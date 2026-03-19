//
//  SpeedTracker.swift
//  AvgSpeed Watch App
//
//  Core logic for tracking speed and keeping the complication updated.
//

import SwiftUI
import Combine
import CoreLocation

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
    @Published private(set) var gpsSpeedKmh: Double = 0
    @Published private(set) var isGpsFresh = false
    @Published private(set) var isGpsWeak = false
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
    private var distanceAnchorLocation: CLLocation?
    private var totalDistance: CLLocationDistance = 0
    private var initialSpeedSeedKmh: Double?
    private var measurementStartDate: Date?
    private var distanceElapsed: TimeInterval = 0
    private var startDate: Date?
    private var timer: Timer?
    private var lastGpsUpdate: Date?
    private var pendingStartAfterAuth = false
    private var pendingStartAfterWorkoutEnd = false

    private let startupWarmupDuration: TimeInterval = 2
    private let maxAcceptedLocationAge: TimeInterval = 10
    private let maxHorizontalAccuracyForSpeedSmoothing: CLLocationAccuracy = 200
    private let maxHorizontalAccuracyForDistance: CLLocationAccuracy = 250
    private let maxHorizontalAccuracyForEstimatedDistance: CLLocationAccuracy = 300
    private let minDistanceSampleInterval: TimeInterval = 1
    private let maxEstimatedDistanceInterval: TimeInterval = 5
    private let minGapBridgeInterval: TimeInterval = 15
    private let maxGapBridgeInterval: TimeInterval = 300
    private let minEstimatedSpeedKmh: Double = 3
    private let maxEstimatedSpeedKmh: Double = 180
    private let maxSegmentSpeedKmh: Double = 300
    private var ignoreLocationUpdatesUntil: Date?
    private var hasReliableDistanceSample = false

    private let speedSmoothingWindow: TimeInterval = 8
    private var recentLocations: [CLLocation] = []

    private override init() {
        super.init()
        configureLocationManager()
        workoutManager.onEnded = { [weak self] error in
            guard let self else { return }
            if let error {
                recordDiagnostic("[SpeedTracker] Workout ended with error: \(error.localizedDescription)")
                statusMessage = nil
            }
            if pendingStartAfterWorkoutEnd {
                pendingStartAfterWorkoutEnd = false
                recordDiagnostic("[SpeedTracker] Waiting workout ended; retrying start")
                startTracking()
                return
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
        pendingStartAfterWorkoutEnd = false
        resetMetrics()
        statusMessage = "Starting…"
        recordDiagnostic("[SpeedTracker] Start requested")

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
            recordDiagnostic("[SpeedTracker] Location services disabled")
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
            recordDiagnostic("[SpeedTracker] Location permission not granted: \(authorizationStatus)")
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
                recordDiagnostic("[SpeedTracker] Tracking started workout=\(workoutManager.isRunning)")
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true, forceReload: true)
            } catch {
                guard isStarting else { return }
                if let workoutError = error as? WorkoutManager.WorkoutError {
                    switch workoutError {
                    case .anotherWorkoutAlreadyRunning:
                        isStarting = false
                        if workoutManager.hasSession {
                            pendingStartAfterWorkoutEnd = true
                            statusMessage = "Waiting for workout to end..."
                        } else {
                            statusMessage = "Another workout is already running."
                        }
                        return
                    default:
                        break
                    }
                }
                recordDiagnostic("[SpeedTracker] Workout start failed: \(error.localizedDescription)")
                startDate = Date()
                startElapsedTimer()
                ignoreLocationUpdatesUntil = Date().addingTimeInterval(startupWarmupDuration)
                locationManager.startUpdatingLocation()
                isStarting = false
                isTracking = true
                statusMessage = nil
                recordDiagnostic("[SpeedTracker] Tracking started without workout session")
                ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true, forceReload: true)
            }
        }
    }

    func stopTracking(reason: StopReason) {
        pendingStartAfterWorkoutEnd = false
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        isTracking = false
        isStarting = false
        isGpsFresh = false
        isGpsWeak = false
        lastGpsUpdate = nil
        startDate = nil
        workoutManager.stop()
        recordDiagnostic(
            "[SpeedTracker] Tracking stopped " +
            "reason=\(stopReasonLabel(reason)) " +
            "distance_km=\(String(format: "%.3f", distanceKm)) " +
            "elapsed_s=\(String(format: "%.1f", elapsed))"
        )
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
            recordDiagnostic("[SpeedTracker] Demo simulation ignored (already tracking)")
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

        recordDiagnostic("[SpeedTracker] Demo simulation started")
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
        gpsSpeedKmh = simulatedSpeedKmh
        lastGpsUpdate = now

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
        tracker.gpsSpeedKmh = 25.9
        tracker.distanceKm = 3.42
        tracker.elapsed = 780
        tracker.statusMessage = "Preview data"
        tracker.isGpsFresh = true
        tracker.isGpsWeak = false
        tracker.lastGpsUpdate = Date()
        return tracker
    }
}
#endif

