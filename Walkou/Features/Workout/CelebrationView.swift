import SwiftUI

/// "You rock!" moment when the step goal is reached mid-workout.
struct CelebrationView: View {
    let goalSteps: Int
    let stage: MascotStage
    let liquid: Color
    var onKeepGoing: () -> Void
    var onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.indigo, Color(hex: 0x8B5CF6), Theme.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer()
                HStack(alignment: .bottom, spacing: 18) {
                    SweatJarView(fill: 1, liquid: liquid, sealed: true, label: "GOAL!", onDark: true)
                        .frame(height: 104)
                        .rotationEffect(.degrees(appeared ? -6 : -40))
                    MascotView(pose: .cheer, stage: stage, sweat: 1)
                        .frame(width: 130, height: 156)
                }
                .scaleEffect(appeared ? 1 : 0.3)

                VStack(spacing: 10) {
                    Text("YOU ROCK!")
                        .font(.hero(64))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(Format.steps(goalSteps)) steps done")
                        .font(.system(size: 22, weight: .bold))
                    Text("Jar sealed! It crystallized into a Sweat Crystal · +\(GemKind.crystal.points) pts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFE59A))
                        .multilineTextAlignment(.center)
                    Text("Go the extra mile. You can do it! 💪")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Spacer()

                VStack(spacing: 12) {
                    Button("KEEP GOING", action: onKeepGoing)
                        .buttonStyle(PrimaryButtonStyle(background: .white, foreground: Theme.indigo))
                    Button("Finish workout", action: onFinish)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 44)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

/// Lightweight falling confetti drawn with Canvas.
struct ConfettiView: View {
    var count = 90
    let colors: [Color] = [.white, Color(hex: 0xFFD25A), Theme.mint, Color(hex: 0xFF6FA8), Theme.green]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSince(start)
                for i in 0..<count {
                    let speed = 70 + random(i, 2) * 150
                    let travel = size.height + 60
                    let y = (random(i, 3) * travel + t * speed).truncatingRemainder(dividingBy: travel) - 30
                    let x = random(i, 1) * size.width + sin(t * (1 + random(i, 5)) + Double(i)) * 20
                    let spin = t * 240 * (random(i, 4) - 0.5)

                    var piece = canvas
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(spin))
                    let rect = CGRect(x: -4, y: -7, width: 8, height: 14)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[i % colors.count]))
                }
            }
        }
    }

    /// Stable pseudo-random value in 0..<1 for a particle and channel.
    private func random(_ index: Int, _ channel: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(channel) * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }
}
