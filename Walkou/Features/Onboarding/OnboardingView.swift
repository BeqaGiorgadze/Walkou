import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            if page == 0 {
                welcome.transition(.opacity)
            } else {
                permissions.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: page)
    }

    // MARK: - Welcome

    private var welcome: some View {
        ZStack(alignment: .bottom) {
            Theme.sunsetGradient.ignoresSafeArea()

            // Sun and runner silhouette
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFE3B0), Color(hex: 0xFFB36B).opacity(0)], center: .center, startRadius: 10, endRadius: 180))
                        .frame(width: 360, height: 360)
                        .position(x: proxy.size.width * 0.7, y: proxy.size.height * 0.28)
                    Image(systemName: "figure.run")
                        .font(.system(size: 260, weight: .black))
                        .foregroundStyle(.black.opacity(0.55))
                        .position(x: proxy.size.width * 0.45, y: proxy.size.height * 0.36)
                    Image(systemName: "figure.walk")
                        .font(.system(size: 90, weight: .black))
                        .foregroundStyle(.black.opacity(0.4))
                        .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.46)
                }
            }
            .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("LET'S WALK\nTOGETHER")
                    .font(.hero(52))
                    .foregroundStyle(.white)
                    .lineSpacing(-6)
                    .minimumScaleFactor(0.7)
                Text("Pick a step goal. Get routes that match it. Follow the path, step by step.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Button("GET STARTED") { page = 1 }
                    .buttonStyle(PrimaryButtonStyle(background: Color(hex: 0x6A3FE0)))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 20)
            BadgeIcon(symbol: "shoeprints.fill", size: 84)
            VStack(alignment: .leading, spacing: 10) {
                Text("Before you go")
                    .font(.system(size: 34, weight: .bold))
                Text("Walkou needs a few permissions to plan routes and count your steps. Everything stays on your iPhone.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 0) {
                PermissionRow(symbol: "location.fill", tint: Theme.indigo, title: "Location",
                              detail: "Find routes near you and guide you along them, even with the screen locked.")
                PermissionRow(symbol: "figure.walk", tint: Theme.green, title: "Motion & Fitness",
                              detail: "Count your steps with your iPhone's motion sensors.")
                PermissionRow(symbol: "bell.badge.fill", tint: Theme.orange, title: "Notifications",
                              detail: "Halfway reminders and your goal celebration while the phone is in your pocket.",
                              showsDivider: false)
            }
            .card()

            Spacer()

            Button {
                Task { await requestPermissions() }
            } label: {
                if isRequesting {
                    ProgressView().tint(.white)
                } else {
                    Text("ALLOW & CONTINUE")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isRequesting)

            Button("Not now", action: onFinish)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
    }

    private func requestPermissions() async {
        isRequesting = true
        model.location.requestPermission()
        await NotificationService.requestPermission()
        // Querying the pedometer shows the Motion & Fitness prompt.
        _ = await PedometerService().steps(from: Calendar.current.startOfDay(for: Date()), to: Date())
        isRequesting = false
        onFinish()
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12)
            if showsDivider {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }
}
