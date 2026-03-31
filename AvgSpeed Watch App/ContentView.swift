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
    @StateObject private var diagnostics = TrackerDiagnostics.shared
    @StateObject private var historyStore = SessionHistoryStore.shared
    @StateObject private var proStore = ProPurchaseStore.shared

    @AppStorage("speed_limit_kmh", store: SharedDefaults.store) private var speedLimitKmh: Double = 10
    @AppStorage("speed_unit", store: SharedDefaults.store) private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage(SharedDefaults.proUnlockedKey, store: SharedDefaults.store) private var proUnlocked = false
    @AppStorage(SharedDefaults.distanceStallHapticsEnabledKey, store: SharedDefaults.store) private var distanceStallHapticsEnabled = false
    @AppStorage(SharedDefaults.gpsSignalHapticsEnabledKey, store: SharedDefaults.store) private var gpsSignalHapticsEnabled = false
    @AppStorage(SharedDefaults.appThemeKey, store: SharedDefaults.store) private var appThemeRaw: String = AppTheme.ocean.rawValue

    @State private var wasOverLimit = false
    @State private var crownLimit: Double = 10
    @State private var showsVersionInfo = false
    @State private var showsDiagnostics = false
    @State private var showsProSheet = false
    @State private var showsHistory = false
    @State private var unitLongPressTriggered = false
    @State private var lastDistanceStallAlertToken: UInt = 0
    @State private var gpsIssueWasActive = false
    @State private var hasSeenGpsIssueDuringTracking = false
    @FocusState private var isLimitCrownFocused: Bool

    private let buttonHitTarget: CGFloat = 48

    private var speedUnit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .kmh }
    private var appTheme: AppTheme { AppTheme.resolved(rawValue: appThemeRaw, hasPro: proUnlocked) }
    private var advancedGpsHapticsEnabled: Bool { proUnlocked && gpsSignalHapticsEnabled }

    private var limit: Double { max(speedUnit.speed(fromKmh: speedLimitKmh), 1) }
    private var averageSpeed: Double { max(speedUnit.speed(fromKmh: tracker.averageSpeedKmh), 0) }
    private var currentSpeed: Double { max(speedUnit.speed(fromKmh: tracker.currentSpeedKmh), 0) }
    private var maxSpeed: Double { max(speedUnit.speed(fromKmh: tracker.maxSpeedKmh), 0) }
    // private var gpsSpeed: Double { max(speedUnit.speed(fromKmh: tracker.gpsSpeedKmh), 0) }
    private var distance: Double { max(speedUnit.distance(fromKm: tracker.distanceKm), 0) }
    private var currentSpeedText: String { String(format: "%.1f %@", currentSpeed, speedUnit.speedLabel) }
    private var distanceText: String { String(format: "%.2f %@", distance, speedUnit.distanceLabel) }
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let marketingVersion = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let buildVersion = (info?["CFBundleVersion"] as? String) ?? "?"
        return "v\(marketingVersion) (\(buildVersion))"
    }
    private var diagnosticsButtonText: String { "Logs \(diagnostics.entries.count)" }

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

    private struct LayoutMetrics {
        let size: CGSize
        let safeAreaInsets: EdgeInsets
        let hasProMetrics: Bool

        private let referenceSize = CGSize(width: 184, height: 224)
        private let baseGaugeSize: CGFloat = 132
        private let maxGaugeWidthFraction: CGFloat = 0.64

        var screenSize: CGSize {
            CGSize(
                width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
                height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
            )
        }

        var screenScale: CGFloat {
            let widthScale = screenSize.width / referenceSize.width
            let heightScale = screenSize.height / referenceSize.height
            return min(widthScale, heightScale)
        }

        var scale: CGFloat {
            let exponent: Double = 2.25
            let curved = CGFloat(pow(Double(screenScale), exponent))
            return curved.clamped(to: 0.75...1.0)
        }

        var gaugeScale: CGFloat {
            let widthLimited = (size.width * maxGaugeWidthFraction / baseGaugeSize).clamped(to: 0.5...1.0)
            return min(scale, widthLimited)
        }

        var headerHeight: CGFloat { 28 * scale }
        var gaugeSize: CGFloat { baseGaugeSize * gaugeScale * (hasProMetrics ? 0.90 : 1.0) }
        var gaugeTopPadding: CGFloat { (hasProMetrics ? 8 : 13) * gaugeScale }
        var gaugeBottomPadding: CGFloat { (hasProMetrics ? 4 : 10) * gaugeScale }
        var startStopButtonOffsetY: CGFloat { 18 * gaugeScale }
        var unitToggleButtonOffsetY: CGFloat { 19 * gaugeScale }

        var topRowAlignmentOffset: CGFloat {
            -(safeAreaInsets.top * 0.5)
        }
    }

    private func headerBar(height: CGFloat) -> some View {
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

                proHeaderButton
                    .frame(width: timeReservedWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
    }

#if DEBUG
    private func debugPrintLayout(_ metrics: LayoutMetrics, event: String) {
        func f(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
        func sizeString(_ size: CGSize) -> String { "\(f(size.width))×\(f(size.height))" }

        func insetsString(_ insets: EdgeInsets) -> String {
            "t:\(f(insets.top)) l:\(f(insets.leading)) b:\(f(insets.bottom)) r:\(f(insets.trailing))"
        }

        let gaugeSize = metrics.gaugeSize
        let strokeWidth = gaugeSize * 10 / 132
        let needleWidth = gaugeSize * 3 / 132
        let needleHeight = gaugeSize * 56 / 132
        let hubSize = gaugeSize * 14 / 132
        let speedFontSize = gaugeSize * 42 / 132

        print(
            """
            [Layout:\(event)]
              safeAreaSize: \(sizeString(metrics.size))
              screenSize: \(sizeString(metrics.screenSize))
              safeArea: \(insetsString(metrics.safeAreaInsets))
              screenScale: \(f(metrics.screenScale))
              scale: \(f(metrics.scale))
              gaugeScale: \(f(metrics.gaugeScale))
              headerHeight: \(f(metrics.headerHeight))
              gaugeSize: \(f(gaugeSize)) (radius=\(f(gaugeSize / 2)))
              gaugeStrokeWidth: \(f(strokeWidth))
              gaugeNeedle: w=\(f(needleWidth)) h=\(f(needleHeight))
              gaugeHubSize: \(f(hubSize))
              gaugeSpeedFont: \(f(speedFontSize))
              gaugePaddings: top=\(f(metrics.gaugeTopPadding)) bottom=\(f(metrics.gaugeBottomPadding))
              buttonOffsets: startStop=\(f(metrics.startStopButtonOffsetY)) unitToggle=\(f(metrics.unitToggleButtonOffsetY))
              topRowOffset: \(f(metrics.topRowAlignmentOffset))
            """
        )
    }
#endif

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets, hasProMetrics: proUnlocked)

            ZStack {
                LinearGradient(
                    colors: appTheme.backgroundColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    headerBar(height: metrics.headerHeight)

                    ZStack {
                        SpeedGauge(
                            limitFraction: limitFraction,
                            needleFraction: needleFraction,
                            speed: averageSpeed,
                            isTracking: tracker.isTracking,
                            isGpsFresh: tracker.isGpsFresh,
                            isGpsWeak: tracker.isGpsWeak,
                            unitLabel: speedUnit.speedLabel,
                            theme: appTheme,
                            size: metrics.gaugeSize
                        )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .overlay(alignment: .bottomLeading) {
                                startStopButton
                                    .padding(.leading, 6)
                                    .offset(y: metrics.startStopButtonOffsetY)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                unitToggleButton
                                    .padding(.trailing, 2)
                                    .offset(y: metrics.unitToggleButtonOffsetY)
                            }
                    }
                    .frame(height: metrics.gaugeSize)
                    .padding(.top, metrics.gaugeTopPadding)
                    .padding(.bottom, metrics.gaugeBottomPadding)

                    VStack(spacing: 2) {
                        summaryMetricsRow

                        /*
                        Text("GPS \(gpsSpeed, format: .number.precision(.fractionLength(1))) \(speedUnit.speedLabel)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: gpsSpeed)
                        */

                        if proUnlocked {
                            proMetricsRow
                                .padding(.top, 1)
                        }
                    }
                    .padding(.bottom, 0)
#if DEBUG
                    .onLongPressGesture(minimumDuration: 0.8) {
                        tracker.toggleDemoSimulation()
                        WKInterfaceDevice.current().play(.click)
                    }
#endif

                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: metrics.topRowAlignmentOffset)
                .overlay(alignment: .top) {
                    if showsVersionInfo {
                        versionInfoOverlay(topPadding: metrics.headerHeight + 2)
                    }
                }
            }
#if DEBUG
            .onAppear {
                debugPrintLayout(metrics, event: "onAppear")
            }
            .onChange(of: proxy.size) { _, _ in
                debugPrintLayout(LayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets, hasProMetrics: proUnlocked), event: "sizeChanged")
            }
