import SwiftUI

/// Sweat jars: every workout fills a jar toward its step goal. Reaching the goal seals the jar,
/// and a sealed jar crystallizes into a Sweat Crystal gem. Going past the goal fills more jars.
enum SweatJar {
    /// Most jars one workout can seal (so a tiny goal can't farm crystals).
    static let maxPerWorkout = 3

    /// Fill measured in jars: 0.5 is half a jar, 1.4 is one sealed jar and 40% of the next.
    static func fill(steps: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return Double(max(0, steps)) / Double(goal)
    }

    static func sealed(steps: Int, goal: Int) -> Int {
        min(maxPerWorkout, Int(fill(steps: steps, goal: goal)))
    }

    /// How full the jar being filled right now is (a fully sealed set shows a full jar).
    static func currentJarFill(steps: Int, goal: Int) -> Double {
        let fill = fill(steps: steps, goal: goal)
        let sealed = sealed(steps: steps, goal: goal)
        if sealed >= maxPerWorkout { return 1 }
        return fill - Double(sealed)
    }

    /// Blue sweat for walks, orange for runs.
    static func liquid(for activity: ActivityType) -> Color {
        activity == .run ? Color(hex: 0xFF8A2A) : Color(hex: 0x4FC3FF)
    }

    static func lifetimeSealed(_ workouts: [WorkoutRecord]) -> Int {
        workouts.reduce(0) { $0 + sealed(steps: $1.steps, goal: $1.goalSteps) }
    }

    /// "OCT 16" on a sealed jar's label.
    static func label(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }
}

/// Kou, the mascot, gets fitter as you seal jars.
struct MascotStage: Equatable, Identifiable {
    let number: Int
    let title: String
    let jarsNeeded: Int
    /// What changes on Kou at this stage.
    let unlock: String

    var id: Int { number }

    static let name = "Kou"

    static let all: [MascotStage] = [
        MascotStage(number: 0, title: "Couch Bean", jarsNeeded: 0, unlock: "Ready to start"),
        MascotStage(number: 1, title: "Warming Up", jarsNeeded: 3, unlock: "Mint headband"),
        MascotStage(number: 2, title: "Getting Fit", jarsNeeded: 10, unlock: "Fitter shape and racing stripes"),
        MascotStage(number: 3, title: "Athlete", jarsNeeded: 30, unlock: "Race bib"),
        MascotStage(number: 4, title: "Legend", jarsNeeded: 100, unlock: "Gold medal"),
    ]

    static func forJars(_ jars: Int) -> MascotStage {
        all.last(where: { jars >= $0.jarsNeeded }) ?? all[0]
    }

    var next: MascotStage? {
        number + 1 < MascotStage.all.count ? MascotStage.all[number + 1] : nil
    }

    func progress(jars: Int) -> Double {
        guard let next else { return 1 }
        return min(1, max(0, Double(jars - jarsNeeded) / Double(next.jarsNeeded - jarsNeeded)))
    }

    // Looks
    var chubbiness: CGFloat { [1.12, 1.08, 1.02, 0.96, 0.96][number] }
    var hasHeadband: Bool { number >= 1 }
    var hasStripes: Bool { number >= 2 }
    var hasBib: Bool { number == 3 }
    var hasMedal: Bool { number >= 4 }
}
