import SwiftUI
import CoreMotion

/// Kou on their own, animated.
struct MascotView: View {
    var pose: MascotPose = .idle
    let stage: MascotStage
    var sweat: Double = 0
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, size in
                MascotRenderer.draw(
                    in: context,
                    rect: MascotRenderer.fittedRect(in: size),
                    pose: pose,
                    stage: stage,
                    sweat: sweat,
                    time: animated ? timeline.date.timeIntervalSinceReferenceDate : 0.4
                )
            }
        }
        .aspectRatio(MascotRenderer.designSize.width / MascotRenderer.designSize.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(MascotStage.name), \(stage.title)")
    }
}

/// A sweat jar. Animated jars slosh gently; `tilt` makes the liquid stay level as the phone tilts.
struct SweatJarView: View {
    let fill: Double
    var liquid: Color = Color(hex: 0x4FC3FF)
    var sealed = false
    var label: String?
    var onDark = false
    var animated = false
    var tilt: JarTilt?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, size in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                let rect = jarRect(in: size)
                SweatJarRenderer.draw(
                    in: context,
                    rect: rect,
                    fill: sealed ? 1 : fill,
                    style: .init(onDark: onDark, liquid: liquid),
                    time: t,
                    wave: animated ? 1 + (tilt?.wobble ?? 0) : 0.8,
                    slope: tilt.map { -tan($0.angle) } ?? 0,
                    sealed: sealed,
                    label: label
                )
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(sealed ? "Sealed sweat jar" : "Sweat jar \(Int(min(fill, 1) * 100)) percent full")
    }

    private func jarRect(in size: CGSize) -> CGRect {
        // Leave room above for the lid.
        CGRect(x: 2, y: 4, width: size.width - 4, height: size.height - 6)
    }
}

/// Reads the phone's tilt so jar liquid stays level, and sloshes when the phone moves.
/// Plain class on purpose: the jar's TimelineView polls it every frame, so nothing else re-renders.
final class JarTilt {
    /// Phone roll in radians, smoothed and clamped (positive = turned clockwise).
    private(set) var angle: Double = 0
    /// Extra wave height from recent movement.
    private(set) var wobble: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Lying flat there's no meaningful roll, so fade the effect out.
            let strength = min(1, hypot(gravity.x, gravity.y) / 0.5)
            let target = max(-0.7, min(0.7, atan2(gravity.x, -gravity.y))) * strength
            let delta = target - self.angle
            self.angle += delta * 0.25
            self.wobble = min(5, self.wobble * 0.93 + abs(delta) * 10)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        angle = 0
        wobble = 0
    }
}

// MARK: - Live workout

/// Bottom-panel companion during a workout: Kou walks or runs, sweat flies into the jar,
/// and the jar fills toward the goal. A sealed jar gets its lid and Kou cheers.
struct SweatBuddyView: View {
    /// Pose from the workout state; drops to idle when you stop moving, and cheers right after a seal.
    let basePose: MascotPose
    let stage: MascotStage
    let sweat: Double
    let jarFill: Double
    let liquid: Color
    let sealedJars: Int
    let lastSeal: Date?
    let lastMove: Date?

