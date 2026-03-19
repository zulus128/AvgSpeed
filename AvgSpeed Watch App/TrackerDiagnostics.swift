//
//  TrackerDiagnostics.swift
//  AvgSpeed Watch App
//
//  Persistent diagnostic log storage for standalone device runs.
//

import Combine
import Foundation

@MainActor
final class TrackerDiagnostics: ObservableObject {
    static let shared = TrackerDiagnostics()

    @Published private(set) var entries: [String] = []

    private let defaults = SharedDefaults.store
    private let entriesKey = "trackerDiagnosticEntries"
    private let maxEntryCount = 500
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        entries = defaults.stringArray(forKey: entriesKey) ?? []
    }

    func log(_ message: String) {
        let entry = "\(timestampFormatter.string(from: Date())) \(message)"
        print(entry)

        entries.append(entry)
        if entries.count > maxEntryCount {
            entries.removeFirst(entries.count - maxEntryCount)
        }

        defaults.set(entries, forKey: entriesKey)
    }

    func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: entriesKey)
    }
}
