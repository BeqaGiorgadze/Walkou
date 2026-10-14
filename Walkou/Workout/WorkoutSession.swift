import Foundation
import CoreLocation
import Observation

/// One walk or run from countdown to finish: records steps, distance and the GPS track,
/// follows the chosen route with voice guidance, and fires the halfway / goal milestones.
@MainActor
@Observable
final class WorkoutSession: Identifiable {
    enum Phase: Equatable {
        case countdown(Int)
        case active
        case paused
        case finished
    }

    let id = UUID()
    let plan: WorkoutPlan
    let plannedRoute: PlannedRoute?
    let unit: DistanceUnit

    private(set) var phase: Phase = .countdown(3)
    private(set) var steps = 0
    private(set) var distance: Double = 0
    private(set) var elevationGain: Double = 0
    private(set) var track: [CLLocation] = []
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var startCoordinate: CLLocationCoordinate2D?
    private(set) var currentLocation: CLLocation?

    // Navigation
    private(set) var guidedRoute: PlannedRoute?
    private(set) var navigation: RouteTracker.Snapshot?
    private(set) var walkedPath: [CLLocationCoordinate2D] = []
    private(set) var remainingPath: [CLLocationCoordinate2D] = []
    private(set) var detour: PlannedRoute?
    private(set) var isFindingWayBack = false
    private(set) var routeFinished = false
    var wayBackError: String?

    // Milestones
    private(set) var halfwayReached = false
    private(set) var goalReached = false
    var showHalfwayCard = false
    var showCelebration = false

    // Gem Trail
    private(set) var gems: [Gem] = []
    private(set) var gemTally = GemTally()
    /// Latest collect, drives the pop-and-fly animation.
    private(set) var lastCollect: GemCollectEvent?
    private(set) var goldGemAtStart = false

    private(set) var voiceEnabled: Bool
    let offRouteAlertsEnabled: Bool

    // Dependencies and bookkeeping
    private let location: LocationService
    private let pedometer = PedometerService()
    private let voice = VoiceCoach()
    private let planner = RoutePlanner()
    @ObservationIgnored private var tracker: RouteTracker?
    @ObservationIgnored private var announcedInstructions = Set<Int>()
    @ObservationIgnored private var stepsBeforePause = 0
    @ObservationIgnored private var segmentSteps = 0
    @ObservationIgnored private var activeTimeBeforePause: TimeInterval = 0
    @ObservationIgnored private var segmentStart: Date?
    @ObservationIgnored private var lastAltitude: Double?
    @ObservationIgnored private var lastRecorded: CLLocation?
    @ObservationIgnored private var lastDetourRequest: Date?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var lastGemSpawnDistance: Double = -250
    @ObservationIgnored private var isSpawningGem = false
    @ObservationIgnored private var nextFreeGemID = GemPlanner.freeIDBase

    init(
        plan: WorkoutPlan,
        route: PlannedRoute?,
        location: LocationService,
        unit: DistanceUnit,
        voiceEnabled: Bool,
        offRouteAlertsEnabled: Bool
    ) {
        self.plan = plan
        self.plannedRoute = route
        self.location = location
        self.unit = unit
        self.voiceEnabled = voiceEnabled
        self.offRouteAlertsEnabled = offRouteAlertsEnabled
        voice.isEnabled = voiceEnabled
        if let route {
            setGuidedRoute(route)
            gems = route.gems.isEmpty ? GemPlanner.routeGems(for: route) : route.gems
            if !route.bonusGemsPlaced { placeBonusGems(on: route) }
        }
    }

    // MARK: - Derived values

    var isRecording: Bool { phase == .active }

    var isFinished: Bool { phase == .finished }

    var goalProgress: Double {
        guard plan.goalSteps > 0 else { return 0 }
        return min(1, Double(steps) / Double(plan.goalSteps))
    }

    var remainingSteps: Int { max(0, plan.goalSteps - steps) }

    var calories: Double { distance / 1000 * plan.activity.kilocaloriesPerKilometer }

    var gemPoints: Int { gemTally.points }

    var collectedGemCount: Int { gems.filter(\.isCollected).count }

    /// Extra steps taken for collected bonus detours.
    var bonusSteps: Int { gems.filter { $0.isCollected }.compactMap(\.detourSteps).reduce(0, +) }

