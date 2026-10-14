import Foundation
import CoreMotion

/// Step counting from the phone's motion coprocessor.
final class PedometerService {
    private let pedometer = CMPedometer()

    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Live steps since `date`. The handler is called on the main queue.
    func startUpdates(from date: Date, handler: @escaping (Int) -> Void) {
        guard Self.isAvailable else { return }
        pedometer.startUpdates(from: date) { data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { handler(steps) }
        }
    }

    func stopUpdates() {
        pedometer.stopUpdates()
    }

    /// Steps between two dates (the system keeps about 7 days of history).
    func steps(from start: Date, to end: Date) async -> Int? {
        guard Self.isAvailable else { return nil }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    /// Steps per day for the last `days` days, oldest first.
    func dailySteps(days: Int) async -> [(day: Date, steps: Int)]? {
        guard Self.isAvailable else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(day: Date, steps: Int)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let steps = await self.steps(from: day, to: min(next, Date())) ?? 0
            result.append((day, steps))
        }
        return result
    }
}
