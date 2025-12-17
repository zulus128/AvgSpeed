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

#if DEBUG
    @Published private(set) var isSimulating = false
    private var simulationStartDate: Date?
    private var lastSimulationTick: Date?
#endif

    private let locationManager = CLLocationManager()
    private let workoutManager = WorkoutManager()
    private var lastLocation: CLLocation?
    private var totalDistance: CLLocationDistance = 0
    private var startDate: Date?
    private var timer: Timer?
    private var pendingStartAfterAuth = false

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
                print("[SpeedTracker] Workout ended with error: \(error.localizedDescription)")
                statusMessage = nil
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
            print("[SpeedTracker] Location services disabled")
            statusMessage = nil
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
            print("[SpeedTracker] Location permission not granted: \(authorizationStatus)")
            statusMessage = nil
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
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true, forceReload: true)
            } catch {
                guard isStarting else { return }
                print("[SpeedTracker] Workout start failed: \(error.localizedDescription)")
                startDate = Date()
                startElapsedTimer()
                ignoreLocationUpdatesUntil = Date().addingTimeInterval(startupWarmupDuration)
                locationManager.startUpdatingLocation()
                isStarting = false
                isTracking = true
                statusMessage = nil
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true, forceReload: true)
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
#if DEBUG
        isSimulating = false
        simulationStartDate = nil
        lastSimulationTick = nil
#endif
        ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: false, forceReload: true)

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
    func toggleDemoSimulation() {
        if isSimulating {
            stopTracking(reason: .user)
            return
        }

        guard !isTracking, !isStarting else {
            print("[SpeedTracker] Demo simulation ignored (already tracking)")
            return
        }

        startSimulatedTracking()
    }

    private func startSimulatedTracking() {
        resetMetrics()
        statusMessage = nil
        locationManager.stopUpdatingLocation()
        workoutManager.stop()

        let now = Date()
        startDate = now
        simulationStartDate = now
        lastSimulationTick = now

        isSimulating = true
        isTracking = true
        isStarting = false
        startElapsedTimer()

        print("[SpeedTracker] Demo simulation started")
        ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true, forceReload: true)
    }

    private func tickSimulatedMotion(now: Date) {
        guard isSimulating, let simulationStartDate else { return }
        guard let lastTick = lastSimulationTick else {
            lastSimulationTick = now
            return
        }

        let dt = now.timeIntervalSince(lastTick)
        guard dt > 0 else { return }

        let t = now.timeIntervalSince(simulationStartDate)
        let cycle: TimeInterval = 300
        let baseSpeedKmh: Double = 18
        let amplitudeKmh: Double = 10

        var simulatedSpeedKmh = baseSpeedKmh + amplitudeKmh * sin((t / cycle) * 2 * .pi)

        let stopCycle: TimeInterval = 90
        if t >= 30, (t.truncatingRemainder(dividingBy: stopCycle)) < 8 {
            simulatedSpeedKmh = 0
        }

        simulatedSpeedKmh = min(max(simulatedSpeedKmh, 0), 40)
        currentSpeedKmh = simulatedSpeedKmh

        totalDistance += (simulatedSpeedKmh / 3.6) * dt
        distanceKm = totalDistance / 1000

        if elapsed > 0 {
            averageSpeedKmh = (totalDistance / elapsed) * 3.6
        } else {
            averageSpeedKmh = 0
        }

        lastSimulationTick = now
        pushToComplicationIfNeeded()
    }

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
        startDate = nil
        ignoreLocationUpdatesUntil = nil
    }

    func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let startDate else { return }
            let now = Date()
            elapsed = now.timeIntervalSince(startDate)
#if DEBUG
            tickSimulatedMotion(now: now)
#endif
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
        // Always store the latest state; ComplicationManager throttles reloadTimeline.
        ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true)
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
        let nsError = error as NSError
        Task { @MainActor in
            let prefix = "[SpeedTracker] Location error: \(nsError.domain) \(nsError.code) – \(nsError.localizedDescription)"

            if nsError.domain == kCLErrorDomain, let code = CLError.Code(rawValue: nsError.code) {
                switch code {
                case .locationUnknown:
                    // Temporary condition (GPS acquiring, poor signal, indoors). Keep tracking.
                    print("\(prefix) (locationUnknown; will keep trying)")
                    return
                case .denied:
                    print("\(prefix) (denied)")
                    statusMessage = nil
                    stopTracking(reason: .permission)
                    return
                default:
                    break
                }
            }

            // For other errors, log but don't stop; CoreLocation may recover on its own.
            print(prefix)
            statusMessage = nil
        }
    }
}
