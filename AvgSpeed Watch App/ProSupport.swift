//
//  ProSupport.swift
//  AvgSpeed Watch App
//
//  Pro entitlement, theme, and session history support.
//

import Foundation
import SwiftUI
import Combine
import StoreKit

extension SharedDefaults {
    static let proUnlockedKey = "pro_unlocked"
    static let distanceStallHapticsEnabledKey = "distance_stall_haptics_enabled"
    static let gpsSignalHapticsEnabledKey = "gps_signal_haptics_enabled"
    static let appThemeKey = "app_theme"
    static let sessionHistoryKey = "session_history"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case ocean
    case ember
    case volt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean:
            return "Ocean"
        case .ember:
            return "Ember"
        case .volt:
            return "Volt"
        }
    }

    var isProExclusive: Bool {
        switch self {
        case .ocean:
            return false
        case .ember, .volt:
            return true
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .ocean:
            return [Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.06, green: 0.18, blue: 0.34)]
        case .ember:
            return [Color(red: 0.16, green: 0.05, blue: 0.04), Color(red: 0.47, green: 0.17, blue: 0.08)]
        case .volt:
            return [Color(red: 0.02, green: 0.08, blue: 0.06), Color(red: 0.04, green: 0.30, blue: 0.18)]
        }
    }

    var panelFill: Color {
        switch self {
        case .ocean:
            return .white.opacity(0.12)
        case .ember:
            return Color(red: 0.98, green: 0.73, blue: 0.53).opacity(0.16)
        case .volt:
            return Color(red: 0.73, green: 0.96, blue: 0.54).opacity(0.14)
        }
    }

    var panelStrongFill: Color {
        switch self {
        case .ocean:
            return .white.opacity(0.20)
        case .ember:
            return Color(red: 0.99, green: 0.80, blue: 0.62).opacity(0.24)
        case .volt:
            return Color(red: 0.83, green: 0.98, blue: 0.66).opacity(0.22)
        }
    }

    var borderColor: Color {
        switch self {
        case .ocean:
            return .white.opacity(0.15)
        case .ember:
            return Color(red: 1.0, green: 0.85, blue: 0.72).opacity(0.22)
        case .volt:
            return Color(red: 0.88, green: 1.0, blue: 0.81).opacity(0.22)
        }
    }

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

    var secondaryAccentColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.61, green: 0.83, blue: 1.0)
        case .ember:
            return Color(red: 1.0, green: 0.56, blue: 0.48)
        case .volt:
            return Color(red: 0.58, green: 1.0, blue: 0.82)
        }
    }

    var gaugeSafeColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.28, green: 0.94, blue: 0.82)
        case .ember:
            return Color(red: 1.0, green: 0.77, blue: 0.34)
        case .volt:
            return Color(red: 0.74, green: 1.0, blue: 0.39)
        }
    }

    var gaugeAlertColor: Color {
        switch self {
        case .ocean:
            return Color(red: 1.0, green: 0.38, blue: 0.45)
        case .ember:
            return Color(red: 1.0, green: 0.40, blue: 0.32)
        case .volt:
            return Color(red: 1.0, green: 0.82, blue: 0.24)
        }
    }

    static func resolved(rawValue: String, hasPro: Bool) -> AppTheme {
        let theme = AppTheme(rawValue: rawValue) ?? .ocean
        if theme.isProExclusive && !hasPro {
            return .ocean
        }
        return theme
    }
}

struct SessionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let movingTime: TimeInterval
    let stoppedTime: TimeInterval
    let distanceKm: Double
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
}

@MainActor
final class SessionHistoryStore: ObservableObject {
    static let shared = SessionHistoryStore()

    @Published private(set) var sessions: [SessionRecord] = []

    private let defaults = SharedDefaults.store
    private let maxSessionCount = 100

    private init() {
        load()
    }

    func add(_ session: SessionRecord) {
        sessions.insert(session, at: 0)
        if sessions.count > maxSessionCount {
            sessions.removeLast(sessions.count - maxSessionCount)
        }
        save()
    }

    func clear() {
        sessions.removeAll()
        defaults.removeObject(forKey: SharedDefaults.sessionHistoryKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: SharedDefaults.sessionHistoryKey) else {
            sessions = []
            return
        }

        do {
            sessions = try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            sessions = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            defaults.set(data, forKey: SharedDefaults.sessionHistoryKey)
        } catch {
            assertionFailure("Failed to encode session history: \(error)")
        }
    }
}

private enum ProPurchaseError: LocalizedError {
    case failedVerification
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "The App Store transaction couldn't be verified."
        case .productUnavailable:
            return "AvgSpeed Pro is unavailable right now."
        }
    }
}

@MainActor
final class ProPurchaseStore: ObservableObject {
    static let shared = ProPurchaseStore()
    static let productID = "com.vkassin.avgspeed.pro"

    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isProUnlocked: Bool
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let defaults = SharedDefaults.store
    private var didPrepare = false
    private var updatesTask: Task<Void, Never>?

    private init() {
        isProUnlocked = SharedDefaults.store.bool(forKey: SharedDefaults.proUnlockedKey)
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in StoreKit.Transaction.updates {
                await self.handleTransactionUpdate(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var isBusy: Bool {
        isLoadingProduct || isPurchasing || isRestoring
    }

    func prepare() async {
        if !didPrepare {
            didPrepare = true
            await loadProduct()
        }

        await refreshEntitlements()
    }

    func purchase() async {
        clearMessage()

        if product == nil {
            await loadProduct()
        }

        guard let product else {
            presentMessage(ProPurchaseError.productUnavailable.localizedDescription, isError: true)
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                presentMessage("Purchase is pending approval.", isError: false)
            case .userCancelled:
                break
            @unknown default:
                presentMessage("The App Store returned an unknown purchase result.", isError: true)
            }
        } catch {
            presentMessage(error.localizedDescription, isError: true)
        }
    }

    func restorePurchases() async {
        clearMessage()

        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if isProUnlocked {
                presentMessage("AvgSpeed Pro restored.", isError: false)
            } else {
                presentMessage("No previous AvgSpeed Pro purchase was found for this Apple Account.", isError: false)
            }
        } catch {
            presentMessage("Restore failed. \(error.localizedDescription)", isError: true)
        }
    }

    func clearMessage() {
        message = nil
        messageIsError = false
    }

    private func loadProduct() async {
        guard !isLoadingProduct else { return }

        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first(where: { $0.id == Self.productID })
        } catch {
            product = nil
            presentMessage("Couldn't load AvgSpeed Pro from the App Store. \(error.localizedDescription)", isError: true)
        }
    }

    private func refreshEntitlements() async {
        var unlocked = false

        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(from: result) else { continue }

            if transaction.productID == Self.productID && transaction.revocationDate == nil {
                unlocked = true
                break
            }
        }

        updateEntitlementState(isUnlocked: unlocked)
    }

    private func handleTransactionUpdate(_ update: VerificationResult<StoreKit.Transaction>) async {
        do {
            let transaction = try verify(update)
            await transaction.finish()

            if transaction.productID == Self.productID {
                await refreshEntitlements()
            }
        } catch {
            presentMessage(ProPurchaseError.failedVerification.localizedDescription, isError: true)
        }
    }

    private func updateEntitlementState(isUnlocked: Bool) {
        isProUnlocked = isUnlocked
        defaults.set(isUnlocked, forKey: SharedDefaults.proUnlockedKey)
    }

    private func presentMessage(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }

    private func verifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            return nil
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signedType):
            return signedType
        case .unverified:
            throw ProPurchaseError.failedVerification
        }
    }
}
