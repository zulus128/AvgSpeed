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
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    @StateObject private var tracker = SpeedTracker.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
        }
    }
}

final class ExtensionDelegate: NSObject, WKExtensionDelegate {
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
