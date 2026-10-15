import SwiftUI
import SwiftData

@main
struct WalkouApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.indigo)
                .task { await AppWarmUp.run() }
        }
        .modelContainer(for: WorkoutRecord.self)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        @Bindable var model = model
        Group {
            if hasOnboarded {
                MainTabView()
            } else {
                OnboardingView {
                    withAnimation(.easeInOut) { hasOnboarded = true }
                }
            }
        }
        .fullScreenCover(item: $model.activeSession) { session in
            WorkoutFlowView(session: session)
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            PlanView()
                .tabItem { Label("Start", systemImage: "figure.walk.motion") }
                .tag(AppTab.start)
            HistoryView()
                .tabItem { Label("Activity", systemImage: "chart.bar.fill") }
                .tag(AppTab.activity)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.settings)
        }
    }
}
