import SwiftUI

/// What Kou is doing.
enum MascotPose: Equatable {
    case idle
    /// Crouched, waiting for the countdown.
    case ready
    case walk
    case run
    /// Jumping with arms up (goal reached, jar sealed).
    case cheer
    /// Napping (paused workout, rest days).
    case rest
}

/// Draws Kou with plain shapes in a 100 × 120 design space, facing right.
/// Everything is a function of time, so a `TimelineView` + `Canvas` animates it cheaply.
/// (A Rive version can replace this later; see docs/MASCOT_RIVE.md.)
enum MascotRenderer {
    static let designSize = CGSize(width: 100, height: 120)

    private static let body = Color(hex: 0xFFC23D)
    private static let bodyShade = Color(hex: 0xF2A516)
    private static let belly = Color(hex: 0xFFE08A)
    private static let limb = Color(hex: 0xE89B12)
    private static let limbBack = Color(hex: 0xC97F05)
    private static let ink = Color(hex: 0x2A2357)
    private static let cheek = Color(hex: 0xFF7A9A)
    private static let mint = Color(hex: 0x6FE3C8)
    private static let shoe = Color(hex: 0x5B5CE2)
    private static let shoeBack = Color(hex: 0x4645B8)
    private static let tongue = Color(hex: 0xFF6F8E)
    static let sweat = Color(hex: 0x7FD3FF)

    /// Back of Kou's head in design space: where flying sweat drops start.
    static let dropOrigin = CGPoint(x: 26, y: 44)

