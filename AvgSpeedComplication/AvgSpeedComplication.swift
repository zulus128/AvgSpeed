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
    static let themeKey = "app_theme"
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

private enum ComplicationTheme: String {
    case ocean
    case ember
    case volt

    var accentColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.43, green: 0.86, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.72, blue: 0.34)
        case .volt:
            return Color(red: 0.72, green: 1.0, blue: 0.44)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.61, green: 0.83, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.56, blue: 0.48)
        case .volt:
            return Color(red: 0.58, green: 1.0, blue: 0.82)
        }
    }
}

private struct AvgSpeedComplicationEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let displaySpeed: Double
    let unit: ComplicationSpeedUnit
    let theme: ComplicationTheme

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
            unit: .kmh,
            theme: .ocean
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
        let themeRaw = defaults.string(forKey: SharedComplicationDefaults.themeKey) ?? ComplicationTheme.ocean.rawValue
        let theme = ComplicationTheme(rawValue: themeRaw) ?? .ocean
        let displaySpeed = unit.speed(fromKmh: averageSpeedKmh)
        complicationLogger.notice(
            "loadEntry avgKmh=\(averageSpeedKmh, format: .fixed(precision: 1)) running=\(isRunning, privacy: .public) unit=\(unit.rawValue, privacy: .public) theme=\(theme.rawValue, privacy: .public)"
        )

        return AvgSpeedComplicationEntry(
            date: date,
            isRunning: isRunning,
            displaySpeed: displaySpeed,
            unit: unit,
            theme: theme
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
                .foregroundStyle(entry.theme.accentColor)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(entry.valueText)
                    .font(.headline)
                    .foregroundStyle(entry.theme.accentColor)
                Text(entry.unit.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(entry.theme.secondaryColor)
            }
        case .accessoryCorner:
            Text(entry.valueText)
                .widgetCurvesContent()
                .foregroundStyle(entry.theme.accentColor)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Average Speed")
                    .font(.caption2)
                    .foregroundStyle(entry.theme.secondaryColor)
                Text(entry.speedWithUnit)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(entry.theme.accentColor)
            }
        @unknown default:
            Text(entry.inlineText)
                .foregroundStyle(entry.theme.accentColor)
        }
    }
}
