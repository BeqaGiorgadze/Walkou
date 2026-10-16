import SwiftUI
import SwiftData
import MapKit

/// Shown after finishing: big numbers, the path walked, and saving to history / Apple Health.
struct WorkoutSummaryView: View {
    let session: WorkoutSession

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = false

    @State private var saved = false
    @State private var healthStatus: HealthStatus = .idle
    @State private var lifetimePointsBefore = 0
    @State private var jarsBefore = 0
    @State private var levelUp: GemLevel?
    @State private var showCollection = false

    private enum HealthStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private var unit: DistanceUnit { session.unit }
    private var duration: TimeInterval { session.elapsed() }
    private var hasData: Bool { session.steps > 0 || session.distance > 10 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if session.track.count > 1 {
                    TrackMap(coordinates: session.track.map(\.coordinate), plannedRoute: session.plannedRoute?.coordinates)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                goalCard
                if hasData {
                    SweatJarCard(
                        steps: session.steps,
                        goal: session.plan.goalSteps,
                        activity: session.plan.activity,
                        date: session.startDate ?? Date(),
                        jarsBefore: jarsBefore
                    )
                }
                if !session.gems.isEmpty {
                    GemHaulCard(
                        collected: { session.gemsCollected($0) },
                        available: { session.gemsAvailable($0) },
                        // Crystal points are shown on the jar card.
                        points: session.gemPoints - session.gemTally[.crystal] * GemKind.crystal.points,
                        bonusSteps: session.bonusSteps,
                        bonusDetours: session.gems.filter { $0.isCollected && $0.detourSteps != nil }.count,
                        lifetimePoints: lifetimePointsBefore + session.gemPoints
                    )
                }
                stats
                healthRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button("DONE") { model.activeSession = nil }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
        }
        .task { await persist() }
        .overlay {
            if let levelUp {
                LevelUpView(
                    level: levelUp,
                    points: lifetimePointsBefore + session.gemPoints,
                    onDone: { withAnimation(.easeInOut) { self.levelUp = nil } },
                    onCollection: {
                        withAnimation(.easeInOut) { self.levelUp = nil }
                        showCollection = true
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .sheet(isPresented: $showCollection) {
            NavigationStack {
                GemCollectionView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showCollection = false }
                        }
                    }
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
            Text(Format.distanceValue(session.distance, unit: unit))
                .font(.hero(96))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit.title)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var goalCard: some View {
        HStack(spacing: 16) {
            BadgeIcon(
                symbol: session.goalReached ? "trophy.fill" : "shoeprints.fill",
                colors: session.goalReached ? [Color(hex: 0xFFD25A), Theme.orange] : [Theme.indigo, Color(hex: 0x8B5CF6)],
                size: 64
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.steps(session.steps) + " Steps")
                    .font(.system(size: 26, weight: .bold))
                Text(goalMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(session.goalReached ? Color.white.opacity(0.9) : Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(session.goalReached ? Color.white : Color.primary)
        .card(session.goalReached ? Theme.green : Theme.card)
    }

    private var stats: some View {
        VStack(spacing: 0) {
            StatRow(symbol: "timer", title: "Time", value: Format.duration(duration))
            StatRow(symbol: "figure.run", title: "Avg Pace", value: Format.pace(distance: session.distance, duration: duration, unit: unit) + " /\(unit.abbreviation)")
            StatRow(symbol: "flame", title: "Calories", value: Format.calories(session.calories))
            StatRow(symbol: "mountain.2", title: "Elevation Gain", value: Format.elevation(session.elevationGain, unit: unit), showsDivider: false)
        }
        .padding(.vertical, 4)
        .card(padding: 20)
    }

    @ViewBuilder
    private var healthRow: some View {
        if saveToHealth && hasData {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xFF2D55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                switch healthStatus {
                case .idle, .saving:
                    Text("Saving to Apple Health…")
                    Spacer()
                    ProgressView()
                case .saved:
                    Text("Saved to Apple Health")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
            .font(.system(size: 16, weight: .medium))
            .card()
        } else if !hasData {
            Text("Nothing was recorded, so this workout wasn't saved.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .card()
        }
    }

    // MARK: - Text

    private var title: String {
        let hour = Calendar.current.component(.hour, from: session.startDate ?? Date())
        let part: String
        switch hour {
        case 5..<12: part = "Morning"
        case 12..<17: part = "Afternoon"
        case 17..<22: part = "Evening"
        default: part = "Night"
        }
        return "\(part) \(session.plan.activity.title)"
    }

    private var goalMessage: String {
        if session.goalReached {
            let extra = session.steps - session.plan.goalSteps
            return extra > 50
                ? "Goal smashed with \(Format.steps(extra)) bonus steps. You rock!"
                : "Goal of \(Format.steps(session.plan.goalSteps)) reached. You rock!"
        }
        return "\(Format.steps(session.remainingSteps)) steps short of \(Format.steps(session.plan.goalSteps)). Next time!"
    }

    // MARK: - Saving

    private func persist() async {
        guard !saved else { return }
        let earlier = (try? modelContext.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        lifetimePointsBefore = earlier.reduce(0) { $0 + $1.gemPoints }
        jarsBefore = SweatJar.lifetimeSealed(earlier)
        guard hasData, let start = session.startDate else { return }
        saved = true
        let end = session.endDate ?? Date()

        let record = WorkoutRecord(
            startDate: start,
            endDate: end,
            activity: session.plan.activity,
            mode: session.plan.mode,
            goalSteps: session.plan.goalSteps,
            steps: session.steps,
            distanceMeters: session.distance,
            duration: duration,
            calories: session.calories,
            elevationGain: session.elevationGain,
            routeName: session.plannedRoute?.name,
            track: session.track.map(\.coordinate),
            gemTally: session.gemTally,
            gemsAvailable: session.gems.count,
            bonusSteps: session.bonusSteps
        )
        modelContext.insert(record)
        try? modelContext.save()

        let before = GemLevel.forPoints(lifetimePointsBefore)
        let after = GemLevel.forPoints(lifetimePointsBefore + session.gemPoints)
        if after.number > before.number {
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { levelUp = after }
            }
        }

        guard saveToHealth else { return }
        healthStatus = .saving
        do {
            try await HealthKitService.shared.save(
                activity: session.plan.activity,
                start: start,
                end: end,
                distance: session.distance,
                steps: session.steps,
                calories: session.calories,
                locations: session.track
            )
            record.savedToHealth = true
            try? modelContext.save()
            healthStatus = .saved
        } catch {
            healthStatus = .failed("Couldn't save to Apple Health. \((error as? LocalizedError)?.errorDescription ?? "")")
        }
    }
}

/// Non-interactive map of a recorded path (with the planned route underneath when there was one).
struct TrackMap: View {
    let coordinates: [CLLocationCoordinate2D]
    var plannedRoute: [CLLocationCoordinate2D]? = nil

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: []) {
            if let plannedRoute, plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(Theme.indigo.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.indigo, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            if let first = coordinates.first {
                Annotation("Start", coordinate: first) {
                    Circle().fill(Theme.green).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                }
            }
            if let last = coordinates.last {
                Annotation("End", coordinate: last) {
                    Circle().fill(Theme.danger).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    private var initialPosition: MapCameraPosition {
        let all = coordinates + (plannedRoute ?? [])
        guard !all.isEmpty else { return .automatic }
        let rect = MKPolyline(coordinates: all, count: all.count).boundingMapRect
        let padded = rect.insetBy(dx: -max(rect.width * 0.2, 300), dy: -max(rect.height * 0.2, 300))
        return .rect(padded)
    }
}
