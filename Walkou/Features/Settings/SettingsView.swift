import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers
    @AppStorage(SettingsKey.voiceGuidance) private var voiceGuidance = true
    @AppStorage(SettingsKey.offRouteAlerts) private var offRouteAlerts = true
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = false

    @State private var healthError: String?
    @State private var isRequestingHealth = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(isOn: $voiceGuidance) {
                        Label("Voice guidance", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: $offRouteAlerts) {
                        Label("Off-route alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                } header: {
                    Text("During a workout")
                } footer: {
                    Text("Turn-by-turn directions, halfway reminders and your goal celebration are spoken, even with the screen locked.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { saveToHealth },
                        set: { newValue in
                            if newValue { Task { await enableHealth() } } else { saveToHealth = false }
                        }
                    )) {
                        HStack {
                            Label("Save to Apple Health", systemImage: "heart.fill")
                            if isRequestingHealth {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    if let healthError {
                        Text(healthError)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Saves each workout with its distance, steps, calories and route. Needs the HealthKit capability (paid Apple Developer account). See the README.")
                }

                Section {
                    LabeledContent("Walking stride", value: String(format: "%.2f m", ActivityType.walk.strideLength))
                    LabeledContent("Running stride", value: String(format: "%.2f m", ActivityType.run.strideLength))
                } header: {
                    Text("Step estimates")
                } footer: {
                    Text("Route lengths are planned from these average strides. Your real steps are counted by your iPhone's motion sensors.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func enableHealth() async {
        isRequestingHealth = true
        healthError = nil
        defer { isRequestingHealth = false }
        do {
            try await HealthKitService.shared.requestAuthorization()
            if HealthKitService.shared.canSaveWorkouts {
                saveToHealth = true
            } else {
                healthError = "Walkou isn't allowed to save workouts. You can change this in the Health app under Sharing → Apps."
            }
        } catch {
            saveToHealth = false
            healthError = "Apple Health isn't available in this build. \(error.localizedDescription)"
        }
    }
}
