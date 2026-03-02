//
//  ComplicationController.swift
//  AvgSpeed Watch App
//
//  ClockKit data source that surfaces the latest average speed.
//

import ClockKit
import Foundation

@objc(ComplicationController)
final class ComplicationController: NSObject, CLKComplicationDataSource {
    private let defaultDescriptorIdentifier = CLKDefaultComplicationIdentifier
    private let legacyDescriptorIdentifier = "avgSpeed"
    private let supportedFamilies: [CLKComplicationFamily] = [
        .graphicBezel,
        .graphicRectangular,
        .graphicCircular,
        .graphicCorner,
        .utilitarianSmall,
        .utilitarianLarge,
        .circularSmall,
        .extraLarge,
        .modularSmall,
        .modularLarge
    ]

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptor = CLKComplicationDescriptor(
            identifier: defaultDescriptorIdentifier,
            displayName: "Average Speed",
            supportedFamilies: supportedFamilies
        )

        // Keep legacy identifier so older faces that reference it can still resolve.
        let legacyDescriptor = CLKComplicationDescriptor(
            identifier: legacyDescriptorIdentifier,
            displayName: "Average Speed",
            supportedFamilies: supportedFamilies
        )

        handler([descriptor, legacyDescriptor])
    }

    // Legacy API fallback. Some runtimes still query this path for picker filtering.
    func getSupportedComplicationFamilies(handler: @escaping ([CLKComplicationFamily]) -> Void) {
        handler(supportedFamilies)
    }

    func handleSharedComplicationDescriptors(_ complicationDescriptors: [CLKComplicationDescriptor]) {
        // Nothing to do here; single descriptor covers all faces.
    }

    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        let speed = ComplicationManager.shared.cachedAverageSpeed()
        let isRunning = ComplicationManager.shared.cachedIsRunning()
        guard let template = template(for: complication.family, speed: speed, isRunning: isRunning) else {
            handler(nil)
            return
        }
        handler(CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template))
    }

    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        handler(nil)
    }

    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }

    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }

    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }

    func getPlaceholderTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(template(for: complication.family, speed: 0, isRunning: true))
    }

    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        handler(template(for: complication.family, speed: 0, isRunning: true))
    }
}

private extension ComplicationController {
    func template(for family: CLKComplicationFamily, speed speedKmh: Double, isRunning: Bool) -> CLKComplicationTemplate? {
        let unit = selectedSpeedUnit()
        let displaySpeed = unit.speed(fromKmh: speedKmh)
        let text = isRunning ? speedText(displaySpeed) : "—"
        let speedWithUnitText = "\(text) \(unit.speedLabel)"

        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "Avg")
            template.line2TextProvider = CLKSimpleTextProvider(text: text)
            return template
        case .modularLarge:
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = CLKSimpleTextProvider(text: "Average Speed")
            template.body1TextProvider = CLKSimpleTextProvider(text: isRunning ? speedWithUnitText : "Stopped")
            return template
        case .utilitarianSmall:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: "Avg \(text)")
            return template
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            template.textProvider = CLKSimpleTextProvider(text: isRunning ? "Avg \(speedWithUnitText)" : "Avg stopped")
            return template
        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: text)
            return template
        case .extraLarge:
            let template = CLKComplicationTemplateExtraLargeSimpleText()
            template.textProvider = CLKSimpleTextProvider(text: text)
            return template
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
                gaugeProvider: CLKSimpleGaugeProvider(style: .ring, gaugeColor: .cyan, fillFraction: isRunning ? gaugeFill(for: displaySpeed, unit: unit) : 0),
                bottomTextProvider: CLKSimpleTextProvider(text: "Avg"),
                centerTextProvider: CLKSimpleTextProvider(text: text)
            )
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerGaugeText(
                gaugeProvider: CLKSimpleGaugeProvider(style: .ring, gaugeColor: .cyan, fillFraction: isRunning ? gaugeFill(for: displaySpeed, unit: unit) : 0),
                outerTextProvider: CLKSimpleTextProvider(text: isRunning ? text : "—")
            )
        case .graphicBezel:
            let circular = CLKComplicationTemplateGraphicCircularOpenGaugeSimpleText(
                gaugeProvider: CLKSimpleGaugeProvider(style: .ring, gaugeColor: .cyan, fillFraction: isRunning ? gaugeFill(for: displaySpeed, unit: unit) : 0),
                bottomTextProvider: CLKSimpleTextProvider(text: "Avg"),
                centerTextProvider: CLKSimpleTextProvider(text: text)
            )
            let template = CLKComplicationTemplateGraphicBezelCircularText()
            template.circularTemplate = circular
            template.textProvider = CLKSimpleTextProvider(text: isRunning ? "Avg \(speedWithUnitText)" : "Avg —")
            return template
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "Average Speed"),
                body1TextProvider: CLKSimpleTextProvider(text: isRunning ? speedWithUnitText : "Stopped")
            )
        default:
            return nil
        }
    }

    func speedText(_ speed: Double) -> String {
        String(format: "%.1f", speed)
    }

    func gaugeFill(for speed: Double, unit: ComplicationSpeedUnit) -> Float {
        let maxGaugeSpeed = (unit == .kmh) ? 40.0 : 25.0
        let normalized = min(max(speed / maxGaugeSpeed, 0), 1)
        return Float(normalized)
    }

    func selectedSpeedUnit() -> ComplicationSpeedUnit {
        let rawValue = SharedDefaults.store.string(forKey: "speed_unit") ?? ComplicationSpeedUnit.kmh.rawValue
        return ComplicationSpeedUnit(rawValue: rawValue) ?? .kmh
    }
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

    func speed(fromKmh kmh: Double) -> Double {
        switch self {
        case .kmh:
            return kmh
        case .mph:
            return kmh * 0.621_371
        }
    }
}
