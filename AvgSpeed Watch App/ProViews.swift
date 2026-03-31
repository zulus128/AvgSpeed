//
//  ProViews.swift
//  AvgSpeed Watch App
//
//  Pro settings and session history UI.
//

import SwiftUI

struct ProFeaturesView: View {
    @ObservedObject var proStore: ProPurchaseStore
    @Binding var proUnlocked: Bool
    @Binding var distanceStallHapticsEnabled: Bool
    @Binding var gpsSignalHapticsEnabled: Bool
    @Binding var selectedThemeRaw: String

    private var availableThemes: [AppTheme] {
        AppTheme.allCases.filter { proUnlocked || !$0.isProExclusive }
    }

    private var selectedTheme: AppTheme {
        AppTheme.resolved(rawValue: selectedThemeRaw, hasPro: proUnlocked)
    }

    private var statusTitle: String {
        proUnlocked ? "AvgSpeed Pro active" : "Unlock AvgSpeed Pro"
    }

    private var statusMessage: String {
        proUnlocked
            ? "History, themes and advanced alerts are enabled."
            : "One-time unlock for session history, premium themes and advanced alerts."
    }

    private var purchaseTitle: String {
        if proUnlocked {
            return "Pro Unlocked"
        }

        if proStore.isPurchasing {
            return "Purchasing..."
        }

        if let price = proStore.displayPrice {
            return "Unlock for \(price)"
        }

        if proStore.isLoadingProduct {
            return "Loading Price..."
        }

        return "Unlock AvgSpeed Pro"
    }

