import Foundation
import HealthKit
import CoreLocation

/// Saves finished workouts (with distance, steps, energy and the GPS route) to Apple Health.
///
/// Needs the HealthKit capability, which requires a paid Apple Developer account. Without it,
/// authorization fails with an error and the app simply keeps workouts on the device.
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: shareTypes, read: []) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    var canSaveWorkouts: Bool {
        isAvailable && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func save(
        activity: ActivityType,
        start: Date,
        end: Date,
        distance: Double,
        steps: Int,
        calories: Double,
        locations: [CLLocation]
    ) async throws {
        guard canSaveWorkouts else { throw HealthError.notAuthorized }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity == .run ? .running : .walking
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        var samples: [HKSample] = []
        if distance > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: start, end: end
            ))
        }
        if steps > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: Double(steps)),
                start: start, end: end
            ))
        }
        if calories > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: start, end: end
            ))
        }

        if !samples.isEmpty {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.add(samples) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { finished, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: finished) }
            }
        }

        guard let workout, !locations.isEmpty else { return }
        try await saveRoute(locations, for: workout)
    }

    private func saveRoute(_ locations: [CLLocation], for workout: HKWorkout) async throws {
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.insertRouteData(locations) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.finishRoute(with: workout, metadata: nil) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    enum HealthError: LocalizedError {
        case unavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health isn't available on this device."
            case .notAuthorized: return "Walkou doesn't have permission to save workouts to Apple Health."
            }
        }
    }
}
