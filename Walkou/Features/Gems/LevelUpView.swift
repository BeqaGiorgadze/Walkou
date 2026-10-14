import SwiftUI

/// Shown after a workout that pushed lifetime gem points into a new level.
struct LevelUpView: View {
    let level: GemLevel
    let points: Int
    var onDone: () -> Void
    var onCollection: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2D1B5E), Color(hex: 0x1C1850), Color(hex: 0x0E0C26)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFC53D).opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 210))
                .frame(width: 420, height: 420)
                .offset(y: -170)
                .scaleEffect(appeared ? 1 : 0.6)
            ConfettiView(count: 50)
                .ignoresSafeArea()
                .opacity(0.6)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                gemCluster
                    .frame(height: 280)
                    .padding(.top, 40)

                VStack(spacing: 12) {
                    Text("LEVEL UP!")
                        .font(.hero(60))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Level \(level.number) · \(level.title)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3A2600))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.goldGradient, in: Capsule())
                    Text("\(Format.steps(points)) points of gems collected. Your legs are officially legendary.")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    HStack(spacing: 12) {
                        Image(systemName: "rosette")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(hex: 0x3A2600))
                            .frame(width: 46, height: 46)
                            .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEW TITLE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0xFFD25A))
                            Text(level.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)

                Spacer()

                VStack(spacing: 12) {
                    Button("AWESOME", action: onDone)
                        .buttonStyle(PrimaryButtonStyle(background: .white, foreground: Theme.indigo))
                    Button("See my collection", action: onCollection)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            SoundEffects.play(.levelUp)
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { appeared = true }
        }
    }

    private var gemCluster: some View {
        ZStack {
            ForEach(Array(orbit.enumerated()), id: \.offset) { index, item in
                GemImage(kind: item.kind, size: item.size)
                    .rotationEffect(.degrees(item.rotation))
                    .offset(appeared ? item.offset : .zero)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(Double(index) * 0.05), value: appeared)
            }
            GemImage(kind: .legendary, size: 150)
                .scaleEffect(appeared ? 1 : 0.2)
                .rotationEffect(.degrees(appeared ? 0 : -25))
        }
    }

    private var orbit: [(kind: GemKind, size: CGFloat, offset: CGSize, rotation: Double)] {
        [
            (.common, 52, CGSize(width: -112, height: -40), -14),
            (.rare, 56, CGSize(width: 112, height: -60), 12),
            (.bonus, 50, CGSize(width: -96, height: 82), 10),
            (.heart, 50, CGSize(width: 100, height: 78), -8),
            (.amber, 44, CGSize(width: 0, height: -120), 0),
        ]
    }
}
