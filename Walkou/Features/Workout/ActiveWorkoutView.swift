import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// The live screen: dark navigation map, next turn, steps toward the goal and controls.
struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(AppModel.self) private var model
    @Query private var workouts: [WorkoutRecord]
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showEndDialog = false
    /// Last position the camera was moved to while following the autopilot.
    @State private var followedCenter: CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            WorkoutMap(session: session, camera: $camera)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topArea
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        MapControlButton(symbol: session.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                            session.toggleVoice()
                        }
                        .accessibilityLabel(session.voiceEnabled ? "Mute voice guidance" : "Unmute voice guidance")
                        MapControlButton(
                            symbol: camera.followsUserLocation ? "location.north.line.fill" : "location.fill",
                            tint: camera.followsUserLocation ? Theme.mint : .white
                        ) {
                            withAnimation { camera = .userLocation(followsHeading: true, fallback: .automatic) }
                        }
                        .accessibilityLabel("Center on my location")
                    }
                    .padding(.trailing, 16)
                }
                bottomPanel
            }

            if let event = session.lastCollect {
                GemCollectBurst(event: event)
                    .offset(y: -90)
                    .id(event.id)
            }

            if case .countdown(let value) = session.phase {
                CountdownOverlay(value: value)
                    .transition(.opacity)
            }

            if session.showCelebration {
                CelebrationView(
                    goalSteps: session.plan.goalSteps,
                    stage: mascotStage,
                    liquid: SweatJar.liquid(for: session.plan.activity),
                    onKeepGoing: {
                        withAnimation(.spring) { session.showCelebration = false }
                    },
                    onFinish: {
                        session.showCelebration = false
                        session.finish()
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.4), value: session.showCelebration)
        .animation(.easeInOut, value: isCountingDown)
        .confirmationDialog("End workout?", isPresented: $showEndDialog, titleVisibility: .visible) {
            Button("Finish & save") { session.finish() }
            Button("Discard", role: .destructive) {
                session.finish()
                model.activeSession = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(session.goalReached ? "Goal reached. Nice work!" : "\(Format.steps(session.remainingSteps)) steps left to your goal.")
        }
        .persistentSystemOverlays(.hidden)
        .onChange(of: session.currentLocation?.timestamp) { _, _ in
            // Follow the autopilot, since "follow user location" tracks the real GPS.
            // Only move the camera after real movement, never during the countdown,
            // so the map isn't asked to re-position on every update.
            guard session.isSimulated, !isCountingDown, let here = session.currentLocation?.coordinate else { return }
            if let followedCenter, Geo.distance(followedCenter, here) < 4 { return }
            followedCenter = here
            camera = .camera(MapCamera(centerCoordinate: here, distance: 900, heading: 0, pitch: 0))
        }
    }

    private var isCountingDown: Bool {
        if case .countdown = session.phase { return true }
        return false
    }

    /// Kou's look includes the jars sealed in this workout.
    private var mascotStage: MascotStage {
        MascotStage.forJars(SweatJar.lifetimeSealed(workouts) + session.sealedJars)
    }

    private var mascotPose: MascotPose {
        switch session.phase {
        case .countdown: return .ready
        case .paused: return .rest
        case .finished: return .idle
        case .active:
            let speed = session.currentLocation?.speed ?? -1
            if session.plan.activity == .run { return speed < 0 || speed > 1.2 ? .run : .walk }
            return speed > 2.6 ? .run : .walk
        }
    }

    // MARK: - Top

    @ViewBuilder
    private var topArea: some View {
        VStack(spacing: 10) {
            if session.isSimulated, let speed = session.simulation?.speedMultiplier {
                Text("SIMULATED WALK · \(Int(speed))×\(session.simulation?.noisyGPS == true ? " · NIGHT GPS" : "")")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.navBackground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xFFD25A), in: Capsule())
            }
            if let navigation = session.navigation, navigation.isOffRoute {
                OffRouteBanner(distance: navigation.distanceFromRoute, unit: session.unit, hasDetour: session.detour != nil)
            } else if session.routeFinished {
                InfoBanner(symbol: "flag.checkered", title: session.plan.mode == .free ? "Back at your start" : "Route complete",
                           detail: session.goalReached ? "Goal reached. Keep going or finish up." : "\(Format.steps(session.remainingSteps)) steps to your goal.")
            } else if session.guidedRoute != nil, let navigation = session.navigation, let next = navigation.nextInstruction,
                      let distance = navigation.distanceToNextInstruction {
                InstructionBanner(instruction: next, distance: distance, unit: session.unit, onClose: stopGuidanceAction)
            } else if session.guidedRoute != nil {
                InfoBanner(symbol: "location.north.line.fill", title: session.guidedRoute?.name ?? "Your route",
                           detail: "Head to the start of the route to begin.")
            } else {
                freeBanner
            }

            if !session.gems.isEmpty {
                HStack {
                    Spacer()
                    GemCounterPill(collected: session.collectedGemCount, total: session.gems.count, points: session.gemPoints,
                                   nearestDistance: session.nearestGemDistance, unit: session.unit)
                }
            }

            if session.showHalfwayCard {
                HalfwayCard(
                    goldGemWaiting: session.goldGemAtStart,
                    isLoading: session.isFindingWayBack,
                    onGuideBack: { session.guideBackToStart() },
                    onDismiss: { withAnimation { session.showHalfwayCard = false } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let error = session.wayBackError {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.snappy, value: session.showHalfwayCard)
    }

    /// Only free workouts can drop the "back to start" guidance.
    private var stopGuidanceAction: (() -> Void)? {
        guard session.plan.mode == .free else { return nil }
        return { session.stopGuidance() }
    }

    private var freeBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: session.plan.activity.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.navBackground)
                .frame(width: 48, height: 48)
                .background(Theme.mint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Free \(session.plan.activity.title.lowercased())")
                    .font(.system(size: 18, weight: .bold))
                if let back = session.distanceBackToStart {
                    Text("\(Format.shortDistance(back, unit: session.unit)) from your start")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Go anywhere. We'll count every step.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            if session.halfwayReached, (session.distanceBackToStart ?? 0) > 50 {
                Button {
                    session.guideBackToStart()
                } label: {
                    if session.isFindingWayBack {
                        ProgressView().tint(Theme.navBackground)
                    } else {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(Theme.navBackground)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .accessibilityLabel("Guide me back to start")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Theme.navSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Bottom

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                SweatBuddyView(
                    basePose: mascotPose,
                    stage: mascotStage,
                    sweat: min(1, 0.15 + session.goalProgress * 1.1),
                    jarFill: session.currentJarFill,
                    liquid: SweatJar.liquid(for: session.plan.activity),
                    sealedJars: session.sealedJars,
                    lastSeal: session.lastJarSeal,
                    lastMove: session.lastMoveDate
                )
                .frame(width: 124, height: 88)

                VStack(alignment: .leading, spacing: 0) {
                    Text("STEPS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(Format.steps(session.steps))
                        .font(.hero(44))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(session.steps)))
                        .animation(.snappy, value: session.steps)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(session.goalReached ? "Goal of \(Format.steps(session.plan.goalSteps)) reached!" : "of \(Format.steps(session.plan.goalSteps)) · \(Format.steps(session.remainingSteps)) to go")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = session.elapsed(at: context.date)
                HStack(spacing: 8) {
                    MetricTile(title: "Distance", value: Format.distanceValue(session.distance, unit: session.unit), unit: session.unit.abbreviation)
                    MetricTile(title: "Time", value: Format.duration(elapsed))
                    MetricTile(title: "Pace", value: Format.pace(distance: session.distance, duration: elapsed, unit: session.unit))
                    if let navigation = session.navigation, session.guidedRoute != nil {
                        MetricTile(title: "Route left", value: Format.shortDistance(navigation.remaining, unit: session.unit))
                    } else {
                        MetricTile(title: "Calories", value: Format.calories(session.calories))
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    showEndDialog = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Theme.danger, in: Circle())
                }
                .accessibilityLabel("End workout")

                Button {
                    Haptics.tap()
                    if session.phase == .paused { session.resume() } else { session.pause() }
                } label: {
                    Label(session.phase == .paused ? "RESUME" : "PAUSE",
                          systemImage: session.phase == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(PrimaryButtonStyle(background: session.phase == .paused ? Theme.mint : .white, foreground: Theme.navBackground))
                .disabled(!(session.phase == .active || session.phase == .paused))
            }
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Theme.navSurface.opacity(0.97))
                .ignoresSafeArea(edges: .bottom)
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Map

private struct WorkoutMap: View {
    let session: WorkoutSession
    @Binding var camera: MapCameraPosition

    var body: some View {
        Map(position: $camera) {
            if session.guidedRoute != nil {
                if session.walkedPath.count > 1 {
                    MapPolyline(coordinates: session.walkedPath)
                        .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                if session.remainingPath.count > 1 {
                    MapPolyline(coordinates: session.remainingPath)
                        .stroke(Theme.mint.opacity(0.22), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: session.remainingPath)
                        .stroke(Theme.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                if let end = session.guidedRoute?.end, session.guidedRoute?.kind != .loop {
                    Annotation("Finish", coordinate: end) {
                        RoutePin(symbol: "flag.checkered", color: Theme.mintDeep)
                    }
                }
            } else if session.mapTrack.count > 1 {
                MapPolyline(coordinates: session.mapTrack)
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }

            ForEach(session.gems.filter { !$0.isCollected && !$0.detourPath.isEmpty }) { gem in
                MapPolyline(coordinates: gem.detourPath)
                    .stroke(Color(hex: 0x3EE08A), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
            }

            ForEach(session.gems.filter { !$0.isCollected }) { gem in
                Annotation("", coordinate: gem.coordinate, anchor: .center) {
                    MapGem(gem: gem)
                }
                .annotationTitles(.hidden)
            }

            if let detour = session.detour {
                MapPolyline(coordinates: detour.coordinates)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [1, 10]))
            }

            if let start = session.startCoordinate ?? session.guidedRoute?.start {
                Annotation("Start", coordinate: start) {
                    RoutePin(symbol: "house.fill", color: Theme.indigo)
                }
            }

            if session.isSimulated {
                // The real location doesn't move during a simulated walk; draw the autopilot instead.
                if let here = session.currentLocation?.coordinate {
                    Annotation("", coordinate: here, anchor: .center) {
                        Circle()
                            .fill(Theme.mint)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .background(Circle().fill(Theme.mint.opacity(0.25)).frame(width: 44, height: 44))
                    }
                    .annotationTitles(.hidden)
                }
            } else {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

// MARK: - Banners

private struct InstructionBanner: View {
    let instruction: NavigationInstruction
    let distance: Double
    let unit: DistanceUnit
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: instruction.symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.navBackground)
                .frame(width: 58, height: 58)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.shortDistance(distance, unit: unit))
                    .font(.number(28, weight: .bold))
                    .contentTransition(.numericText())
                Text(instruction.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Stop guidance")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Theme.navSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

private struct OffRouteBanner: View {
    let distance: Double
    let unit: DistanceUnit
    let hasDetour: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.orange)
                .frame(width: 52, height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Off route")
                    .font(.system(size: 20, weight: .bold))
                Text(hasDetour
                     ? "Follow the dashed line back · \(Format.shortDistance(distance, unit: unit)) away"
                     : "Finding the way back… \(Format.shortDistance(distance, unit: unit)) from the route")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct InfoBanner: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.navBackground)
                .frame(width: 48, height: 48)
                .background(Theme.mint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 18, weight: .bold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Theme.navSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A gem on the live map. The gold gem waiting at your start pulses.
private struct MapGem: View {
    let gem: Gem
    @State private var pulse = false

    var body: some View {
        ZStack {
            if gem.kind == .legendary && gem.distanceIntoRoute == nil {
                Circle()
                    .fill(Color(hex: 0xFFC53D).opacity(0.22))
                    .overlay(Circle().strokeBorder(Color(hex: 0xFFC53D).opacity(0.5), lineWidth: 1.5))
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1 : 0.55)
                    .opacity(pulse ? 0.2 : 1)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
                    }
            }
            GemImage(kind: gem.kind, size: gem.kind.mapSize)
        }
    }
}

private struct HalfwayCard: View {
    let goldGemWaiting: Bool
    let isLoading: Bool
    var onGuideBack: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Halfway there! 🎯")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .accessibilityLabel("Keep exploring")
            }
            Text(goldGemWaiting
                 ? "A gold gem just appeared at your start. Head back to grab it and finish your goal at home."
                 : "Turn around now and you'll hit your goal right back where you started.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
            ArrowCapsuleButton(title: isLoading ? "Finding the way…" : "Guide me back", action: onGuideBack)
                .disabled(isLoading)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.indigo, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - Overlays

private struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("\(value)")
                    .font(.hero(160))
                    .foregroundStyle(Theme.mint)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: value)
                Text("GET READY")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