    private static let cheerDuration = 3.5
    private static let lidDuration = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: basePose == .ready)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, date: timeline.date)
            }
        }
        .overlay(alignment: .topLeading) {
            if sealedJars > 0 {
                Text("🫙×\(sealedJars)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.navBackground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.mint, in: Capsule())
                    .offset(x: -2, y: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Sweat jar \(Int(min(jarFill, 1) * 100)) percent full, \(sealedJars) sealed")
    }

    private func pose(at date: Date) -> MascotPose {
        if let lastSeal, date.timeIntervalSince(lastSeal) < Self.cheerDuration { return .cheer }
        if basePose == .walk || basePose == .run {
            guard let lastMove, date.timeIntervalSince(lastMove) < 8 else { return .idle }
        }
        return basePose
    }

    private func draw(in context: GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate
        let pose = pose(at: date)

        // Layout: jar on the left, Kou on the right facing the numbers.
        let jarRect = CGRect(x: 2, y: size.height * 0.33, width: size.width * 0.34, height: size.height * 0.65)
        let mascotHeight = size.height
        let mascotWidth = mascotHeight * MascotRenderer.designSize.width / MascotRenderer.designSize.height
        let mascotRect = CGRect(x: size.width - mascotWidth, y: 0, width: mascotWidth, height: mascotHeight)
        let scale = mascotRect.width / MascotRenderer.designSize.width
        let origin = CGPoint(x: mascotRect.minX + MascotRenderer.dropOrigin.x * scale, y: mascotRect.minY + MascotRenderer.dropOrigin.y * scale)
        let mouth = CGPoint(x: jarRect.midX, y: jarRect.minY + 2)

        // Flying sweat: one drop every interval, each flying for `life` seconds in an arc.
        let moving = pose == .walk || pose == .run
        let interval = pose == .run ? 0.75 : 1.5
        let life = 0.8
        var splash = 0.0
        if moving {
            let newest = Int(floor(t / interval))
            for i in max(0, newest - 2)...newest {
                let age = t - Double(i) * interval
                if age >= life {
                    // Recently landed drops make the surface jump.
                    splash = max(splash, 1.8 * exp(-(age - life) * 5))
                    continue
                }
                guard age >= 0 else { continue }
                let p = age / life
                let jitter = pseudoRandom(i) * 6 - 3
                let x = origin.x + (mouth.x - origin.x) * p
                let y = origin.y + jitter * (1 - p) + (mouth.y - origin.y) * p - 22 * 4 * p * (1 - p)
                var drop = context
                drop.opacity = min(1, age / 0.12)
                drop.fill(MascotRenderer.dropPath(center: CGPoint(x: x, y: y), size: 3.2 * (1 - 0.3 * p)), with: .color(MascotRenderer.sweat))
            }
        }

        // Jar: right after a seal, show the full jar with its lid dropping on.
        let sealAge = lastSeal.map { date.timeIntervalSince($0) } ?? .infinity
        let showingSeal = sealAge < Self.lidDuration || sealedJars >= SweatJar.maxPerWorkout
        let wave = (pose == .run ? 2.6 : (moving ? 1.6 : 0.8)) + splash
        if showingSeal {
            let drop = CGFloat(max(0, 1 - sealAge / 0.35)) * 14
            SweatJarRenderer.draw(in: context, rect: jarRect, fill: 1, style: .init(onDark: true, liquid: liquid), time: t,
                                  wave: 0.6, sealed: true, lidDrop: sealAge.isFinite ? drop : 0)
            if sealAge < Self.lidDuration {
                drawSparkles(in: context, around: jarRect, age: sealAge)
            }
        } else {
            SweatJarRenderer.draw(in: context, rect: jarRect, fill: jarFill, style: .init(onDark: true, liquid: liquid), time: t, wave: wave)
        }

        MascotRenderer.draw(in: context, rect: mascotRect, pose: pose, stage: stage, sweat: sweat, time: t)
    }

    private func drawSparkles(in context: GraphicsContext, around rect: CGRect, age: Double) {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(-0.15, 0.1, 10), (1.1, 0.0, 12), (1.05, 0.6, 8), (-0.1, 0.7, 7)]
        for (index, spot) in spots.enumerated() {
            let local = age - Double(index) * 0.12
            guard local > 0 else { continue }
            let scale = CGFloat(sin(min(1, local / 0.9) * .pi))
            let size = spot.2 * scale
            let center = CGPoint(x: rect.minX + rect.width * spot.0, y: rect.minY + rect.height * spot.1)
            context.fill(SparkleShape().path(in: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)),
                         with: .color(Color(hex: 0xFFE59A)))
        }
    }

    private func pseudoRandom(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898) * 43758.5453
        return value - value.rounded(.down)
    }
}

// MARK: - Home

/// Home card: Kou, their stage and how many jars until the next look.
struct MascotCard: View {
    let jars: Int
    let workedOutToday: Bool

