//
//  managerApp.swift
//  manager
//
//  Created by Zhuanz1 on 2026/9/19.
//

import SwiftUI
import AppIntents

@main
struct managerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = TaskStore.shared
    @State private var reminders = ReminderService()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).environment(reminders)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .onChange(of: store.document.boards, initial: true) { _, _ in ChidiShortcuts.updateAppShortcutParameters() }
                .onChange(of: store.document, initial: true) { _, document in
                    if !store.isReadOnly { reminders.refresh(document) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !store.isReadOnly { reminders.refresh(store.document) }
                }
        }
    }
}
