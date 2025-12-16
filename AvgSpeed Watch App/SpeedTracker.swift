//
//  SpeedTracker.swift
//  AvgSpeed Watch App
//
//  Core logic for tracking speed and keeping the complication updated.
//

import SwiftUI
import Combine
import CoreLocation
import ClockKit

@MainActor
final class SpeedTracker: NSObject, ObservableObject {
    static let shared = SpeedTracker()

    enum StopReason {
        case user
        case complication
        case workoutEnded
        case permission
    }

    // Published for UI
    @Published private(set) var isTracking = false
    @Published private(set) var isStarting = false
    @Published private(set) var averageSpeedKmh: Double = 0
    @Published private(set) var currentSpeedKmh: Double = 0
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var statusMessage: String?

    private let locationManager = CLLocationManager()
    private let workoutManager = WorkoutManager()
    private var lastLocation: CLLocation?
    private var totalDistance: CLLocationDistance = 0
    private var startDate: Date?
    private var timer: Timer?
    private var pendingStartAfterAuth = false
    private var lastComplicationPush: Double = 0
    private var lastComplicationUpdateTime: TimeInterval = 0

    private let startupWarmupDuration: TimeInterval = 2
    private let maxAcceptedLocationAge: TimeInterval = 10
    private let maxHorizontalAccuracyForDistance: CLLocationAccuracy = 100
    private let minDistanceSampleInterval: TimeInterval = 1
    private let maxSegmentSpeedKmh: Double = 300
    private var ignoreLocationUpdatesUntil: Date?

    private let speedSmoothingWindow: TimeInterval = 8
    private var recentLocations: [CLLocation] = []

    private override init() {
        super.init()
        configureLocationManager()
        workoutManager.onEnded = { [weak self] error in
            guard let self else { return }
            if let error {
                statusMessage = error.localizedDescription
            }
            if isTracking || isStarting {
                stopTracking(reason: .workoutEnded)
            }
        }
    }

    func prepare() {
        // Called on appear to sync auth state (avoid blocking the main thread).
        Task.detached(priority: .utility) {
            let status = CLLocationManager.authorizationStatus()
            await MainActor.run {
                SpeedTracker.shared.authorizationStatus = status
            }
        }
    }

    func toggleTracking() {
        isTracking ? stopTracking(reason: .user) : startTracking()
    }

    func stopFromComplicationTap() {
        stopTracking(reason: .complication)
    }

    func startTracking() {
        guard !isTracking, !isStarting else { return }
        resetMetrics()
        statusMessage = "Starting…"

        // Avoid calling CLLocationManager authorization checks on the main thread.
        Task.detached(priority: .userInitiated) {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            let status = CLLocationManager.authorizationStatus()
            await MainActor.run {
                SpeedTracker.shared.startTrackingAfterLocationCheck(servicesEnabled: servicesEnabled, status: status)
            }
        }
    }

    private func startTrackingAfterLocationCheck(servicesEnabled: Bool, status: CLAuthorizationStatus) {
        guard servicesEnabled else {
            statusMessage = "Location services disabled"
            return
        }

        authorizationStatus = status
        if authorizationStatus == .notDetermined {
            pendingStartAfterAuth = true
            locationManager.requestWhenInUseAuthorization()
            statusMessage = "Requesting location access…"
            return
        }

        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            statusMessage = "Enable location in Settings"
            stopTracking(reason: .permission)
            return
        }

        guard !isTracking, !isStarting else { return }

        statusMessage = "Starting workout…"
        isStarting = true

        Task {
            do {
                let workoutStartDate = try await workoutManager.start()
                guard isStarting else {
                    workoutManager.stop()
                    return
                }
                startDate = workoutStartDate
                startElapsedTimer()
                ignoreLocationUpdatesUntil = Date().addingTimeInterval(startupWarmupDuration)
                locationManager.startUpdatingLocation()
                isStarting = false
                isTracking = true
                statusMessage = "Tracking…"
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true)
            } catch {
                guard isStarting else { return }
                startDate = Date()
                startElapsedTimer()
                ignoreLocationUpdatesUntil = Date().addingTimeInterval(startupWarmupDuration)
                locationManager.startUpdatingLocation()
                isStarting = false
                isTracking = true
                statusMessage = "Tracking without workout: \(error.localizedDescription)"
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true)
            }
        }
    }

    func stopTracking(reason: StopReason) {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        isTracking = false
        isStarting = false
        startDate = nil
        workoutManager.stop()
        ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: false)

        switch reason {
        case .complication:
            statusMessage = "Stopped from complication"
        case .workoutEnded:
            if statusMessage == nil {
                statusMessage = "Workout ended"
            }
        case .permission:
            if statusMessage == nil {
                statusMessage = "Location permission needed"
            }
        case .user:
            statusMessage = nil
        }
    }
}

