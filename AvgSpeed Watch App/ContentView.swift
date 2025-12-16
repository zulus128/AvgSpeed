//
//  ContentView.swift
//  AvgSpeed Watch App
//
//  Created by VADIM KASSIN on 15.12.2025.
//

import SwiftUI
import WatchKit

struct ContentView: View {
    @EnvironmentObject private var tracker: SpeedTracker

    @AppStorage("speed_limit_kmh") private var speedLimitKmh: Double = 10
    @AppStorage("speed_unit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue

    @State private var wasOverLimit = false
    @State private var crownLimit: Double = 10
    @FocusState private var isLimitCrownFocused: Bool

    private var speedUnit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .kmh }

    private var limit: Double { max(speedUnit.speed(fromKmh: speedLimitKmh), 1) }
    private var averageSpeed: Double { max(speedUnit.speed(fromKmh: tracker.averageSpeedKmh), 0) }
    private var distance: Double { max(speedUnit.distance(fromKm: tracker.distanceKm), 0) }

    private var crownLimitRange: ClosedRange<Double> {
        1...max(speedUnit.speed(fromKmh: 400), 1)
    }

    private var maxGaugeSpeed: Double {
        let baseline: Double = (speedUnit == .kmh) ? 40 : 25
        let desired = max(limit, averageSpeed) * 1.2
        let step: Double = (speedUnit == .kmh) ? 10 : 5
        return max(roundUp(max(desired, baseline), step: step), 1)
    }

    private var needleFraction: Double { min(max(averageSpeed / maxGaugeSpeed, 0), 1) }
    private var limitFraction: Double { min(max(limit / maxGaugeSpeed, 0), 1) }

    private var verticalSpacingCoefficient: CGFloat {
        let referenceHeight: CGFloat = 224
        let screenHeight = WKInterfaceDevice.current().screenBounds.size.height
        let scale = screenHeight / referenceHeight
        return scale//.clamped(to: 0.75...1.15)
    }

    private func vSpace(_ value: CGFloat) -> CGFloat {
        value * verticalSpacingCoefficient
    }

    private var headerBar: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 0
            let limitWidth: CGFloat = 68
            let timeReservedWidth = min(max(proxy.size.width * 0.30, 44), 60)
            let unitAreaWidth = max(0, proxy.size.width - limitWidth - timeReservedWidth - spacing * 2)

            HStack(alignment: .center, spacing: spacing) {
                limitCrownControl
                    .frame(width: limitWidth, alignment: .leading)

                Color.clear
                    .frame(width: unitAreaWidth, height: 1)
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: timeReservedWidth, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 28)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                headerBar

                ZStack {
                    SpeedGauge(
                        limitFraction: limitFraction,
                        needleFraction: needleFraction,
                        speed: averageSpeed,
                        unitLabel: speedUnit.speedLabel
                    )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .overlay(alignment: .bottomLeading) {
                            startStopButton
                                .padding(.leading, 6)
                                .offset(y: vSpace(18))
                        }
                        .overlay(alignment: .bottomTrailing) {
                            unitToggleButton
                                .padding(.trailing, 2)
                                .offset(y: vSpace(19))
                        }
                }
                .frame(height: 132)
                .padding(.top, vSpace(13))
                .padding(.bottom, vSpace(10))

                Text(String(format: "%.2f %@", distance, speedUnit.distanceLabel))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                    .padding(.bottom, 0)

