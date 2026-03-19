//
//  AvgSpeedApp.swift
//  AvgSpeed Watch App
//
//  Created by VADIM KASSIN on 15.12.2025.
//

import SwiftUI
import WatchKit

@main
struct AvgSpeed_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    @StateObject private var tracker = SpeedTracker.shared

    init() {
        SharedDefaults.migrateLegacyValuesIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
        }
    }
}

final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
