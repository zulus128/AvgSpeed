//
//  AvgSpeedComplication.swift
//  AvgSpeedComplicationExtension
//
//  WidgetKit complication provider for modern watch faces.
//

import SwiftUI
import WidgetKit
import OSLog

private let complicationLogger = Logger(subsystem: "com.vkassin.AvgSpeed", category: "complication")

private enum SharedComplicationDefaults {
    static let appGroupIdentifier = "group.7TTF49AXF6.com.vkassin.AvgSpeed"

    static var store: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static let averageKey = "latestAverageSpeedKmh"
    static let runningKey = "isTracking"
    static let speedUnitKey = "speed_unit"
}

private enum ComplicationSpeedUnit: String {
    case kmh
    case mph

    var speedLabel: String {
        switch self {
        case .kmh:
            return "km/h"
        case .mph:
            return "mi/h"
        }
    }

    var shortLabel: String {
        switch self {
        case .kmh:
            return "km"
        case .mph:
            return "mi"
        }
    }

    func speed(fromKmh kmh: Double) -> Double {
        switch self {
        case .kmh:
            return kmh
        case .mph:
            return kmh * 0.621_371
        }
    }
}

private struct AvgSpeedComplicationEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let displaySpeed: Double
    let unit: ComplicationSpeedUnit

    var valueText: String {
        isRunning ? String(format: "%.1f", displaySpeed) : "-"
    }

    var speedWithUnit: String {
        isRunning ? "\(valueText) \(unit.speedLabel)" : "-"
    }

    var inlineText: String {
        isRunning ? "Avg \(speedWithUnit)" : "Avg -"
    }
}

private struct AvgSpeedComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> AvgSpeedComplicationEntry {
        complicationLogger.notice("placeholder requested; preview=\(context.isPreview, privacy: .public)")
        return AvgSpeedComplicationEntry(
            date: Date(),
            isRunning: true,
            displaySpeed: 12.5,
            unit: .kmh
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AvgSpeedComplicationEntry) -> Void) {
        let entry = loadEntry(at: Date())
        complicationLogger.notice(
            "snapshot requested; preview=\(context.isPreview, privacy: .public) running=\(entry.isRunning, privacy: .public) speed=\(entry.displaySpeed, format: .fixed(precision: 1)) unit=\(entry.unit.rawValue, privacy: .public)"
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AvgSpeedComplicationEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(at: now)
        let nextRefresh = now.addingTimeInterval(30)
        complicationLogger.notice(
            "timeline requested; running=\(entry.isRunning, privacy: .public) speed=\(entry.displaySpeed, format: .fixed(precision: 1)) unit=\(entry.unit.rawValue, privacy: .public) nextRefresh=\(nextRefresh.formatted(date: .omitted, time: .standard), privacy: .public)"
        )
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry(at date: Date) -> AvgSpeedComplicationEntry {
        let defaults = SharedComplicationDefaults.store
        let averageSpeedKmh = defaults.double(forKey: SharedComplicationDefaults.averageKey)
        let isRunning = defaults.bool(forKey: SharedComplicationDefaults.runningKey)
        let unitRaw = defaults.string(forKey: SharedComplicationDefaults.speedUnitKey) ?? ComplicationSpeedUnit.kmh.rawValue
        let unit = ComplicationSpeedUnit(rawValue: unitRaw) ?? .kmh
        let displaySpeed = unit.speed(fromKmh: averageSpeedKmh)
        complicationLogger.notice(
            "loadEntry avgKmh=\(averageSpeedKmh, format: .fixed(precision: 1)) running=\(isRunning, privacy: .public) unit=\(unit.rawValue, privacy: .public)"
        )

        return AvgSpeedComplicationEntry(
            date: date,
            isRunning: isRunning,
            displaySpeed: displaySpeed,
            unit: unit
        )
    }
}

@main
struct AvgSpeedComplicationExtension: Widget {
    let kind = "AvgSpeedComplication"

    var body: some WidgetConfiguration {
        complicationLogger.notice("widget configuration loaded for kind=\(kind, privacy: .public)")
        return StaticConfiguration(kind: kind, provider: AvgSpeedComplicationProvider()) { entry in
            AvgSpeedComplicationView(entry: entry)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Average Speed")
        .description("Shows your latest average speed.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
        ])
    }
}

private struct AvgSpeedComplicationView: View {
    let entry: AvgSpeedComplicationEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.inlineText)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(entry.valueText)
                    .font(.headline)
                Text(entry.unit.shortLabel)
                    .font(.caption2)
            }
        case .accessoryCorner:
            Text(entry.valueText)
                .widgetCurvesContent()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Average Speed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.speedWithUnit)
                    .font(.headline)
                    .monospacedDigit()
            }
        @unknown default:
            Text(entry.inlineText)
        }
    }
}