#endif
        }
        .onAppear {
            tracker.prepare()
            normalizeProState()
            wasOverLimit = false
            lastDistanceStallAlertToken = tracker.distanceStallAlertToken
            syncCrownLimit()
            isLimitCrownFocused = true
            evaluateGpsSignalHaptics()
        }
        .task {
            await proStore.prepare()
        }
        .onReceive(tracker.$averageSpeedKmh) { _ in
            evaluateLimitHaptics()
        }
        .onReceive(tracker.$distanceStallAlertToken) { token in
            playDistanceStallHapticIfNeeded(for: token)
        }
        .onReceive(tracker.$isGpsFresh) { _ in
            evaluateGpsSignalHaptics()
        }
        .onReceive(tracker.$isGpsWeak) { _ in
            evaluateGpsSignalHaptics()
        }
        .onReceive(tracker.$distanceKm) { _ in
            evaluateGpsSignalHaptics()
        }
        .onChange(of: speedLimitKmh) { _, _ in
            evaluateLimitHaptics()
        }
        .onChange(of: speedUnitRaw) { _, _ in
            evaluateLimitHaptics()
            syncCrownLimit()
            isLimitCrownFocused = true
            ComplicationManager.shared.pushState(
                averageSpeedKmh: tracker.averageSpeedKmh,
                isRunning: tracker.isTracking,
                forceReload: true
            )
        }
        .onChange(of: proUnlocked) { _, _ in
            normalizeProState()
            evaluateGpsSignalHaptics()
            ComplicationManager.shared.pushState(
                averageSpeedKmh: tracker.averageSpeedKmh,
                isRunning: tracker.isTracking,
                forceReload: true
            )
        }
        .onChange(of: appThemeRaw) { _, _ in
            normalizeProState()
            ComplicationManager.shared.pushState(
                averageSpeedKmh: tracker.averageSpeedKmh,
                isRunning: tracker.isTracking,
                forceReload: true
            )
        }
        .onChange(of: tracker.isTracking) { _, _ in
            evaluateGpsSignalHaptics()
        }
        .onChange(of: crownLimit) { _, newValue in
            let kmh = speedUnit.kmh(fromSpeed: newValue).clamped(to: 1...400)
            if abs(kmh - speedLimitKmh) >= 0.001 {
                speedLimitKmh = kmh
            }
        }
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticsLogView(diagnostics: diagnostics)
        }
        .sheet(isPresented: $showsProSheet) {
            ProFeaturesView(
                proStore: proStore,
                proUnlocked: $proUnlocked,
                distanceStallHapticsEnabled: $distanceStallHapticsEnabled,
                gpsSignalHapticsEnabled: $gpsSignalHapticsEnabled,
                selectedThemeRaw: $appThemeRaw
            )
        }
        .sheet(isPresented: $showsHistory) {
            SessionHistoryView(historyStore: historyStore, speedUnit: speedUnit, theme: appTheme)
        }
    }

    private func toggleUnit() {
        if unitLongPressTriggered {
            unitLongPressTriggered = false
            return
        }
        speedUnitRaw = (speedUnit == .kmh) ? SpeedUnit.mph.rawValue : SpeedUnit.kmh.rawValue
    }

    private func toggleTracking() {
        tracker.toggleTracking()
        isLimitCrownFocused = true
    }

    private func openDiagnostics() {
        showsVersionInfo = false
        showsDiagnostics = true
    }

    private var summaryMetricsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer(minLength: 0)

            Text(currentSpeedText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: currentSpeed)

            Spacer(minLength: 0)

            Text(distanceText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func versionInfoOverlay(topPadding: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(appVersionText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.3))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .accessibilityLabel("App version \(appVersionText)")

            HStack(spacing: 6) {
                overlayActionButton(title: proUnlocked ? "Pro" : "Unlock", accent: appTheme.accentColor, action: openProSheet)
                overlayActionButton(title: "History", accent: appTheme.secondaryAccentColor, action: openHistory)
            }

            diagnosticsButton
        }
        .padding(.top, topPadding)
        .transition(.opacity)
    }

    private var diagnosticsButton: some View {
        Button(action: openDiagnostics) {
            Text(diagnosticsButtonText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(appTheme.panelFill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(appTheme.borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens saved diagnostics from standalone runs")
    }

    private var proHeaderButton: some View {
        Button(action: openProSheet) {
            HStack(spacing: 3) {
                if !proUnlocked {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                }

                Text("PRO")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background {
                if proUnlocked {
                    appTheme.accentColor.opacity(0.96)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.36),
                            Color(red: 1.0, green: 0.65, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(proUnlocked ? "Pro settings" : "Unlock Pro")
        .accessibilityHint("Opens AvgSpeed Pro")
    }

    private func openProSheet() {
        showsVersionInfo = false
        showsProSheet = true
    }

    private func openHistory() {
        showsVersionInfo = false
        if proUnlocked {
            showsHistory = true
        } else {
            showsProSheet = true
        }
    }

    private func normalizeProState() {
        let normalizedTheme = AppTheme.resolved(rawValue: appThemeRaw, hasPro: proUnlocked)
        if normalizedTheme.rawValue != appThemeRaw {
            appThemeRaw = normalizedTheme.rawValue
        }

        if !proUnlocked {
            distanceStallHapticsEnabled = false
            gpsSignalHapticsEnabled = false
        }
    }

    private var unitToggleButton: some View {
        Button(action: toggleUnit) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .frame(width: buttonHitTarget, height: buttonHitTarget)
                Text(speedUnit.shortLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 32, height: 32)
                    .background(appTheme.panelFill)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(appTheme.borderColor, lineWidth: 1))
                    .contentShape(Circle())
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1, maximumDistance: 24)
                    .onEnded { _ in
                        unitLongPressTriggered = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsVersionInfo.toggle()
                        }
                        WKInterfaceDevice.current().play(.click)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Units")
        .accessibilityValue(speedUnit.speedLabel)
        .accessibilityHint("Tap to change units. Long press to show app version")
    }

    private var startStopButton: some View {
        Button(action: toggleTracking) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(width: buttonHitTarget, height: buttonHitTarget)
                Image(systemName: tracker.isTracking ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tracker.isTracking ? .red : .green)
                    .frame(width: 28, height: 28)
                    .background(appTheme.panelFill)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(appTheme.borderColor, lineWidth: 1))
                    .contentShape(Circle())
            }
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
        .background(isLimitCrownFocused ? appTheme.panelStrongFill : appTheme.panelFill)
        .overlay(Capsule().stroke(isLimitCrownFocused ? appTheme.borderColor.opacity(1.0) : appTheme.borderColor, lineWidth: 1))
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

    private func playDistanceStallHapticIfNeeded(for token: UInt) {
        guard token != lastDistanceStallAlertToken else { return }
        lastDistanceStallAlertToken = token
        guard proUnlocked && distanceStallHapticsEnabled else { return }
        WKInterfaceDevice.current().play(.retry)
    }

    private func evaluateGpsSignalHaptics() {
        guard advancedGpsHapticsEnabled else {
            gpsIssueWasActive = false
            hasSeenGpsIssueDuringTracking = false
            return
        }

        guard tracker.isTracking else {
            gpsIssueWasActive = false
            hasSeenGpsIssueDuringTracking = false
            return
        }

        let issueActive = !tracker.isGpsFresh || tracker.isGpsWeak

        guard tracker.distanceKm > 0.05 else {
            gpsIssueWasActive = issueActive
            hasSeenGpsIssueDuringTracking = false
            return
        }

        if issueActive && !gpsIssueWasActive {
            WKInterfaceDevice.current().play(.failure)
            hasSeenGpsIssueDuringTracking = true
        } else if !issueActive && gpsIssueWasActive && hasSeenGpsIssueDuringTracking {
            WKInterfaceDevice.current().play(.success)
        }

        gpsIssueWasActive = issueActive
    }

    private var proMetricsRow: some View {
        HStack(spacing: 4) {
            liveMetricCapsule(title: "MAX", value: String(format: "%.1f", maxSpeed))
            liveMetricCapsule(title: "MOVE", value: formatMetricDuration(tracker.movingTime))
            liveMetricCapsule(title: "STOP", value: formatMetricDuration(tracker.stoppedTime))
        }
    }

    private func liveMetricCapsule(title: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(appTheme.secondaryAccentColor.opacity(0.88))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2.5)
        .padding(.horizontal, 3)
        .background(appTheme.panelFill)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(appTheme.borderColor, lineWidth: 1))
    }

    private func overlayActionButton(title: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accent.opacity(0.95))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func formatMetricDuration(_ duration: TimeInterval) -> String {
        Self.metricDurationFormatter.string(from: duration) ?? "0:00"
    }

    private func roundUp(_ value: Double, step: Double) -> Double {
        (value / step).rounded(.up) * step
    }

    private static let metricDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

private struct DiagnosticsLogView: View {
    @ObservedObject var diagnostics: TrackerDiagnostics

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("Diagnostics")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                    Text("\(diagnostics.entries.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 4)

                    Button("Clear") {
                        diagnostics.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(diagnostics.entries.indices.reversed()), id: \.self) { index in
                            Text(diagnostics.entries[index])
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 0)
        }
    }
}

enum SpeedUnit: String {
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
    let isTracking: Bool
    let isGpsFresh: Bool
    let isGpsWeak: Bool
    let unitLabel: String
    let theme: AppTheme
    let size: CGFloat

    @State private var blink = false

    private var dynamicGradient: AngularGradient {
        let clampedLimit = limitFraction.clamped(to: 0...1)
        let epsilon = min(0.02, clampedLimit, 1 - clampedLimit)
        let left = (clampedLimit - epsilon).clamped(to: 0...1)
        let right = (clampedLimit + epsilon).clamped(to: 0...1)

        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: theme.gaugeSafeColor.opacity(0.85), location: 0.0),
                .init(color: theme.gaugeSafeColor.opacity(0.85), location: left),
                .init(color: theme.gaugeAlertColor.opacity(0.88), location: right),
                .init(color: theme.gaugeAlertColor.opacity(0.88), location: 1.0),
            ]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    private var gpsIndicatorColor: Color {
        if !isGpsFresh {
            return theme.gaugeAlertColor
        }
        return isGpsWeak ? theme.secondaryAccentColor : theme.gaugeSafeColor
    }

    var body: some View {
        let strokeWidth = size * 10 / 132
        let needleWidth = size * 3 / 132
        let needleHeight = size * 56 / 132
        let hubSize = size * 14 / 132
        let speedFontSize = size * 42 / 132
        let fractionalFontSize = speedFontSize * 0.42
        let fractionalBaselineOffset = speedFontSize * 0.22
        let speedParts = formattedSpeedParts(speed)

        ZStack {
            Circle()
                .stroke(theme.borderColor.opacity(0.55), lineWidth: strokeWidth)

            Circle()
                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .foregroundStyle(dynamicGradient)
                .opacity(0.9)

            Capsule()
                .fill(theme.accentColor.opacity(0.92))
                .frame(width: needleWidth, height: needleHeight)
                .offset(y: -(needleHeight / 2))
                .rotationEffect(.degrees(needleFraction.clamped(to: 0...1) * 360))
                .shadow(color: theme.accentColor.opacity(0.30), radius: 1)
                .animation(.easeInOut(duration: 0.2), value: needleFraction)

            Circle()
                .fill(.black.opacity(0.85))
                .frame(width: hubSize, height: hubSize)
                .overlay(Circle().stroke(theme.borderColor, lineWidth: 1))

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(speedParts.integer)
                        .font(.system(size: speedFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(speedParts.separator)\(speedParts.fraction)")
                        .font(.system(size: fractionalFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .baselineOffset(fractionalBaselineOffset)
                }
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: speed)

                HStack(alignment: .center, spacing: 4) {
                    Text(unitLabel)
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryAccentColor.opacity(0.9))

                    Circle()
                        .fill(gpsIndicatorColor)
                        .frame(width: max(3, speedFontSize * 0.10), height: max(3, speedFontSize * 0.10))
                        .opacity(isTracking ? (blink ? 0.95 : 0.25) : 0)
                        .scaleEffect(isTracking ? (blink ? 1.0 : 0.75) : 0.75)
                        .shadow(color: gpsIndicatorColor.opacity(isTracking ? 0.5 : 0), radius: 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            updateBlinking()
        }
        .onChange(of: isTracking) { _, _ in
            updateBlinking()
        }
    }

    private func formattedSpeedParts(_ speed: Double) -> (integer: String, separator: String, fraction: String) {
        let formatted = speed.formatted(.number.precision(.fractionLength(2)))
        let separator = Locale.current.decimalSeparator ?? "."
        guard let range = formatted.range(of: separator) else {
            return (formatted, separator, "00")
        }
        let integer = String(formatted[..<range.lowerBound])
        let fraction = String(formatted[range.upperBound...])
        return (integer, separator, fraction)
    }

    private func updateBlinking() {
        guard isTracking else {
            blink = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            blink = true
        }
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