    /// Largest rect with Kou's proportions that fits in `size`, centered at the bottom.
    static func fittedRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / designSize.width, size.height / designSize.height)
        let width = designSize.width * scale
        let height = designSize.height * scale
        return CGRect(x: (size.width - width) / 2, y: size.height - height, width: width, height: height)
    }

    // swiftlint:disable:next function_body_length
    static func draw(in context: GraphicsContext, rect: CGRect, pose: MascotPose, stage: MascotStage, sweat: Double, time t: Double) {
        var ctx = context
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / designSize.width, y: rect.height / designSize.height)

        let chub = stage.chubbiness
        let cycles: Double = pose == .walk ? 0.95 : (pose == .run ? 1.45 : 0)
        let ph = 2 * .pi * cycles * t
        let swing: Double = pose == .walk ? 26 : (pose == .run ? 42 : 0)

        let bob: Double
        switch pose {
        case .walk: bob = -abs(sin(ph)) * 3
        case .run: bob = -abs(sin(ph)) * 6
        case .cheer: bob = -abs(sin(2 * .pi * 1.6 * t)) * 9
        case .ready: bob = 1.5
        case .idle, .rest: bob = sin(2 * .pi * 0.35 * t) * 1.2 // breathing
        }
        let lean: Double = pose == .run ? 7 : (pose == .walk ? 3 : 0)
        let cx: CGFloat = 50
        let cy = CGFloat(64 + bob)
        let rx = 29 * chub
        let ry: CGFloat = 33

        // Ground shadow
        ctx.fill(Path(ellipseIn: CGRect(x: 50 - 24 * chub, y: 113.5, width: 48 * chub, height: 7)), with: .color(.black.opacity(0.12)))

        var g = ctx
        g.translateBy(x: 50, y: 116)
        g.rotate(by: .degrees(lean))
        g.translateBy(x: -50, y: -116)

        // Legs and shoes (behind the body); the far leg is darker.
        for side in 0..<2 {
            let near = side == 1
            let hip = CGPoint(x: 50 + (near ? 9 : -9), y: cy + 22)
            var angle = (near ? 1 : -1) * sin(ph) * swing
            if pose == .rest || swing == 0 { angle = 0 }
            let footStart = CGPoint(x: hip.x, y: hip.y + 22 + (pose == .ready ? -3 : 0))
            let foot = rotate(footStart, around: hip, degrees: angle)
            g.stroke(line(hip, foot), with: .color(near ? limb : limbBack), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            var shoeContext = g
            shoeContext.translateBy(x: foot.x, y: foot.y)
            shoeContext.rotate(by: .degrees(angle * 0.4))
            shoeContext.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 15, height: 9), cornerRadius: 4.5), with: .color(near ? shoe : shoeBack))
            shoeContext.fill(Path(roundedRect: CGRect(x: -6, y: 3, width: 15, height: 2.4), cornerRadius: 1.2), with: .color(.white))
            if stage.hasStripes {
                var stripe = shoeContext
                stripe.rotate(by: .degrees(20))
                stripe.fill(Path(roundedRect: CGRect(x: -1, y: -3, width: 3, height: 6), cornerRadius: 1.5), with: .color(mint))
            }
        }

        // Arm angles
        let backArm: Double
        let frontArm: Double
        switch pose {
        case .cheer:
            let wave = sin(2 * .pi * 1.6 * t) * 12
            backArm = 150 + wave
            frontArm = -150 - wave
        case .rest:
            backArm = 8
            frontArm = -8
        case .ready:
            backArm = 35
            frontArm = -35
        case .walk, .run:
            backArm = -sin(ph) * swing * 1.1 - (pose == .run ? 20 : 0)
            frontArm = sin(ph) * swing * 1.1 - (pose == .run ? 20 : 0)
        case .idle:
            backArm = sin(2 * .pi * 0.35 * t) * 3
            frontArm = -backArm
        }

        drawArm(in: g, shoulder: CGPoint(x: cx - rx + 4, y: cy + 2), degrees: backArm)

        // Body
        let bodyPath = Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        g.fill(bodyPath, with: .color(body))
        var inner = g
        inner.clip(to: bodyPath)
        inner.fill(Path(ellipseIn: CGRect(x: cx - 6 - (rx + 6), y: cy + 26 - 18, width: (rx + 6) * 2, height: 36)), with: .color(bodyShade.opacity(0.55)))
        inner.fill(Path(ellipseIn: CGRect(x: cx + 3 - 17 * chub, y: cy + 12 - 15, width: 34 * chub, height: 30)), with: .color(belly))
        var shine = inner
        shine.translateBy(x: cx - 12, y: cy - 20)
        shine.rotate(by: .degrees(-25))
        shine.fill(Path(ellipseIn: CGRect(x: -9, y: -5, width: 18, height: 10)), with: .color(.white.opacity(0.45)))
        if stage.hasHeadband {
            inner.fill(Path(CGRect(x: 0, y: cy - 24, width: 100, height: 7)), with: .color(mint))
            inner.fill(Path(CGRect(x: 0, y: cy - 24, width: 100, height: 2)), with: .color(.white.opacity(0.4)))
        }
        if stage.hasBib {
            inner.fill(Path(roundedRect: CGRect(x: cx - 4, y: cy + 6, width: 16, height: 12), cornerRadius: 2), with: .color(.white))
            inner.fill(Path(roundedRect: CGRect(x: cx - 1, y: cy + 10, width: 10, height: 2), cornerRadius: 1), with: .color(ink.opacity(0.6)))
            inner.fill(Path(roundedRect: CGRect(x: cx - 1, y: cy + 13.5, width: 7, height: 2), cornerRadius: 1), with: .color(ink.opacity(0.6)))
        }

        // Headband knot tails flapping behind
        if stage.hasHeadband {
            let flap = sin(2 * .pi * (swing > 0 ? 2.2 : 0.5) * t) * (swing > 0 ? 14 : 4)
            let knot = CGPoint(x: cx - rx + 3, y: cy - 21)
            for (index, base) in [200.0, 225.0].enumerated() {
                let a = (base + flap * (index == 0 ? 1 : -0.6)) * .pi / 180
                let end = CGPoint(x: knot.x + cos(a) * 13, y: knot.y + sin(a) * 13)
                g.stroke(line(knot, end), with: .color(mint), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
        }

        // Face, shifted right because Kou faces right
        let eyeY = cy - 8
        let eyes: [CGFloat] = [cx + 2, cx + 16]
        let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12
        switch pose {
        case .rest:
            for x in eyes {
                g.stroke(quad(from: CGPoint(x: x - 5, y: eyeY), control: CGPoint(x: x, y: eyeY + 4), to: CGPoint(x: x + 5, y: eyeY)),
                         with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        case .cheer:
            for x in eyes {
                g.stroke(quad(from: CGPoint(x: x - 5, y: eyeY + 2), control: CGPoint(x: x, y: eyeY - 5), to: CGPoint(x: x + 5, y: eyeY + 2)),
                         with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        default:
            for x in eyes {
                let height: CGFloat = blink ? 15 * 0.12 : 15
                g.fill(Path(ellipseIn: CGRect(x: x - 6, y: eyeY - height / 2, width: 12, height: height)), with: .color(.white))
                if !blink {
                    g.fill(circle(CGPoint(x: x + 1.6, y: eyeY + 0.8), 3.6), with: .color(ink))
                    g.fill(circle(CGPoint(x: x + 2.8, y: eyeY - 0.6), 1.2), with: .color(.white))
                }
            }
        }
        for x in [eyes[0] - 7, eyes[1] + 6] {
            g.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: eyeY + 11 - 2.8, width: 9, height: 5.6)), with: .color(cheek.opacity(0.55)))
        }

        // Mouth
        let mouth = CGPoint(x: cx + 9, y: cy + 5)
        switch pose {
        case .run:
            let h = 4.5 + sin(ph * 2) * 1.2
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - 4.2, y: mouth.y - h, width: 8.4, height: h * 2)), with: .color(ink))
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - 2.6, y: mouth.y + h * 0.45 - h * 0.4, width: 5.2, height: h * 0.8)), with: .color(tongue))
        case .cheer:
            var openMouth = Path()
            openMouth.move(to: CGPoint(x: mouth.x - 7, y: mouth.y - 2))
            openMouth.addLine(to: CGPoint(x: mouth.x + 7, y: mouth.y - 2))
            openMouth.addQuadCurve(to: CGPoint(x: mouth.x, y: mouth.y + 8), control: CGPoint(x: mouth.x + 7, y: mouth.y + 8))
            openMouth.addQuadCurve(to: CGPoint(x: mouth.x - 7, y: mouth.y - 2), control: CGPoint(x: mouth.x - 7, y: mouth.y + 8))
            openMouth.closeSubpath()
            g.fill(openMouth, with: .color(ink))
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - 3.5, y: mouth.y + 3, width: 7, height: 4)), with: .color(tongue))
        case .rest:
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - 2.2, y: mouth.y - 2.6, width: 4.4, height: 5.2)), with: .color(ink))
        default:
            g.stroke(quad(from: CGPoint(x: mouth.x - 5, y: mouth.y - 1), control: CGPoint(x: mouth.x, y: mouth.y + 4.5), to: CGPoint(x: mouth.x + 5, y: mouth.y - 1)),
                     with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }

        if stage.hasMedal {
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: cx - 6, y: cy + 1))
            ribbon.addLine(to: CGPoint(x: cx + 3, y: cy + 15))
            ribbon.addLine(to: CGPoint(x: cx + 12, y: cy + 1))
            g.stroke(ribbon, with: .color(shoe), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            let medal = circle(CGPoint(x: cx + 3, y: cy + 19), 6.5)
            g.fill(medal, with: .color(Color(hex: 0xFFD25A)))
            g.stroke(medal, with: .color(Color(hex: 0xE68A00)), lineWidth: 1.5)
            g.fill(SparkleShape().path(in: CGRect(x: cx - 0.5, y: cy + 15.5, width: 7, height: 7)), with: .color(Color(hex: 0xFFF1C2)))
        }

        drawArm(in: g, shoulder: CGPoint(x: cx + rx - 9, y: cy + 9), degrees: frontArm)

        // Sweat beads
        if pose != .rest {
            if sweat > 0.25 { g.fill(dropPath(center: CGPoint(x: cx + 22, y: cy - 24), size: 2.6), with: .color(Self.sweat)) }
            if sweat > 0.6 { g.fill(dropPath(center: CGPoint(x: cx - 24, y: cy - 12), size: 2.2), with: .color(Self.sweat)) }
        }

        // Zzz while napping
        if pose == .rest {
            let z = (t * 0.6).truncatingRemainder(dividingBy: 1)
            var zContext = ctx
            zContext.opacity = 1 - z
            zContext.draw(
                Text("z").font(.system(size: 10 + z * 4, weight: .bold)).foregroundColor(mint),
                at: CGPoint(x: 76 + z * 8, y: 36 - z * 12),
                anchor: .bottomLeading
            )
        }
    }

    /// A sweat drop with its tip at the top.
    static func dropPath(center c: CGPoint, size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 1.6 * s))
        p.addCurve(to: CGPoint(x: c.x + s, y: c.y), control1: CGPoint(x: c.x + 0.15 * s, y: c.y - 1.2 * s), control2: CGPoint(x: c.x + s, y: c.y - 0.55 * s))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + s), control1: CGPoint(x: c.x + s, y: c.y + 0.55 * s), control2: CGPoint(x: c.x + 0.55 * s, y: c.y + s))
        p.addCurve(to: CGPoint(x: c.x - s, y: c.y), control1: CGPoint(x: c.x - 0.55 * s, y: c.y + s), control2: CGPoint(x: c.x - s, y: c.y + 0.55 * s))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - 1.6 * s), control1: CGPoint(x: c.x - s, y: c.y - 0.55 * s), control2: CGPoint(x: c.x - 0.15 * s, y: c.y - 1.2 * s))
        p.closeSubpath()
        return p
    }

    // MARK: - Helpers

    private static func drawArm(in context: GraphicsContext, shoulder: CGPoint, degrees: Double) {
        let hand = rotate(CGPoint(x: shoulder.x, y: shoulder.y + 15), around: shoulder, degrees: degrees)
        context.stroke(line(shoulder, hand), with: .color(limb), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        let palm = circle(hand, 4.6)
        context.fill(palm, with: .color(body))
        context.stroke(palm, with: .color(limb), lineWidth: 1.5)
    }

    private static func rotate(_ p: CGPoint, around o: CGPoint, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = p.x - o.x
        let dy = p.y - o.y
        return CGPoint(x: o.x + dx * cos(a) - dy * sin(a), y: o.y + dx * sin(a) + dy * cos(a))
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    private static func quad(from a: CGPoint, control: CGPoint, to b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: control)
        return p
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// Draws a glass jar with sloshing liquid inside `rect`.
enum SweatJarRenderer {
    struct Style {
        /// Dark backgrounds get a white glass outline; light ones a dark one.
        var onDark = true
        var liquid: Color = Color(hex: 0x4FC3FF)
    }

    /// - Parameters:
    ///   - fill: 0...1.
    ///   - wave: wave height in points.
    ///   - slope: surface tilt (rise per point), for the tilt-to-slosh effect.
    ///   - lidDrop: how far above its place the lid is (for the sealing animation).
    static func draw(
        in context: GraphicsContext,
        rect: CGRect,
        fill: Double,
        style: Style,
        time t: Double,
        wave: Double = 1.2,
        slope: Double = 0,
        sealed: Bool = false,
        label: String? = nil,
        lidDrop: CGFloat = 0
    ) {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        let neckH = 0.13 * h, rimH = 0.07 * h
        let by = y + neckH, bh = h - neckH
        let r = 0.24 * w
        let nx = x + 0.16 * w, nw = 0.68 * w

        var jar = Path()
        jar.move(to: CGPoint(x: nx, y: y + rimH))
        jar.addLine(to: CGPoint(x: nx + nw, y: y + rimH))
        jar.addLine(to: CGPoint(x: nx + nw, y: by))
        jar.addLine(to: CGPoint(x: x + w - r, y: by))
        jar.addQuadCurve(to: CGPoint(x: x + w, y: by + r), control: CGPoint(x: x + w, y: by))
        jar.addLine(to: CGPoint(x: x + w, y: by + bh - r))
        jar.addQuadCurve(to: CGPoint(x: x + w - r, y: by + bh), control: CGPoint(x: x + w, y: by + bh))
        jar.addLine(to: CGPoint(x: x + r, y: by + bh))
        jar.addQuadCurve(to: CGPoint(x: x, y: by + bh - r), control: CGPoint(x: x, y: by + bh))
        jar.addLine(to: CGPoint(x: x, y: by + r))
        jar.addQuadCurve(to: CGPoint(x: x + r, y: by), control: CGPoint(x: x, y: by))
        jar.addLine(to: CGPoint(x: nx, y: by))
        jar.closeSubpath()

        let glass: Color = style.onDark ? .white : Color(hex: 0x2A2357)
        let strokeOpacity = style.onDark ? 0.8 : 0.3
        context.fill(jar, with: .color(glass.opacity(style.onDark ? 0.12 : 0.06)))

        // Liquid
        let innerTop = y + rimH + 2
        let innerBottom = y + h - 3
        let level = innerBottom - CGFloat(min(max(fill, 0), 1)) * (innerBottom - innerTop) * 0.96
        if fill > 0.005 {
            let midX = x + w / 2
            var surface = Path()
            let segments = 24
            for i in 0...segments {
                let px = x + w * CGFloat(i) / CGFloat(segments)
                let py = level + CGFloat(slope) * (px - midX) + CGFloat(wave * sin(Double(px) * 0.22 + t * 3.4))
                if i == 0 { surface.move(to: CGPoint(x: px, y: py)) } else { surface.addLine(to: CGPoint(x: px, y: py)) }
            }
            var liquid = surface
            liquid.addLine(to: CGPoint(x: x + w, y: y + h + 4))
            liquid.addLine(to: CGPoint(x: x, y: y + h + 4))
            liquid.closeSubpath()

            var inside = context
            inside.clip(to: jar)
            inside.fill(liquid, with: .color(style.liquid))
            inside.stroke(surface, with: .color(.white.opacity(0.45)), lineWidth: 2)
            inside.fill(Path(CGRect(x: x, y: level + 6, width: w, height: h)), with: .color(.black.opacity(0.08)))
        }

        context.stroke(jar, with: .color(glass.opacity(strokeOpacity)), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
        context.fill(Path(roundedRect: CGRect(x: x + 0.14 * w, y: by + 0.18 * bh, width: 0.07 * w, height: 0.42 * bh), cornerRadius: 0.035 * w),
                     with: .color(.white.opacity(0.45)))

        if let label {
            let lw = 0.66 * w, lh = 0.24 * h
            let labelRect = CGRect(x: x + (w - lw) / 2, y: by + bh * 0.42, width: lw, height: lh)
            context.fill(Path(roundedRect: labelRect, cornerRadius: 3), with: .color(Color(hex: 0xFFF6E0)))
            context.draw(
                Text(label).font(.system(size: lh * 0.42, weight: .heavy)).foregroundColor(Color(hex: 0x2A2357)),
                at: CGPoint(x: labelRect.midX, y: labelRect.midY)
            )
        }

        if sealed {
            let lidY = y - 2 - lidDrop
            context.fill(Path(roundedRect: CGRect(x: x + 0.1 * w, y: lidY, width: 0.8 * w, height: rimH + 4), cornerRadius: 3), with: .color(Theme.indigo))
            context.fill(Path(roundedRect: CGRect(x: x + 0.1 * w, y: lidY + rimH + 1, width: 0.8 * w, height: 3), cornerRadius: 1.5), with: .color(Theme.indigoDeep))
        } else {
            context.stroke(Path(roundedRect: CGRect(x: nx - 2, y: y, width: nw + 4, height: rimH), cornerRadius: 2),
                           with: .color(glass.opacity(strokeOpacity)), lineWidth: 2.2)
        }
    }
}