    /// Gems available per haul kind, for the summary ("11/12").
    func gemsAvailable(_ kind: GemKind) -> Int { gems.filter { $0.kind.haulKind == kind }.count }

    func gemsCollected(_ kind: GemKind) -> Int { gems.filter { $0.isCollected && $0.kind.haulKind == kind }.count }

    var distanceBackToStart: Double? {
        guard let start = startCoordinate, let here = currentLocation?.coordinate else { return nil }
        return Geo.distance(start, here)
    }

    /// Active time, not counting pauses.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        activeTimeBeforePause + (segmentStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    // MARK: - Lifecycle

    func start() {
        guard case .countdown = phase, countdownTask == nil else { return }
        location.onWorkoutLocations = { [weak self] locations in
            self?.ingest(locations)
        }
        location.startWorkoutTracking()

        countdownTask = Task { [weak self] in
            for value in stride(from: 3, through: 1, by: -1) {
                self?.phase = .countdown(value)
                Haptics.tap()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.beginRecording()
        }
    }

    func pause() {
        guard phase == .active else { return }
        if let segmentStart { activeTimeBeforePause += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        pedometer.stopUpdates()
        stepsBeforePause += segmentSteps
        segmentSteps = 0
        phase = .paused
        voice.say("Workout paused.", interrupt: true)
    }

    func resume() {
        guard phase == .paused else { return }
        let now = Date()
        segmentStart = now
        lastRecorded = nil // don't count distance covered while paused
        startPedometer(from: now)
        phase = .active
        voice.say("Let's keep going.", interrupt: true)
    }

    /// Stops all sensors. The caller saves the result.
    func finish() {
        guard phase != .finished else { return }
        countdownTask?.cancel()
        if let segmentStart { activeTimeBeforePause += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        if startDate == nil { startDate = Date() }
        endDate = Date()
        pedometer.stopUpdates()
        location.stopWorkoutTracking()
        voice.stop()
        phase = .finished
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        voice.isEnabled = voiceEnabled
        if !voiceEnabled { voice.stop() }
    }

    // MARK: - Free mode: guide back to start

    func guideBackToStart() {
        guard let start = startCoordinate, let here = currentLocation?.coordinate, !isFindingWayBack else { return }
        isFindingWayBack = true
        wayBackError = nil
        showHalfwayCard = false
        Task {
            do {
                let route = try await planner.directions(from: here, to: start, name: "Back to start")
                setGuidedRoute(route)
                routeFinished = false
                var message = "Heading back to your start, \(spokenDistance(route.distance)) away."
                if let first = route.instructions.first, first.text != "You've arrived" {
                    message += " \(first.text)."
                    announcedInstructions.insert(first.id)
                }
                voice.say(message)
            } catch {
                wayBackError = (error as? LocalizedError)?.errorDescription ?? "Couldn't find a way back right now."
            }
            isFindingWayBack = false
        }
    }

    func stopGuidance() {
        guard plan.mode == .free else { return }
        guidedRoute = nil
        tracker = nil
        navigation = nil
        walkedPath = []
        remainingPath = []
        detour = nil
    }

    // MARK: - Private

    private func beginRecording() {
        countdownTask = nil
        let now = Date()
        startDate = now
        segmentStart = now
        startCoordinate = location.lastLocation?.coordinate
        phase = .active
        startPedometer(from: now)

        let goal = Format.steps(plan.goalSteps)
        if let route = plannedRoute {
            var message = "Let's go! \(route.name), \(spokenDistance(route.distance))."
            if let first = route.instructions.first {
                message += " \(first.text)."
                announcedInstructions.insert(first.id)
            }
            voice.say(message)
        } else {
            voice.say("Let's go! Free \(plan.activity.title.lowercased()) started. Your goal is \(goal) steps.")
        }
    }

    private func startPedometer(from date: Date) {
        pedometer.startUpdates(from: date) { [weak self] value in
            guard let self, self.phase == .active else { return }
            self.segmentSteps = value
            self.refreshSteps()
        }
    }

    private func setGuidedRoute(_ route: PlannedRoute) {
        guidedRoute = route
        let tracker = RouteTracker(route: route)
        self.tracker = tracker
        announcedInstructions = []
        detour = nil
        walkedPath = []
        remainingPath = route.coordinates
        navigation = nil
    }

    private func ingest(_ locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { continue }
            if startCoordinate == nil { startCoordinate = location.coordinate }

            if phase == .active {
                record(location)
            }
            currentLocation = location
            updateNavigation(with: location)
            checkGems(at: location)
        }
        refreshSteps()
        spawnFreeWalkGemIfNeeded()
    }

    private func record(_ location: CLLocation) {
        if let previous = lastRecorded {
            let delta = location.distance(from: previous)
            // Ignore GPS jitter while standing still.
            guard delta >= 2 else { return }
            distance += delta
        }
        lastRecorded = location
        track.append(location)

        if location.verticalAccuracy > 0, location.verticalAccuracy <= 10 {
            if let lastAltitude {
                let delta = location.altitude - lastAltitude
                if delta > 1.5 {
                    elevationGain += delta
                    self.lastAltitude = location.altitude
                } else if delta < -1.5 {
                    self.lastAltitude = location.altitude
                }
            } else {
                lastAltitude = location.altitude
            }
        }
    }

    private func refreshSteps() {
        let counted = stepsBeforePause + segmentSteps
        // Without motion access (or in the simulator) fall back to the fixed-stride estimate.
        let estimated = plan.activity.steps(forDistance: distance)
        steps = counted > 0 ? counted : (distance > 30 ? estimated : 0)
        checkMilestones()
    }

    private func checkMilestones() {
        guard phase == .active else { return }

        if !halfwayReached, steps >= plan.goalSteps / 2, plan.goalSteps > 0 {
            halfwayReached = true
            if plan.mode == .free {
                showHalfwayCard = true
                if let start = startCoordinate, (distanceBackToStart ?? 0) > 60 {
                    gems.append(GemPlanner.goldGemAtStart(start))
                    goldGemAtStart = true
                }
                voice.say(goldGemAtStart
                    ? "Halfway there! A gold gem just appeared at your start. Head back to grab it and finish your goal."
                    : "Halfway there! If you turn around now, you'll finish your goal right back where you started.")
                NotificationService.notifyIfInBackground(
                    title: "Halfway there! 🎯",
                    body: "Turn around now to finish your \(Format.steps(plan.goalSteps)) steps back at your start."
                )
            } else {
                voice.say("Halfway there. Keep it up!")
            }
        }

        if !goalReached, steps >= plan.goalSteps, plan.goalSteps > 0 {
            goalReached = true
            showCelebration = true
            showHalfwayCard = false
            Haptics.success()
            voice.say("You rock! You just hit \(Format.steps(plan.goalSteps)) steps. Go the extra mile, you can do it!", interrupt: true)
            NotificationService.notifyIfInBackground(
                title: "Goal reached! You rock! 🎉",
                body: "\(Format.steps(plan.goalSteps)) steps done. Go the extra mile, you can do it!"
            )
        }
    }

    private func updateNavigation(with location: CLLocation) {
        guard var tracker else { return }
        let wasOffRoute = navigation?.isOffRoute ?? false
        let snapshot = tracker.update(with: location.coordinate)
        self.tracker = tracker
        navigation = snapshot
        let parts = tracker.split()
        walkedPath = parts.walked
        remainingPath = parts.remaining

        guard phase == .active else { return }

        // Off route / back on route
        if snapshot.isOffRoute {
            if !wasOffRoute, offRouteAlertsEnabled {
                Haptics.warning()
                voice.say("You're off the route. Follow the dashed line to get back.", interrupt: true)
                NotificationService.notifyIfInBackground(title: "Off route", body: "Follow the dashed line on the map to get back on track.")
            }
            requestDetourIfNeeded(from: location, tracker: tracker)
        } else if wasOffRoute {
            detour = nil
            lastDetourRequest = nil
            if offRouteAlertsEnabled { voice.say("You're back on the route.") }
        }

        // Turn-by-turn
        if !snapshot.isOffRoute, let next = snapshot.nextInstruction, let distanceToNext = snapshot.distanceToNextInstruction,
           distanceToNext <= plan.activity.announceDistance, !announcedInstructions.contains(next.id) {
            announcedInstructions.insert(next.id)
            if next.symbol == "flag.checkered" {
                voice.say(next.text)
            } else {
                voice.say("In \(spokenDistance(distanceToNext)), \(next.text.lowercasedFirstLetter)")
            }
        }

        // Route complete
        if snapshot.isComplete, !routeFinished {
            routeFinished = true
            detour = nil
            let isWayBack = plan.mode == .free
            if goalReached {
                voice.say(isWayBack ? "You're back at your start. Amazing work!" : "Route complete. Amazing work!")
            } else {
                let more = Format.steps(remainingSteps)
                voice.say(isWayBack
                    ? "You're back at your start. Just \(more) more steps to reach your goal!"
                    : "Route complete. Just \(more) more steps to reach your goal. Keep moving!")
            }
        }
    }

    // MARK: - Gems

    private func placeBonusGems(on route: PlannedRoute) {
        let stride = plan.activity.strideLength
        Task {
            let bonus = await GemPlanner.bonusGems(for: route, strideLength: stride)
            let existing = Set(gems.map(\.id))
            gems.append(contentsOf: bonus.filter { !existing.contains($0.id) })
        }
    }

    private func checkGems(at location: CLLocation) {
        guard phase == .active, !gems.isEmpty else { return }
        // Gems only count on foot: ignore fixes faster than 25 km/h.
        if location.speed > 7 { return }
        let radius = 25 + min(15, max(0, location.horizontalAccuracy - 10))
        let progress = tracker.map(\.progress)
        for index in gems.indices where !gems[index].isCollected {
            let gem = gems[index]
            guard Geo.distance(location.coordinate, gem.coordinate) <= radius else { continue }
            // On-route gems are reached in order, so a loop's finish gem isn't grabbed at the start.
            if let along = gem.distanceIntoRoute, plannedRoute != nil, guidedRoute?.id == plannedRoute?.id {
                guard let progress, progress >= along - 40 else { continue }
            }
            collect(at: index)
        }
    }

    private func collect(at index: Int) {
        gems[index].isCollected = true
        let kind = gems[index].kind
        gemTally[kind] += 1
        lastCollect = GemCollectEvent(kind: kind, points: kind.points)
        Haptics.gem(kind)
        SoundEffects.play(.forGem(kind))
        if kind == .legendary && goldGemAtStart && gems[index].distanceIntoRoute == nil {
            goldGemAtStart = false
        }
    }

    private func spawnFreeWalkGemIfNeeded() {
        guard plan.mode == .free, phase == .active, !isSpawningGem,
              let here = currentLocation, distance - lastGemSpawnDistance >= 280 else { return }
        let waiting = gems.filter { !$0.isCollected && $0.kind != .legendary }.count
        guard waiting < 3 else { return }
        isSpawningGem = true
        lastGemSpawnDistance = distance
        let id = nextFreeGemID
        nextFreeGemID += 1
        Task {
            if let gem = await GemPlanner.freeWalkGem(near: here, id: id) {
                gems.append(gem)
            }
            isSpawningGem = false
        }
    }

    private func requestDetourIfNeeded(from location: CLLocation, tracker: RouteTracker) {
        let now = Date()
        if let lastDetourRequest, now.timeIntervalSince(lastDetourRequest) < 45 { return }
        guard let target = tracker.coordinate(atDistance: tracker.progress + 80) else { return }
        lastDetourRequest = now
        let origin = location.coordinate
        Task {
            guard let route = try? await planner.directions(from: origin, to: target, name: "Back to route") else { return }
            if self.navigation?.isOffRoute == true {
                self.detour = route
            }
        }
    }

    private func spokenDistance(_ meters: Double) -> String {
        switch unit {
        case .kilometers:
            if meters < 950 { return "\(max(10, Int((meters / 10).rounded()) * 10)) meters" }
            return String(format: "%.1f kilometers", meters / 1000)
        case .miles:
            let feet = meters * 3.28084
            if feet < 1000 { return "\(max(10, Int((feet / 10).rounded()) * 10)) feet" }
            return String(format: "%.1f miles", meters / unit.metersPerUnit)
        }
    }
}

/// One collected gem, used to trigger the collect animation.
struct GemCollectEvent: Equatable, Identifiable {
    let id = UUID()
    let kind: GemKind
    let points: Int
}

private extension String {
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
