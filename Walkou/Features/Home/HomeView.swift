import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]
    @AppStorage(SettingsKey.goalSteps) private var goalSteps = 6000
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers

    @State private var todaySteps: Int?
    @State private var week: [DaySteps] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    todayCard
                    NavigationLink {
                        PantryView()
                    } label: {
                        MascotCard(jars: SweatJar.lifetimeSealed(workouts), workedOutToday: workoutStepsToday > 0)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        GemCollectionView()
                    } label: {
                        GemLevelCard(points: lifetimeGemPoints, recentKinds: recentGemKinds)
                    }
                    .buttonStyle(.plain)
                    startCard
                    weekCard
                    recentCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadSteps() }
            .refreshable { await loadSteps() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("Home")
                    .font(.system(size: 34, weight: .bold))
            }
            Spacer()
            Button {
                model.selectedTab = .start
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Start a workout")
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        let steps = todaySteps ?? workoutStepsToday
        let progress = goalSteps > 0 ? Double(steps) / Double(goalSteps) : 0
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Today", systemImage: "shoeprints.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(Format.steps(steps))
                    .font(.hero(52))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("of \(Format.steps(goalSteps)) steps · \(Format.distance(ActivityType.walk.distance(forSteps: steps), unit: unit))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                TodayJarView(fill: progress)
                    .frame(height: 92)
                Text("\(Int(min(progress, 9.99) * 100))%")
                    .font(.number(15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .card(Theme.indigo, padding: 22)
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready for \(Format.steps(goalSteps)) steps?")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
            Text("Get three routes that match your goal, or go free and we'll tell you when to turn back.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
            ArrowCapsuleButton(title: "Find a route") {
                model.selectedTab = .start
            }
            .padding(.top, 8)
        }
        .card(Theme.green, padding: 24)
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "figure.walk", title: "Steps this week")
            let total = week.reduce(0) { $0 + $1.steps }
            Text(Format.steps(total))
                .font(.system(size: 32, weight: .bold))
            if week.isEmpty {
                Text("Your daily steps will show up here.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Chart {
                    ForEach(week) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Steps", day.steps),
                            width: .fixed(14)
                        )
                        .cornerRadius(7)
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.indigo : Theme.indigo.opacity(0.35))
                    }
                    RuleMark(y: .value("Goal", goalSteps))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
            }
        }
        .card()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.selectedTab = .activity
            } label: {
                CardHeader(symbol: "medal.fill", title: "Recent activity", showsArrow: !workouts.isEmpty)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            if workouts.isEmpty {
                HStack(spacing: 14) {
                    BadgeIcon(symbol: "flag.fill", colors: [Theme.orange, Color(hex: 0xFF5A7A)], size: 52)
                    Text("Your first workout is one tap away. Pick a goal and go!")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                ForEach(Array(workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout, unit: unit)
                    }
                    .buttonStyle(.plain)
                    if index < min(workouts.count, 3) - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Data

    private var lifetimeGemPoints: Int {
        workouts.reduce(0) { $0 + $1.gemPoints }
    }

    /// Gem kinds from recent workouts, rarest first, for the level card.
    private var recentGemKinds: [GemKind] {
        var kinds: [GemKind] = []
        for workout in workouts.prefix(10) {
            let tally = workout.gemTally
            for kind in [GemKind.legendary, .heart, .amber, .rare, .bonus, .common] where tally[kind] > 0 && !kinds.contains(kind) {
                kinds.append(kind)
            }
            if kinds.count >= 5 { break }
        }
        return kinds
    }

    private var workoutStepsToday: Int {
        workouts.filter { Calendar.current.isDateInToday($0.startDate) }.reduce(0) { $0 + $1.steps }
    }

    private func loadSteps() async {
        let pedometer = PedometerService()
        if let daily = await pedometer.dailySteps(days: 7) {
            week = daily.map { DaySteps(date: $0.day, steps: $0.steps) }
            todaySteps = daily.last?.steps
        } else {
            // No motion data (e.g. simulator): fall back to recorded workouts.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            week = (0..<7).reversed().compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let steps = workouts.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.reduce(0) { $0 + $1.steps }
                return DaySteps(date: day, steps: steps)
            }
            todaySteps = nil
        }
    }
}

struct DaySteps: Identifiable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

/// Moodboard-style activity row: medal, date, big number, subtitle.
struct WorkoutRow: View {
    let workout: WorkoutRecord
    let unit: DistanceUnit

    var body: some View {
        HStack(spacing: 16) {
            BadgeIcon(
                symbol: workout.goalReached ? "trophy.fill" : workout.activity.symbol,
                colors: workout.goalReached
                    ? [Color(hex: 0xFFB020), Theme.orange]
                    : (workout.activity == .run ? [Theme.blue, Theme.indigo] : [Theme.indigo, Color(hex: 0x8B5CF6)]),
                size: 60
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.startDate.formatted(.relative(presentation: .named)).capitalizedFirst)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(Format.distanceValue(workout.distanceMeters, unit: unit)) \(unit.abbreviation.uppercased())")
                    .font(.system(size: 26, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let steps = "\(Format.steps(workout.steps)) steps"
        if workout.goalReached {
            return "\(workout.title) · \(steps). Goal reached, you rock!"
        }
        return "\(workout.title) · \(steps) of \(Format.steps(workout.goalSteps))"
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