// MARK: - Private helpers
private extension SpeedTracker {
    func configureLocationManager() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 5
    }

    func resetMetrics() {
        totalDistance = 0
        distanceKm = 0
        averageSpeedKmh = 0
        currentSpeedKmh = 0
        gpsSpeedKmh = 0
        initialSpeedSeedKmh = nil
        measurementStartDate = nil
        distanceElapsed = 0
        elapsed = 0
        lastLocation = nil
        distanceAnchorLocation = nil
        recentLocations.removeAll()
        startDate = nil
        ignoreLocationUpdatesUntil = nil
        hasReliableDistanceSample = false
        isGpsFresh = false
        isGpsWeak = false
        lastGpsUpdate = nil
    }

    func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, startDate != nil else { return }
                let now = Date()
                refreshElapsedAndAverage(at: now)
                updateGpsFreshness(now: now)
#if DEBUG
                tickSimulatedMotion(now: now)
#endif
            }
        }
    }

    func updateMetrics(with location: CLLocation, allowHistoricalSample: Bool = false) {
        guard location.horizontalAccuracy >= 0 else { return }
        guard shouldProcessLocationTimestamp(location.timestamp, allowHistoricalSample: allowHistoricalSample) else { return }

        let rawSpeedKmh = max(location.speed, 0) * 3.6
        gpsSpeedKmh = rawSpeedKmh
        lastGpsUpdate = location.timestamp
        updateGpsFreshness(now: Date())
        isGpsWeak = location.horizontalAccuracy > maxHorizontalAccuracyForDistance

        let now = Date()
        if let ignoreUntil = ignoreLocationUpdatesUntil {
            if now < ignoreUntil {
                isGpsWeak = false
                lastLocation = location
                recentLocations = [location]
                averageSpeedKmh = 0
                currentSpeedKmh = 0
                distanceKm = 0
                return
            }

            // Warmup just ended; drop warmup samples entirely.
            ignoreLocationUpdatesUntil = nil
            lastLocation = nil
            distanceAnchorLocation = nil
            recentLocations.removeAll()
            measurementStartDate = nil
            distanceElapsed = 0
            totalDistance = 0
            distanceKm = 0
            averageSpeedKmh = 0
            currentSpeedKmh = 0
            initialSpeedSeedKmh = nil
            hasReliableDistanceSample = false
        }

        recentLocations.append(location)
        recentLocations = recentLocations.filter {
            $0.horizontalAccuracy >= 0 &&
            $0.horizontalAccuracy <= maxHorizontalAccuracyForSpeedSmoothing &&
            location.timestamp.timeIntervalSince($0.timestamp) >= 0 &&
            location.timestamp.timeIntervalSince($0.timestamp) <= speedSmoothingWindow
        }

        let currentSpeedSampleKmh: Double
        if recentLocations.count >= 2, let first = recentLocations.first {
            let windowDistance = location.distance(from: first)
            let windowTime = max(location.timestamp.timeIntervalSince(first.timestamp), minDistanceSampleInterval)
            currentSpeedSampleKmh = max(windowDistance / windowTime * 3.6, 0)
        } else {
            currentSpeedSampleKmh = 0
        }

        if initialSpeedSeedKmh == nil, currentSpeedSampleKmh > 0 {
            initialSpeedSeedKmh = currentSpeedSampleKmh
        }

        var usedEstimatedDistance = false
        var usedGapBridge = false
        var skippedOverlongGapBridge = false

        if let last = distanceAnchorLocation ?? lastLocation {
            let distance = location.distance(from: last)
            let interval = location.timestamp.timeIntervalSince(last.timestamp)
            let segmentSpeed = (interval > 0) ? (distance / interval) * 3.6 : Double.greatestFiniteMagnitude
            let hasReliableAccuracyPair =
                location.horizontalAccuracy <= maxHorizontalAccuracyForDistance &&
                last.horizontalAccuracy >= 0 &&
                last.horizontalAccuracy <= maxHorizontalAccuracyForDistance
            let isLongGapBridge = interval >= minGapBridgeInterval

            if interval >= minDistanceSampleInterval,
               distance >= 0,
               segmentSpeed <= maxSegmentSpeedKmh,
               hasReliableAccuracyPair,
               (!isLongGapBridge || interval <= maxGapBridgeInterval) {
                let seedKmh = currentSpeedSampleKmh > 0 ? currentSpeedSampleKmh : segmentSpeed
                applyDistanceSample(distanceMeters: distance, interval: interval, anchor: last.timestamp, seedKmh: seedKmh)
                hasReliableDistanceSample = true
                distanceAnchorLocation = location
                usedGapBridge = isLongGapBridge
            } else if interval >= minDistanceSampleInterval,
                      hasReliableDistanceSample,
                      interval <= maxEstimatedDistanceInterval,
                      location.horizontalAccuracy <= maxHorizontalAccuracyForEstimatedDistance,
                      rawSpeedKmh >= minEstimatedSpeedKmh,
                      rawSpeedKmh <= maxEstimatedSpeedKmh {
                // Fallback for short stretches of weak GPS geometry so distance does not flatline.
                let estimatedDistance = (rawSpeedKmh / 3.6) * interval
                applyDistanceSample(distanceMeters: estimatedDistance, interval: interval, anchor: last.timestamp, seedKmh: rawSpeedKmh)
                usedEstimatedDistance = true
                distanceAnchorLocation = location
            } else if hasReliableAccuracyPair,
                      interval > maxGapBridgeInterval {
                // Re-anchor after an overlong outage instead of bridging from stale geometry.
                distanceAnchorLocation = location
                skippedOverlongGapBridge = true
            }
        }

        if distanceAnchorLocation == nil,
           location.horizontalAccuracy <= maxHorizontalAccuracyForDistance {
            distanceAnchorLocation = location
        }

        isGpsWeak = isGpsWeak || usedEstimatedDistance || usedGapBridge

        currentSpeedKmh = currentSpeedSampleKmh
        refreshElapsedAndAverage(at: location.timestamp, currentSpeedSampleKmh: currentSpeedSampleKmh)

#if DEBUG
        debugLogAverage(
            source: skippedOverlongGapBridge ? "gap-reset" : (usedGapBridge ? "gap-bridge" : (usedEstimatedDistance ? "estimated" : "location")),
            totalDistanceMeters: totalDistance,
            travelSeconds: distanceElapsed,
            sessionSeconds: elapsed,
            horizontalAccuracy: location.horizontalAccuracy,
            gpsSpeedKmh: rawSpeedKmh,
            currentSpeedKmh: currentSpeedSampleKmh,
            averageSpeedKmh: averageSpeedKmh,
            seedKmh: initialSpeedSeedKmh
        )
#endif

        pushToComplicationIfNeeded()
        lastLocation = location
    }

    func pushToComplicationIfNeeded() {
        // Always store the latest state; ComplicationManager throttles reloadTimeline.
        ComplicationManager.shared.pushState(averageSpeedKmh: averageSpeedKmh, isRunning: true)
    }

    func recordDiagnostic(_ message: String) {
        TrackerDiagnostics.shared.log(message)
    }

    func stopReasonLabel(_ reason: StopReason) -> String {
        switch reason {
        case .user:
            return "user"
        case .complication:
            return "complication"
        case .workoutEnded:
            return "workoutEnded"
        case .permission:
            return "permission"
        }
    }

    func updateGpsFreshness(now: Date) {
        guard isTracking, let lastGpsUpdate else {
            isGpsFresh = false
            isGpsWeak = false
            return
        }
        isGpsFresh = now.timeIntervalSince(lastGpsUpdate) <= maxAcceptedLocationAge
        if !isGpsFresh {
            isGpsWeak = false
        }
    }

    func applyDistanceSample(
        distanceMeters: CLLocationDistance,
        interval: TimeInterval,
        anchor: Date,
        seedKmh: Double
    ) {
        guard interval > 0, distanceMeters >= 0 else { return }
        if measurementStartDate == nil {
            measurementStartDate = anchor
        }
        if initialSpeedSeedKmh == nil {
            initialSpeedSeedKmh = max(seedKmh, 0)
        }
        distanceElapsed += interval
        totalDistance += distanceMeters
        distanceKm = totalDistance / 1000
    }

    func shouldProcessLocationTimestamp(_ timestamp: Date, allowHistoricalSample: Bool) -> Bool {
        if timestamp.timeIntervalSinceNow > maxAcceptedLocationAge {
            return false
        }

        if let startDate, timestamp < startDate {
            return false
        }

        if let lastLocation, timestamp <= lastLocation.timestamp {
            return false
        }

        if allowHistoricalSample {
            return true
        }

        return abs(timestamp.timeIntervalSinceNow) <= maxAcceptedLocationAge
    }

    func refreshElapsedAndAverage(at date: Date, currentSpeedSampleKmh: Double? = nil) {
        guard let referenceStart = measurementStartDate ?? startDate else {
            elapsed = 0
            averageSpeedKmh = 0
            return
        }

        let sessionElapsed = max(date.timeIntervalSince(referenceStart), 0)
        elapsed = sessionElapsed

        if hasReliableDistanceSample, sessionElapsed > 0 {
            averageSpeedKmh = (totalDistance / sessionElapsed) * 3.6
            return
        }

        if let currentSpeedSampleKmh, currentSpeedSampleKmh > 0 {
            averageSpeedKmh = initialSpeedSeedKmh ?? currentSpeedSampleKmh
        } else if let initialSpeedSeedKmh, initialSpeedSeedKmh > 0 {
            averageSpeedKmh = initialSpeedSeedKmh
        } else {
            averageSpeedKmh = 0
        }
    }

    #if DEBUG
    private func debugLogAverage(
        source: String,
        totalDistanceMeters: Double,
        travelSeconds: TimeInterval,
        sessionSeconds: TimeInterval,
        horizontalAccuracy: Double,
        gpsSpeedKmh: Double,
        currentSpeedKmh: Double,
        averageSpeedKmh: Double,
        seedKmh: Double?
    ) {
        let distanceKm = totalDistanceMeters / 1000
        let formatter: (Double, Int) -> String = { value, decimals in
            String(format: "%.\(decimals)f", value)
        }
        let seed = seedKmh ?? 0
        let averageDeviation = averageSpeedKmh - seed

        recordDiagnostic(
            "[AvgSpeed][\(source)] " +
            "distance_m=\(formatter(totalDistanceMeters, 2)) " +
            "distance_km=\(formatter(distanceKm, 6)) " +
            "travel_s=\(formatter(travelSeconds, 4)) " +
            "session_s=\(formatter(sessionSeconds, 4)) " +
            "accuracy_m=\(formatter(horizontalAccuracy, 1)) " +
            "gps_kmh=\(formatter(gpsSpeedKmh, 3)) " +
            "current_kmh=\(formatter(currentSpeedKmh, 3)) " +
            "seed_kmh=\(formatter(seed, 3)) " +
            "avg_dev_kmh=\(formatter(averageDeviation, 3)) " +
            "average_kmh=\(formatter(averageSpeedKmh, 3))"
        )
    }
    #endif
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
        let orderedLocations = locations.sorted { $0.timestamp < $1.timestamp }
        guard !orderedLocations.isEmpty else { return }
        Task { @MainActor in
            guard isTracking else { return }
#if DEBUG
            if orderedLocations.count > 1,
               let first = orderedLocations.first,
               let last = orderedLocations.last {
                let span = max(last.timestamp.timeIntervalSince(first.timestamp), 0)
                recordDiagnostic("[SpeedTracker] Processing location batch count=\(orderedLocations.count) span_s=\(String(format: "%.2f", span))")
            }
#endif
            for location in orderedLocations {
                guard isTracking else { break }
                updateMetrics(with: location, allowHistoricalSample: true)
            }
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
                    recordDiagnostic("\(prefix) (locationUnknown; will keep trying)")
                    return
                case .denied:
                    recordDiagnostic("\(prefix) (denied)")
                    statusMessage = nil
                    stopTracking(reason: .permission)
                    return
                default:
                    break
                }
            }

            // For other errors, log but don't stop; CoreLocation may recover on its own.
            recordDiagnostic(prefix)
            statusMessage = nil
        }
    }
}
