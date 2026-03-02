//
//  SharedDefaults.swift
//  AvgSpeed Watch App
//
//  App-group backed defaults for watch app + complication widget.
//

import Foundation

enum SharedDefaults {
    static let appGroupIdentifier = "group.7TTF49AXF6.com.vkassin.AvgSpeed"

    static var store: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static let migrationFlagKey = "avgSpeedDidMigrateToAppGroup"

    static func migrateLegacyValuesIfNeeded() {
        let shared = store
        guard !shared.bool(forKey: migrationFlagKey) else { return }

        let standard = UserDefaults.standard
        let keysToMigrate: [String] = [
            "speed_limit_kmh",
            "speed_unit",
            "latestAverageSpeedKmh",
            "isTracking",
            "avgSpeedUpdatedAt",
            "avgSpeedLastComplicationReloadAt",
            "avgSpeedLastWidgetReloadAt",
        ]

        for key in keysToMigrate where shared.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }

        shared.set(true, forKey: migrationFlagKey)
    }
}
