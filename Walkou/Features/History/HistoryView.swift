import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your Activity")
                        .font(.system(size: 34, weight: .bold))
                        .padding(.top, 8)

                    if workouts.isEmpty {
                        emptyState
                    } else {
                        totalsCard
                        section("This Week", workouts: thisWeek)
                        section("Earlier", workouts: earlier)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var thisWeek: [WorkoutRecord] {
        workouts.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
    }

    private var earlier: [WorkoutRecord] {
        workouts.filter { !Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
    }

    private var totalsCard: some View {
        let distance = workouts.reduce(0) { $0 + $1.distanceMeters }
        let steps = workouts.reduce(0) { $0 + $1.steps }
        let goals = workouts.filter(\.goalReached).count
        return VStack(alignment: .leading, spacing: 14) {
            Text("ALL TIME")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.distanceValue(distance, unit: unit))
                    .font(.hero(48))
                Text(unit.abbreviation.uppercased())
                    .font(.system(size: 20, weight: .bold))
            }
            HStack {
                total(value: Format.steps(steps), label: "steps")
                total(value: "\(workouts.count)", label: workouts.count == 1 ? "workout" : "workouts")
                total(value: "\(goals)", label: goals == 1 ? "goal hit" : "goals hit")
            }
        }
        .foregroundStyle(.white)
        .card(Theme.indigo, padding: 22)
    }

    private func total(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.number(20, weight: .bold))
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(_ title: String, workouts: [WorkoutRecord]) -> some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 6)
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout, unit: unit)
                    }
                    .buttonStyle(.plain)
                    if index < workouts.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            .card()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            BadgeIcon(symbol: "figure.walk", size: 96)
            Text("No workouts yet")
                .font(.system(size: 22, weight: .bold))
            Text("Finish your first walk or run and it will show up here.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("SET A GOAL") { model.selectedTab = .start }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
        .padding(.vertical, 24)
        .card()
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(workout.startDate.formatted(date: .complete, time: .shortened))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(workout.title)
                        .font(.system(size: 28, weight: .bold))
                    if let routeName = workout.routeName {
                        Text(routeName)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(Format.distanceValue(workout.distanceMeters, unit: unit))
                        .font(.hero(88))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unit.title)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                let track = workout.track
                if track.count > 1 {
                    TrackMap(coordinates: track)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }

                HStack(spacing: 16) {
                    BadgeIcon(
                        symbol: workout.goalReached ? "trophy.fill" : "shoeprints.fill",
                        colors: workout.goalReached ? [Color(hex: 0xFFD25A), Theme.orange] : [Theme.indigo, Color(hex: 0x8B5CF6)],
                        size: 56
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.steps(workout.steps)) Steps")
                            .font(.system(size: 24, weight: .bold))
                        Text(workout.goalReached
                             ? "Goal of \(Format.steps(workout.goalSteps)) reached. You rock!"
                             : "Goal was \(Format.steps(workout.goalSteps)) steps")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .card()

                VStack(spacing: 0) {
                    StatRow(symbol: "timer", title: "Time", value: Format.duration(workout.duration))
                    StatRow(symbol: "figure.run", title: "Avg Pace",
                            value: Format.pace(distance: workout.distanceMeters, duration: workout.duration, unit: unit) + " /\(unit.abbreviation)")
                    StatRow(symbol: "flame", title: "Calories", value: Format.calories(workout.calories))
                    StatRow(symbol: "mountain.2", title: "Elevation Gain", value: Format.elevation(workout.elevationGain, unit: unit),
                            showsDivider: workout.savedToHealth || workout.gemsAvailable > 0)
                    if workout.gemsAvailable > 0 {
                        StatRow(symbol: "diamond.fill", title: "Gems",
                                value: "\(workout.gemTally.total)/\(workout.gemsAvailable) · +\(workout.gemPoints) pts",
                                showsDivider: workout.savedToHealth)
                    }
                    if workout.savedToHealth {
                        StatRow(symbol: "heart.fill", title: "Apple Health", value: "Saved", showsDivider: false)
                    }
                }
                .padding(.vertical, 4)
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete workout")
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(workout)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("It will be removed from Walkou. Anything saved to Apple Health stays there.")
        }
    }
}