                if let status = tracker.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 6)
            .offset(y: -vSpace(10))
        }
        .onAppear {
            tracker.prepare()
            wasOverLimit = false
            syncCrownLimit()
            isLimitCrownFocused = true
        }
        .onReceive(tracker.$averageSpeedKmh) { _ in
            evaluateLimitHaptics()
        }
        .onChange(of: speedLimitKmh) { _, _ in
            evaluateLimitHaptics()
        }
        .onChange(of: speedUnitRaw) { _, _ in
            evaluateLimitHaptics()
            syncCrownLimit()
            isLimitCrownFocused = true
        }
        .onChange(of: crownLimit) { _, newValue in
            let kmh = speedUnit.kmh(fromSpeed: newValue).clamped(to: 1...400)
            if abs(kmh - speedLimitKmh) >= 0.001 {
                speedLimitKmh = kmh
            }
        }
    }

    private func toggleUnit() {
        speedUnitRaw = (speedUnit == .kmh) ? SpeedUnit.mph.rawValue : SpeedUnit.kmh.rawValue
    }

    private func toggleTracking() {
        tracker.toggleTracking()
        isLimitCrownFocused = true
    }

    private var unitToggleButton: some View {
        Button(action: toggleUnit) {
            Text(speedUnit.shortLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.14))
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Units")
        .accessibilityValue(speedUnit.speedLabel)
        .accessibilityHint("Tap to change units")
    }

    private var startStopButton: some View {
        Button(action: toggleTracking) {
            Image(systemName: tracker.isTracking ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tracker.isTracking ? .red : .green)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14))
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(tracker.isStarting)
        .opacity(tracker.isStarting ? 0.55 : 1)
        .accessibilityLabel(tracker.isTracking ? "Stop" : "Start")
    }

    private var limitCrownControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)

            Text(crownLimit.rounded(), format: .number.precision(.fractionLength(0)))
                .font(.headline)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(isLimitCrownFocused ? .white.opacity(0.22) : .white.opacity(0.14))
        .overlay(Capsule().stroke(isLimitCrownFocused ? .white.opacity(0.28) : .white.opacity(0.14), lineWidth: 1))
        .contentShape(Capsule())
        .focusable(true)
        .focused($isLimitCrownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            $crownLimit,
            from: crownLimitRange.lowerBound,
            through: crownLimitRange.upperBound,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onTapGesture {
            isLimitCrownFocused = true
        }
        .clipShape(Capsule())
        .accessibilityLabel("Speed limit")
        .accessibilityValue("\(Int(crownLimit.rounded()))")
    }

    private func syncCrownLimit() {
        crownLimit = limit.clamped(to: crownLimitRange)
    }

    private func evaluateLimitHaptics() {
        guard tracker.isTracking else {
            wasOverLimit = false
            return
        }

        let over = averageSpeed > limit
        if over && !wasOverLimit {
            WKInterfaceDevice.current().play(.notification)
        }
        wasOverLimit = over
    }

    private func roundUp(_ value: Double, step: Double) -> Double {
        (value / step).rounded(.up) * step
    }
}

private enum SpeedUnit: String {
    case kmh
    case mph

    var speedLabel: String {
        switch self {
        case .kmh: return "km/h"
        case .mph: return "mi/h"
        }
    }

    var distanceLabel: String {
        switch self {
        case .kmh: return "km"
        case .mph: return "mi"
        }
    }

    var shortLabel: String {
        switch self {
        case .kmh: return "km"
        case .mph: return "mi"
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

    func distance(fromKm km: Double) -> Double {
        switch self {
        case .kmh:
            return km
        case .mph:
            return km * 0.621_371
        }
    }

    func kmh(fromSpeed speed: Double) -> Double {
        switch self {
        case .kmh:
            return speed
        case .mph:
            return speed / 0.621_371
        }
    }
}

private struct SpeedGauge: View {
    let limitFraction: Double
    let needleFraction: Double
    let speed: Double
    let unitLabel: String

    private var dynamicGradient: AngularGradient {
        let clampedLimit = limitFraction.clamped(to: 0...1)
        let epsilon = min(0.02, clampedLimit, 1 - clampedLimit)
        let left = (clampedLimit - epsilon).clamped(to: 0...1)
        let right = (clampedLimit + epsilon).clamped(to: 0...1)

        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .green.opacity(0.75), location: 0.0),
                .init(color: .green.opacity(0.75), location: left),
                .init(color: .red.opacity(0.75), location: right),
                .init(color: .red.opacity(0.75), location: 1.0),
            ]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)

            Circle()
                .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .foregroundStyle(dynamicGradient)
                .opacity(0.9)

            Capsule()
                .fill(.white.opacity(0.65))
                .frame(width: 3, height: 56)
                .offset(y: -28)
                .rotationEffect(.degrees(needleFraction.clamped(to: 0...1) * 360))
                .shadow(color: .white.opacity(0.25), radius: 1)
                .animation(.easeInOut(duration: 0.2), value: needleFraction)

            Circle()
                .fill(.black.opacity(0.85))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))

            VStack(spacing: 0) {
                Text(speed, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: speed)

                Text(unitLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 132, height: 132)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SpeedTracker.previewModel)
    }
}
#endif
