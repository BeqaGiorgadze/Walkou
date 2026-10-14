import SwiftUI

/// Hosts a workout from countdown to summary inside the full-screen cover.
struct WorkoutFlowView: View {
    let session: WorkoutSession

    var body: some View {
        Group {
            if session.isFinished {
                WorkoutSummaryView(session: session)
                    .transition(.move(edge: .bottom))
            } else {
                ActiveWorkoutView(session: session)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isFinished)
        .onAppear { session.start() }
    }
}