    var body: some View {
        let stage = MascotStage.forJars(jars)
        HStack(spacing: 16) {
            MascotView(pose: workedOutToday ? .cheer : .idle, stage: stage)
                .frame(width: 84, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(MascotStage.name.uppercased()) · \(stage.title.uppercased())")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.mint)
                    Text(jars == 1 ? "1 jar sealed" : "\(Format.steps(jars)) jars sealed")
                        .font(.hero(26))
                        .foregroundStyle(.white)
                }
                if let next = stage.next {
                    ProgressBar(progress: stage.progress(jars: jars), tint: Theme.mint, track: .white.opacity(0.15), height: 8)
                    Text("\(next.jarsNeeded - jars) more for \(next.unlock.lowercased())")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Kou is a legend. So are you.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.navSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Today's jar on the Home card. Tilt the phone and the sweat sloshes.
struct TodayJarView: View {
    let fill: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Created on appear so re-rendering Home never makes extra motion managers.
    @State private var tilt: JarTilt?

    var body: some View {
        SweatJarView(
            fill: min(fill, 1),
            liquid: Color(hex: 0x6FE3C8),
            sealed: fill >= 1,
            label: fill >= 1 ? "TODAY" : nil,
            onDark: true,
            animated: !reduceMotion,
            tilt: tilt
        )
        .onAppear {
            guard !reduceMotion else { return }
            let tilt = self.tilt ?? JarTilt()
            self.tilt = tilt
            tilt.start()
        }
        .onDisappear { tilt?.stop() }
    }
}

// MARK: - Workout summary

/// Summary card: the jar(s) this workout filled, the crystals they made and Kou's progress.
struct SweatJarCard: View {
    let steps: Int
    let goal: Int
    let activity: ActivityType
    let date: Date
    let jarsBefore: Int

    @Environment(\.colorScheme) private var colorScheme

    private var sealed: Int { SweatJar.sealed(steps: steps, goal: goal) }
    private var remainder: Double { SweatJar.currentJarFill(steps: steps, goal: goal) }

    var body: some View {
        let before = MascotStage.forJars(jarsBefore)
        let after = MascotStage.forJars(jarsBefore + sealed)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<max(1, sealed), id: \.self) { index in
                    jar(sealed: index < sealed, fill: index < sealed ? 1 : remainder)
                }
                if sealed > 0, sealed < SweatJar.maxPerWorkout, remainder > 0.02 {
                    jar(sealed: false, fill: remainder)
                }
                Spacer(minLength: 0)
                MascotView(pose: sealed > 0 ? .cheer : .idle, stage: after, sweat: 0.8)
                    .frame(width: 70, height: 84)
            }
            .frame(height: 90)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }

            if after.number > before.number {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("NEW LOOK: \(after.unlock). Kou is now \(after.title)!")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Theme.navBackground)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let next = after.next {
                let total = jarsBefore + sealed
                Text("\(next.jarsNeeded - total) more \(next.jarsNeeded - total == 1 ? "jar" : "jars") until Kou gets: \(next.unlock.lowercased())")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.indigo)
            }
        }
        .card()
    }

    private func jar(sealed: Bool, fill: Double) -> some View {
        SweatJarView(
            fill: fill,
            liquid: SweatJar.liquid(for: activity),
            sealed: sealed,
            label: sealed ? SweatJar.label(for: date) : nil,
            onDark: colorScheme == .dark
        )
        .frame(height: 84)
    }

    private var title: String {
        switch sealed {
        case 0: return "Jar \(Int(remainder * 100))% full"
        case 1: return "Jar sealed!"
        default: return "\(sealed) jars sealed!"
        }
    }

    private var subtitle: String {
        if sealed == 0 { return "Reach your goal to seal the jar. It turns into a Sweat Crystal." }
        let points = sealed * GemKind.crystal.points
        return sealed == 1
            ? "Your sweat crystallized into a Sweat Crystal · +\(points) pts"
            : "Your sweat crystallized into \(sealed) Sweat Crystals · +\(points) pts"
    }
}
