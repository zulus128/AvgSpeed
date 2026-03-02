//
//  AvgSpeedApp.swift
//  AvgSpeed Watch App
//
//  Created by VADIM KASSIN on 15.12.2025.
//

import SwiftUI
import ClockKit
import WatchKit

@main
struct AvgSpeed_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    @StateObject private var tracker = SpeedTracker.shared

    init() {
        SharedDefaults.migrateLegacyValuesIfNeeded()

        // Keep the class linked even though it is referenced from Info.plist by name.
        _ = ComplicationController.self

        // Make sure watchOS refreshes available complication descriptors after installs/updates.
        CLKComplicationServer.sharedInstance().reloadComplicationDescriptors()

        #if DEBUG
        debugPrintComplicationRegistration()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
        }
    }
}

#if DEBUG
private func debugPrintComplicationRegistration() {
    let bundle = Bundle.main
    let principal = (bundle.object(forInfoDictionaryKey: "CLKComplicationPrincipalClass") as? String) ?? "nil"
    let families = bundle.object(forInfoDictionaryKey: "CLKComplicationSupportedFamilies") ?? "nil"
    let resolved = NSClassFromString(principal) ?? NSClassFromString("\(bundle.bundleIdentifier ?? "").ComplicationController")
    print("[Complications:Bundle]")
    print("  bundleId: \(bundle.bundleIdentifier ?? "nil")")
    print("  principal: \(principal)")
    print("  principalResolved: \(resolved != nil)")
    print("  families: \(families)")
}
#endif

final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func handle(_ userActivity: NSUserActivity) {
        guard userActivity.userInfo?[CLKLaunchedTimelineEntryDateKey] != nil else { return }
        Task { @MainActor in
            SpeedTracker.shared.stopFromComplicationTap()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
