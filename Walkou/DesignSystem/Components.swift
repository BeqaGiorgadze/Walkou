import SwiftUI

// MARK: - Cards

struct CardModifier: ViewModifier {
    var background: Color = Theme.card
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card(_ background: Color = Theme.card, padding: CGFloat = 20) -> some View {
        modifier(CardModifier(background: background, padding: padding))
    }
}

/// Card header: icon, title and an optional trailing arrow.
struct CardHeader: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.indigo
    var showsArrow = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            if showsArrow {
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

// MARK: - Stats

/// "Time ........ 44:58" row from the moodboard stat lists.
struct StatRow: View {
    let symbol: String
    let title: String
    let value: String
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                Spacer()
                Text(value)
                    .font(.number(17, weight: .medium))
            }
            .padding(.vertical, 14)
            if showsDivider {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }
}

/// Small label + value tile used on the live workout panel.
struct MetricTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.number(22, weight: .bold))
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Full-width capsule button ("GET STARTED").
struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = Theme.indigo
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .tracking(1)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// White capsule with a dark round arrow on the right ("Join Challenge →").
struct ArrowCapsuleButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: 0x1C1C28), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.trailing, 7)
            .frame(height: 52)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Round floating map control.
struct MapControlButton: View {
    let symbol: String
    var tint: Color = .white
    var background: Color = Theme.navSurfaceRaised
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(background.opacity(0.92), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = Theme.indigo
    var track: Color = Theme.separator

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
        }
    }
}

struct ProgressBar: View {
    let progress: Double
    var tint: Color = .white
    var track: Color = .white.opacity(0.3)
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.6), value: progress)
    }
}

/// Round gradient medal like the moodboard badges.
struct BadgeIcon: View {
    let symbol: String
    var colors: [Color] = [Theme.indigo, Color(hex: 0x8B5CF6)]
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: size * 0.06)
                .padding(size * 0.08)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Selection

/// Segmented pill control.
struct PillPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var symbol: ((Option) -> String)? = nil

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy) { selection = option }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        if let symbol { Image(systemName: symbol(option)) }
                        Text(label(option))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if isSelected {
                            Capsule().fill(Theme.indigo)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.cardSecondary, in: Capsule())
    }
}
