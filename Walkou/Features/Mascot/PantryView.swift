import SwiftUI
import SwiftData

/// "Kou's Pantry": Kou's stage, the looks still to unlock, and a shelf of every jar you've filled.
struct PantryView: View {
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]
    @Environment(\.colorScheme) private var colorScheme

    private var jars: Int { SweatJar.lifetimeSealed(workouts) }

    var body: some View {
        let stage = MascotStage.forJars(jars)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kou's Pantry")
                    .font(.system(size: 34, weight: .bold))

                header(stage)

                Text("Kou's looks").font(.system(size: 22, weight: .bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MascotStage.all) { item in
                            stageTile(item, unlocked: item.number <= stage.number)
                        }
                    }
                }

                Text("Your jars").font(.system(size: 22, weight: .bold))
                if workouts.isEmpty {
                    Text("Every walk fills a jar. Reach your goal to seal it, and Kou gets a little fitter.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .card()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                        ForEach(workouts) { workout in
                            jarTile(workout)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ stage: MascotStage) -> some View {
        HStack(spacing: 18) {
            MascotView(pose: .idle, stage: stage)
                .frame(width: 110, height: 132)
            VStack(alignment: .leading, spacing: 8) {
                Text(stage.title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.mint)
                Text(jars == 1 ? "1 jar" : "\(Format.steps(jars)) jars")
                    .font(.hero(34))
                if let next = stage.next {
                    ProgressBar(progress: stage.progress(jars: jars), tint: Theme.mint, track: .white.opacity(0.15), height: 8)
                    Text("\(next.jarsNeeded - jars) more for \(next.unlock.lowercased())")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Every look unlocked.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.navSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func stageTile(_ stage: MascotStage, unlocked: Bool) -> some View {
        VStack(spacing: 6) {
            MascotView(pose: .idle, stage: stage, animated: false)
                .frame(width: 60, height: 72)
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.3)
            Text(stage.title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Text(unlocked ? stage.unlock : "🔒 \(stage.jarsNeeded) jars")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: 104)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func jarTile(_ workout: WorkoutRecord) -> some View {
        let sealed = SweatJar.sealed(steps: workout.steps, goal: workout.goalSteps)
        let fill = SweatJar.fill(steps: workout.steps, goal: workout.goalSteps)
        return VStack(spacing: 4) {
            SweatJarView(
                fill: min(fill, 1),
                liquid: SweatJar.liquid(for: workout.activity),
                sealed: sealed > 0,
                label: sealed > 0 ? SweatJar.label(for: workout.startDate) : nil,
                onDark: colorScheme == .dark
            )
            .frame(height: 74)
            .overlay(alignment: .topTrailing) {
                if sealed > 1 {
                    Text("×\(sealed)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.indigo, in: Capsule())
                }
            }
            Text(sealed > 0 ? "Sealed" : "\(Int(fill * 100))%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(sealed > 0 ? Theme.indigo : Theme.textSecondary)
            Text(workout.startDate.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
