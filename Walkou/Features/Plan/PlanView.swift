import SwiftUI

/// Pick walk/run, a step goal and how to reach it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.goalSteps) private var goalSteps = 6000
    @AppStorage(SettingsKey.activity) private var activity: ActivityType = .walk
    @AppStorage(SettingsKey.mode) private var mode: WorkoutMode = .loop
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers

    @State private var showRoutes = false

    private let presets = [3000, 5000, 6000, 8000, 10000, 15000]
    private let stepIncrement = 500
    private let goalRange = 1000...40000

    private var plan: WorkoutPlan {
        WorkoutPlan(activity: activity, goalSteps: goalSteps, mode: mode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Set your goal")
                        .font(.system(size: 34, weight: .bold))
                        .padding(.top, 8)

                    PillPicker(options: ActivityType.allCases, selection: $activity, label: { $0.title }, symbol: { $0.symbol })

                    goalCard
                    modeSection

                    if model.location.isDenied && mode.needsRoute {
                        locationWarning
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { startButton }
            .navigationDestination(isPresented: $showRoutes) {
                RouteSuggestionsView(plan: plan)
            }
            .onAppear { model.location.startPreviewUpdates() }
        }
    }

    // MARK: - Goal

    private var goalCard: some View {
        VStack(spacing: 18) {
            HStack {
                roundButton("minus") { adjustGoal(by: -stepIncrement) }
                Spacer()
                VStack(spacing: 0) {
                    Text(Format.steps(goalSteps))
                        .font(.hero(60))
                        .contentTransition(.numericText(value: Double(goalSteps)))
                        .animation(.snappy, value: goalSteps)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("steps")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                roundButton("plus") { adjustGoal(by: stepIncrement) }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            Haptics.tap()
                            goalSteps = preset
                        } label: {
                            Text(preset >= 1000 ? "\(preset / 1000)K" : "\(preset)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(goalSteps == preset ? Color.white : Color.primary)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(goalSteps == preset ? Theme.indigo : Theme.cardSecondary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.snappy(duration: 0.2), value: goalSteps)
            }

            HStack(spacing: 0) {
                estimate(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Distance",
                         value: Format.distance(plan.targetDistance, unit: unit))
                Rectangle().fill(Theme.separator).frame(width: 1, height: 36)
                estimate(symbol: "clock", title: "About", value: Format.durationEstimate(plan.estimatedDuration))
                Rectangle().fill(Theme.separator).frame(width: 1, height: 36)
                estimate(symbol: "flame", title: "Calories",
                         value: "\(Format.calories(plan.targetDistance / 1000 * activity.kilocaloriesPerKilometer))")
            }
            .padding(.vertical, 12)
            .background(Theme.cardSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Based on an average \(activity.title.lowercased()) stride of \(String(format: "%.2f", activity.strideLength)) m.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func estimate(symbol: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .labelStyle(.titleOnly)
            Text(value)
                .font(.number(16, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.indigo)
                .frame(width: 52, height: 52)
                .background(Theme.indigo.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private func adjustGoal(by delta: Int) {
        let rounded = (goalSteps / stepIncrement) * stepIncrement
        let next = (delta > 0 || rounded == goalSteps) ? rounded + delta : rounded
        goalSteps = min(goalRange.upperBound, max(goalRange.lowerBound, next))
        Haptics.tap()
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How do you want to get there?")
                .font(.system(size: 19, weight: .semibold))
            HStack(spacing: 10) {
                ForEach(WorkoutMode.allCases) { option in
                    modeCard(option)
                }
            }
            .animation(.snappy(duration: 0.2), value: mode)
        }
    }

    private func modeCard(_ option: WorkoutMode) -> some View {
        let isSelected = option == mode
        return Button {
            Haptics.tap()
            mode = option
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: option == .free ? activity.symbol : option.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Theme.indigo)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Theme.indigo : Theme.indigo.opacity(0.12), in: Circle())
                Text(option == .free ? "Free \(activity.title.lowercased())" : option.title)
                    .font(.system(size: 16, weight: .bold))
                Text(option.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Theme.indigo : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var locationWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Location is off")
                    .font(.system(size: 16, weight: .semibold))
                Text("Turn on location for Walkou in Settings to get routes.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
            }
        }
        .card()
    }

    // MARK: - Start

    private var startButton: some View {
        Button {
            Haptics.tap()
            if mode.needsRoute {
                showRoutes = true
            } else {
                model.startWorkout(plan: plan, route: nil)
            }
        } label: {
            Text(mode.needsRoute ? "FIND ROUTES" : "START FREE \(activity.title.uppercased())")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(mode.needsRoute && model.location.isDenied)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .background(Theme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
    }
}
