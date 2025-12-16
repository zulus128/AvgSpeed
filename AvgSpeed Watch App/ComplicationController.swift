//
//  ComplicationController.swift
//  AvgSpeed Watch App
//
//  ClockKit data source that surfaces the latest average speed.
//

import ClockKit

final class ComplicationController: NSObject, CLKComplicationDataSource {
    private let supportedFamilies: [CLKComplicationFamily] = [
        .graphicRectangular,
        .graphicCircular,
        .graphicCorner,
        .utilitarianSmall,
        .utilitarianLarge,
        .circularSmall,
        .extraLarge,
        .modularSmall
    ]

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptor = CLKComplicationDescriptor(
            identifier: "avgSpeed",
            displayName: "Average Speed",
            supportedFamilies: supportedFamilies
        )
        handler([descriptor])
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
}

private extension ComplicationController {
    func template(for family: CLKComplicationFamily, speed: Double, isRunning: Bool) -> CLKComplicationTemplate? {
        let text = isRunning ? speedText(speed) : "—"
        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "Avg")
            template.line2TextProvider = CLKSimpleTextProvider(text: text)
            return template
        case .utilitarianSmall:
            let template = CLKComplicationTemplateUtilitarianSmallFlat()
            template.textProvider = CLKSimpleTextProvider(text: "Avg \(text)")
            return template
        case .utilitarianLarge:
            let template = CLKComplicationTemplateUtilitarianLargeFlat()
            template.textProvider = CLKSimpleTextProvider(text: isRunning ? "Avg \(text) km/h" : "Avg stopped")
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
                gaugeProvider: CLKSimpleGaugeProvider(style: .ring, gaugeColor: .cyan, fillFraction: isRunning ? gaugeFill(for: speed) : 0),
                bottomTextProvider: CLKSimpleTextProvider(text: "Avg"),
                centerTextProvider: CLKSimpleTextProvider(text: text)
            )
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerGaugeText(
                gaugeProvider: CLKSimpleGaugeProvider(style: .ring, gaugeColor: .cyan, fillFraction: isRunning ? gaugeFill(for: speed) : 0),
                outerTextProvider: CLKSimpleTextProvider(text: isRunning ? "Avg \(text)" : "Avg —")
            )
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "Average Speed"),
                body1TextProvider: CLKSimpleTextProvider(text: isRunning ? "\(text) km/h" : "Stopped")
            )
        default:
            return nil
        }
    }

    func speedText(_ speed: Double) -> String {
        String(format: "%.1f", speed)
    }

    func gaugeFill(for speed: Double) -> Float {
        let normalized = min(max(speed / 40, 0), 1) // assume 0-40 km/h typical range
        return Float(normalized)
    }
}
