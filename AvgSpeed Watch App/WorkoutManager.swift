//
//  WorkoutManager.swift
//  AvgSpeed Watch App
//
//  Starts an HKWorkoutSession to keep the app running reliably in the background.
//  The workout is NOT saved to HealthKit (no HKWorkoutBuilder is finished).
//

import Foundation
import HealthKit

@MainActor
final class WorkoutManager: NSObject {
    enum WorkoutError: LocalizedError {
        case healthDataUnavailable
        case missingEntitlement
        case authorizationDenied
        case anotherWorkoutAlreadyRunning
        case liveWorkoutUnavailable
        case workoutSessionInitFailed(Error)

        var errorDescription: String? {
            switch self {
            case .healthDataUnavailable:
                return "Health data unavailable on this device."
            case .missingEntitlement:
                return "HealthKit entitlement is missing. Enable the HealthKit capability for the watch target and reinstall the app."
            case .authorizationDenied:
                return "Health permission not granted."
            case .anotherWorkoutAlreadyRunning:
                return "Another workout is already running on the watch. End it and try again."
            case .liveWorkoutUnavailable:
                return "Workout sessions aren’t available in the watchOS Simulator."
            case .workoutSessionInitFailed(let error):
                return "Workout session failed: \(error.localizedDescription)"
            }
        }
    }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    var onEnded: ((Error?) -> Void)?

    var isRunning: Bool {
        session?.state == .running
    }

    func start() async throws -> Date {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutError.healthDataUnavailable
        }

#if targetEnvironment(simulator)
        throw WorkoutError.liveWorkoutUnavailable
#endif

        try await requestAuthorizationIfNeeded()

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self
            self.session = session

            let startDate = Date()
            session.startActivity(with: startDate)
            return startDate
        } catch {
            if Self.isAnotherWorkoutAlreadyRunning(error) {
                cleanupAfterFailure()
                throw WorkoutError.anotherWorkoutAlreadyRunning
            }
            cleanupAfterFailure()
            throw WorkoutError.workoutSessionInitFailed(error)
        }
    }

    func stop() {
        session?.end()
        session = nil
    }
}

private extension WorkoutManager {
    func requestAuthorizationIfNeeded() async throws {
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        if status == .sharingAuthorized {
            return
        }

        let shareTypes: Set<HKSampleType> = [workoutType]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: []) { success, error in
                if let error {
                    if Self.isMissingEntitlement(error) {
                        continuation.resume(throwing: WorkoutError.missingEntitlement)
                        return
                    }
                    if Self.isAnotherWorkoutAlreadyRunning(error) {
                        continuation.resume(throwing: WorkoutError.anotherWorkoutAlreadyRunning)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: WorkoutError.authorizationDenied)
                }
            }
        }
    }

    nonisolated static func isAnotherWorkoutAlreadyRunning(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return false }
        // HKErrorAnotherWorkoutSessionStarted
        return nsError.code == 8
    }

    nonisolated static func isMissingEntitlement(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return false }
        let description = nsError.localizedDescription.lowercased()
        return description.contains("com.apple.developer.healthkit") && description.contains("entitlement")
    }

    func cleanupAfterFailure() {
        session?.end()
        session = nil
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            Task { @MainActor in
                onEnded?(nil)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            onEnded?(error)
        }
    }
}