#if DEBUG
extension SpeedTracker {
    static var previewModel: SpeedTracker {
        let tracker = SpeedTracker.shared
        tracker.isTracking = true
        tracker.averageSpeedKmh = 24.6
        tracker.currentSpeedKmh = 26.3
        tracker.distanceKm = 3.42
        tracker.elapsed = 780
        tracker.statusMessage = "Preview data"
        return tracker
    }
}
#endif

// MARK: - Private helpers
private extension SpeedTracker {
    func configureLocationManager() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 10
    }

    func resetMetrics() {
        totalDistance = 0
        distanceKm = 0
        averageSpeedKmh = 0
        currentSpeedKmh = 0
        elapsed = 0
        lastLocation = nil
        recentLocations.removeAll()
        lastComplicationPush = 0
        lastComplicationUpdateTime = 0
        startDate = nil
        ignoreLocationUpdatesUntil = nil
    }

    func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate else { return }
            elapsed = Date().timeIntervalSince(startDate)
        }
    }

    func updateMetrics(with location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) <= maxAcceptedLocationAge else { return }

        if let ignoreUntil = ignoreLocationUpdatesUntil, Date() < ignoreUntil {
            lastLocation = location
            recentLocations = [location]
            averageSpeedKmh = 0
            currentSpeedKmh = 0
            distanceKm = 0
            return
        } else {
            ignoreLocationUpdatesUntil = nil
        }

        recentLocations.append(location)
        recentLocations = recentLocations.filter {
            $0.horizontalAccuracy >= 0 &&
            $0.horizontalAccuracy <= maxHorizontalAccuracyForDistance &&
            abs($0.timestamp.timeIntervalSinceNow) <= maxAcceptedLocationAge &&
            location.timestamp.timeIntervalSince($0.timestamp) <= speedSmoothingWindow
        }

        if let last = lastLocation {
            let distance = location.distance(from: last)
            let interval = location.timestamp.timeIntervalSince(last.timestamp)
            let segmentSpeed = (interval > 0) ? (distance / interval) * 3.6 : Double.greatestFiniteMagnitude

            if interval >= minDistanceSampleInterval,
               distance >= 0,
               segmentSpeed <= maxSegmentSpeedKmh,
               location.horizontalAccuracy <= maxHorizontalAccuracyForDistance,
               last.horizontalAccuracy >= 0,
               last.horizontalAccuracy <= maxHorizontalAccuracyForDistance {
                totalDistance += distance
                distanceKm = totalDistance / 1000
            }
        }

        if let startDate {
            elapsed = Date().timeIntervalSince(startDate)
            if elapsed > 0 {
                averageSpeedKmh = (totalDistance / elapsed) * 3.6
            }
        }

        if recentLocations.count >= 2, let first = recentLocations.first {
            let windowDistance = location.distance(from: first)
            let windowTime = max(location.timestamp.timeIntervalSince(first.timestamp), minDistanceSampleInterval)
            currentSpeedKmh = max(windowDistance / windowTime * 3.6, 0)
        } else {
            currentSpeedKmh = 0
        }

        pushToComplicationIfNeeded()
        lastLocation = location
    }

    func pushToComplicationIfNeeded() {
        // Avoid spamming ClockKit; only reload when the value changes meaningfully.
        let now = Date().timeIntervalSince1970
        let delta = abs(averageSpeedKmh - lastComplicationPush)
        if delta >= 0.5 || (delta >= 0.1 && (now - lastComplicationUpdateTime) >= 10) {
            lastComplicationPush = averageSpeedKmh
            lastComplicationUpdateTime = now
            ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension SpeedTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if pendingStartAfterAuth && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) {
                pendingStartAfterAuth = false
                startTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard isTracking else { return }
            updateMetrics(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "Location error: \(error.localizedDescription)"
            stopTracking(reason: .permission)
        }
    }
}
