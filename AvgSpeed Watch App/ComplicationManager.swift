//
//  ComplicationManager.swift
//  AvgSpeed Watch App
//
//  Stores the latest average speed and asks ClockKit to refresh.
//

import ClockKit
import Foundation

final class ComplicationManager {
    static let shared = ComplicationManager()

    private let defaults = UserDefaults.standard
    private let averageKey = "latestAverageSpeedKmh"
    private let runningKey = "isTracking"
    private let updatedAtKey = "avgSpeedUpdatedAt"

    private init() {}

    func pushAverageSpeed(_ speedKmh: Double) {
        pushState(averageSpeedKmh: speedKmh, isRunning: true)
    }

    func pushState(averageSpeedKmh speedKmh: Double, isRunning: Bool) {
        defaults.set(speedKmh, forKey: averageKey)
        defaults.set(isRunning, forKey: runningKey)
        defaults.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
        reloadAllComplications()
    }

    func cachedAverageSpeed() -> Double {
        defaults.double(forKey: averageKey)
    }

    func cachedIsRunning() -> Bool {
        defaults.bool(forKey: runningKey)
    }

    func cachedUpdatedAt() -> Date? {
        let ts = defaults.double(forKey: updatedAtKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    private func reloadAllComplications() {
        let server = CLKComplicationServer.sharedInstance()
        server.activeComplications?.forEach { complication in
            server.reloadTimeline(for: complication)
        }
    }
}
