//
//  ComplicationManager.swift
//  AvgSpeed Watch App
//
//  Stores the latest average speed and asks WidgetKit to refresh.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import OSLog

private let complicationLogger = Logger(subsystem: "com.vkassin.AvgSpeed", category: "complication")

final class ComplicationManager {
    static let shared = ComplicationManager()

    private let defaults = SharedDefaults.store
    private let averageKey = "latestAverageSpeedKmh"
    private let runningKey = "isTracking"
    private let updatedAtKey = "avgSpeedUpdatedAt"
    private let lastWidgetReloadAtKey = "avgSpeedLastWidgetReloadAt"

    private let widgetReloadInterval: TimeInterval = 15
    private let widgetKind = "AvgSpeedComplication"

    private init() {}

    func pushAverageSpeed(_ speedKmh: Double) {
        pushState(averageSpeedKmh: speedKmh, isRunning: true)
    }

    func pushState(averageSpeedKmh speedKmh: Double, isRunning: Bool, forceReload: Bool = false) {
        defaults.set(speedKmh, forKey: averageKey)
        defaults.set(isRunning, forKey: runningKey)
        let now = Date().timeIntervalSince1970
        defaults.set(now, forKey: updatedAtKey)
        complicationLogger.notice(
            "pushState speed=\(speedKmh, format: .fixed(precision: 1)) running=\(isRunning, privacy: .public) forceReload=\(forceReload, privacy: .public)"
        )

        let lastWidgetReloadAt = defaults.double(forKey: lastWidgetReloadAtKey)
        if forceReload || (now - lastWidgetReloadAt) >= widgetReloadInterval {
            defaults.set(now, forKey: lastWidgetReloadAtKey)
            reloadWidgetComplications()
        }
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

    private func reloadWidgetComplications() {
#if canImport(WidgetKit)
        if #available(watchOSApplicationExtension 9.0, *) {
            complicationLogger.notice("requesting WidgetKit reload for kind=\(self.widgetKind, privacy: .public)")
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
#endif
    }
}