    private var purchaseSubtitle: String {
        if proUnlocked {
            return "Premium features are ready to use"
        }

        if proStore.isPurchasing {
            return "Confirm the purchase with the App Store"
        }

        return "One-time App Store purchase"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    statusCard
                    featuresCard
                    controlsCard
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("AvgSpeed Pro")
        }
        .task {
            await proStore.prepare()
        }
        .onReceive(proStore.$isProUnlocked) { newValue in
            if proUnlocked != newValue {
                proUnlocked = newValue
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: proUnlocked ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(proUnlocked ? Color(red: 0.44, green: 0.95, blue: 0.66) : Color(red: 1.0, green: 0.83, blue: 0.34))

                Text(proUnlocked ? "Unlocked" : "Premium upgrade")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
            }

            Text(statusTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(statusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))

            purchaseButton

            restoreButton

            if let message = proStore.message {
                Text(message)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(proStore.messageIsError ? Color(red: 1.0, green: 0.63, blue: 0.63) : .white.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var purchaseButton: some View {
        Button {
            guard !proUnlocked else { return }
            Task {
                await proStore.purchase()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: proUnlocked ? "checkmark.circle.fill" : "cart.fill.badge.plus")
                    .font(.system(size: 13, weight: .bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(purchaseTitle)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))

                    Text(purchaseSubtitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .opacity(0.74)
                }

                Spacer(minLength: 8)

                Image(systemName: proUnlocked ? "checkmark" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.74)
            }
            .foregroundStyle(.black.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: proUnlocked
                        ? [Color(red: 0.48, green: 1.0, blue: 0.72), Color(red: 0.29, green: 0.86, blue: 0.56)]
                        : [Color(red: 1.0, green: 0.84, blue: 0.36), Color(red: 1.0, green: 0.62, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: proUnlocked ? Color.green.opacity(0.22) : Color.orange.opacity(0.24), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(proUnlocked || proStore.isPurchasing || proStore.isRestoring)
        .opacity((proUnlocked || proStore.isPurchasing || proStore.isRestoring) ? 0.9 : 1)
    }

    private var restoreButton: some View {
        Button {
            Task {
                await proStore.restorePurchases()
            }
        } label: {
            HStack(spacing: 6) {
                if proStore.isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                }

                Text(proStore.isRestoring ? "Restoring..." : "Restore Purchases")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(proStore.isPurchasing || proStore.isRestoring)
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Includes")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            featureRow("History of sessions")
            featureRow("Max speed, moving and stopped time")
            featureRow("Distance stall and GPS haptic alerts")
            featureRow("Additional watch and complication themes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Toggle("Distance stall haptic", isOn: $distanceStallHapticsEnabled)
                .disabled(!proUnlocked)

            Toggle("GPS alert haptics", isOn: $gpsSignalHapticsEnabled)
                .disabled(!proUnlocked)

            VStack(alignment: .leading, spacing: 6) {
                Text("Theme")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))

                ForEach(availableThemes) { theme in
                    themeOptionButton(theme)
                }

                if !proUnlocked {
                    Text("Unlock Pro for Ember and Volt.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func featureRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green.opacity(0.9))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func themeOptionButton(_ theme: AppTheme) -> some View {
        let isSelected = selectedTheme == theme

        return Button {
            selectedThemeRaw = AppTheme.resolved(rawValue: theme.rawValue, hasPro: proUnlocked).rawValue
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .black.opacity(0.88) : .white.opacity(0.94))

                    Text(theme.isProExclusive ? "Pro theme" : "Included")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .black.opacity(0.62) : .white.opacity(0.74))
                }

                Spacer(minLength: 6)

                HStack(spacing: 3) {
                    Circle()
                        .fill(theme.accentColor)
                    Circle()
                        .fill(theme.secondaryAccentColor)
                    Circle()
                        .fill(theme.gaugeSafeColor)
                }
                .frame(width: 24, height: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? theme.accentColor.opacity(0.96) : theme.accentColor.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.22) : theme.secondaryAccentColor.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: isSelected ? .black.opacity(0.22) : theme.accentColor.opacity(0.12), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct SessionHistoryView: View {
    @ObservedObject var historyStore: SessionHistoryStore
    let speedUnit: SpeedUnit
    let theme: AppTheme

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: theme.backgroundColors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if historyStore.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(historyStore.sessions) { session in
                                NavigationLink {
                                    SessionDetailView(session: session, speedUnit: speedUnit, theme: theme)
                                } label: {
                                    SessionRowView(session: session, speedUnit: speedUnit, theme: theme)
                                }
                                .buttonStyle(.plain)
                            }

                            Button("Clear History") {
                                historyStore.clear()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(theme.accentColor)

            Text("No sessions yet")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Finished trips and runs will appear here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

private struct SessionRowView: View {
    let session: SessionRecord
    let speedUnit: SpeedUnit
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack {
                rowMetric(title: "Avg", value: speedValue(session.averageSpeedKmh))
                Spacer(minLength: 6)
                rowMetric(title: "Dist", value: distanceValue(session.distanceKm))
                Spacer(minLength: 6)
                rowMetric(title: "Move", value: Self.durationFormatter.string(from: session.movingTime) ?? "0:00")
            }
        }
        .padding(10)
        .background(theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.borderColor, lineWidth: 1)
        )
    }

    private func rowMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(theme.secondaryAccentColor.opacity(0.9))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
        }
    }

    private func speedValue(_ kmh: Double) -> String {
        String(format: "%.1f %@", speedUnit.speed(fromKmh: kmh), speedUnit.speedLabel)
    }

    private func distanceValue(_ km: Double) -> String {
        String(format: "%.2f %@", speedUnit.distance(fromKm: km), speedUnit.distanceLabel)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

private struct SessionDetailView: View {
    let session: SessionRecord
    let speedUnit: SpeedUnit
    let theme: AppTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                detailCard(title: "Summary", rows: [
                    ("Start", session.startedAt.formatted(.dateTime.day().month(.wide).year().hour().minute())),
                    ("End", session.endedAt.formatted(.dateTime.hour().minute())),
                    ("Distance", String(format: "%.2f %@", speedUnit.distance(fromKm: session.distanceKm), speedUnit.distanceLabel)),
                    ("Average", String(format: "%.1f %@", speedUnit.speed(fromKmh: session.averageSpeedKmh), speedUnit.speedLabel)),
                    ("Max", String(format: "%.1f %@", speedUnit.speed(fromKmh: session.maxSpeedKmh), speedUnit.speedLabel)),
                ])

                detailCard(title: "Time", rows: [
                    ("Duration", Self.durationFormatter.string(from: session.duration) ?? "0:00"),
                    ("Moving", Self.durationFormatter.string(from: session.movingTime) ?? "0:00"),
                    ("Stopped", Self.durationFormatter.string(from: session.stoppedTime) ?? "0:00"),
                ])
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(LinearGradient(colors: theme.backgroundColors, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Session")
    }

    private func detailCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accentColor)

            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))

                    Spacer(minLength: 6)

                    Text(row.1)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
        }
        .padding(10)
        .background(theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.borderColor, lineWidth: 1)
        )
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
