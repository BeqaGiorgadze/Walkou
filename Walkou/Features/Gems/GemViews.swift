import SwiftUI

extension Theme {
    /// Deep purple used behind gem content (haul card, level card, collection).
    static let gemBackground = LinearGradient(
        colors: [Color(hex: 0x1C1850), Color(hex: 0x2D1B5E)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gemInk = Color(hex: 0x14123A)
    static let goldGradient = LinearGradient(colors: [Color(hex: 0xFFD25A), Color(hex: 0xFF9F1C)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let levelBarGradient = LinearGradient(colors: [Color(hex: 0xFFD25A), Color(hex: 0xFF8FBE)], startPoint: .leading, endPoint: .trailing)
}

/// The gem artwork with its colored glow.
struct GemImage: View {
    let kind: GemKind
    var size: CGFloat = 40
    var glow = true

    var body: some View {
        Image(kind.imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: glow ? kind.glow.opacity(0.45) : .clear, radius: size * 0.14, y: size * 0.06)
            .accessibilityLabel(kind.shelfName)
    }
}

/// Four-point sparkle.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let i = r * 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + i, y: c.y - i))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x + i, y: c.y + i))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - i, y: c.y + i))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.addLine(to: CGPoint(x: c.x - i, y: c.y - i))
        p.closeSubpath()
        return p
    }
}

/// "💎 5/16 · 9 pts" on the live map.
struct GemCounterPill: View {
    let collected: Int
    let total: Int
    let points: Int
    var nearestDistance: Double? = nil
    var unit: DistanceUnit = .kilometers

    var body: some View {
        HStack(spacing: 6) {
            GemImage(kind: .common, size: 22, glow: false)
            Text("\(collected)/\(total)")
                .font(.number(16, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(collected)))
            Text("·").foregroundStyle(.white.opacity(0.4)).font(.system(size: 16, weight: .bold))
            Text("\(points) pts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFD25A))
                .contentTransition(.numericText(value: Double(points)))
            if let nearestDistance, nearestDistance < 200 {
                // Hint when a gem is close, so you know where to look.
                HStack(spacing: 3) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                    Text(Format.shortDistance(nearestDistance, unit: unit))
                        .font(.number(13, weight: .bold))
                }
                .foregroundStyle(Theme.gemInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.mint, in: Capsule())
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(Theme.gemInk.opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .animation(.snappy, value: collected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collected) of \(total) gems, \(points) points")
    }
}

/// Gem pops above the map with sparkles, then flies to the counter in the top-right.
struct GemCollectBurst: View {
    let event: GemCollectEvent

    @State private var stage = 0 // 0 hidden, 1 popped, 2 flown away
    @State private var spin = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(event.kind.tagTitle)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                Text("+\(event.points)")
                    .font(.hero(15))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [event.kind.glow, Color(hex: 0x8B5CF6)], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [event.kind.glow.opacity(0.55), event.kind.glow.opacity(0)], center: .center, startRadius: 4, endRadius: 80))
                    .frame(width: 160, height: 160)
                ForEach(0..<6, id: \.self) { index in
                    SparkleShape()
                        .fill(index.isMultiple(of: 2) ? Color.white : Color(hex: 0xFFD25A))
                        .frame(width: CGFloat(12 + index * 2), height: CGFloat(12 + index * 2))
                        .offset(x: 62 * cos(Double(index) * .pi / 3), y: 62 * sin(Double(index) * .pi / 3))
                        .rotationEffect(.degrees(spin ? 40 : 0))
                        .scaleEffect(spin ? 1 : 0.4)
                }
                GemImage(kind: event.kind, size: 96)
                    .rotationEffect(.degrees(stage == 1 ? -8 : 10))
            }
        }
        .scaleEffect(stage == 0 ? 0.2 : (stage == 1 ? 1 : 0.2))
        .offset(stage == 2 ? CGSize(width: 140, height: -230) : .zero)
        .opacity(stage == 2 ? 0 : 1)
        .allowsHitTesting(false)
        .task(id: event.id) {
            stage = 0
            spin = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { stage = 1 }
            withAnimation(.easeOut(duration: 0.9)) { spin = true }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeIn(duration: 0.45)) { stage = 2 }
        }
        .accessibilityHidden(true)
    }
}

/// Level badge, title and progress bar (white text, for dark gem backgrounds).
struct LevelProgressView: View {
    let points: Int

    var body: some View {
        let level = GemLevel.forPoints(points)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(level.number)")
                    .font(.hero(20))
                    .foregroundStyle(Color(hex: 0x3A2600))
                    .frame(width: 40, height: 40)
                    .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Level \(level.number) · \(level.title)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle(level))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(Theme.levelBarGradient)
                        .frame(width: max(10, proxy.size.width * level.progress(points: points)))
                }
            }
            .frame(height: 10)
        }
    }

    private func subtitle(_ level: GemLevel) -> String {
        guard let next = level.nextThreshold else { return "\(Format.steps(points)) pts" }
        let toGo = next - points
        if let nextTitle = level.nextTitle {
            return "\(Format.steps(points)) / \(Format.steps(next)) pts · \(Format.steps(toGo)) to \(nextTitle)"
        }
        return "\(Format.steps(points)) / \(Format.steps(next)) pts"
    }
}

/// Home card: level + recent gems, opens the collection.
struct GemLevelCard: View {
    let points: Int
    let recentKinds: [GemKind]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LevelProgressView(points: points)
            HStack {
                HStack(spacing: -6) {
                    ForEach(Array(recentKinds.prefix(5).enumerated()), id: \.offset) { _, kind in
                        GemImage(kind: kind, size: 30)
                    }
                    if recentKinds.isEmpty {
                        Text("Walk a route to find your first gems")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Collection")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFD25A))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Theme.gemBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Summary card: what you collected on this workout.
struct GemHaulCard: View {
    let collected: (GemKind) -> Int
    let available: (GemKind) -> Int
    let points: Int
    let bonusSteps: Int
    let bonusDetours: Int
    let lifetimePoints: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    GemImage(kind: .rare, size: 24, glow: false)
                    Text("Gem haul").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                Text("+\(points) pts")
                    .font(.hero(22))
                    .foregroundStyle(Color(hex: 0xFFD25A))
            }
            HStack {
                ForEach(GemKind.haulOrder) { kind in
                    VStack(spacing: 4) {
                        GemImage(kind: kind, size: 40)
                            .opacity(available(kind) == 0 ? 0.3 : 1)
                        Text(available(kind) == 0 ? "–" : "\(collected(kind))/\(available(kind))")
                            .font(.number(16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(kind == .common ? "Common" : kind == .rare ? "Rare" : kind == .legendary ? "Legendary" : "Bonus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if bonusDetours > 0 {
                Text("\(bonusDetours) bonus \(bonusDetours == 1 ? "detour" : "detours") · +\(Format.steps(bonusSteps)) extra steps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7AF2B4))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1FB863).opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            LevelProgressView(points: lifetimePoints)
        }
        .padding(20)
        .background(Theme.gemBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
