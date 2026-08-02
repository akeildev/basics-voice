//
//  fluidApp.swift
//  fluid
//
//  Created by Barathwaj Anandan on 7/30/25.
//

import AppKit
import ApplicationServices
import SwiftUI

@main
struct FluidApp: App {
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var appServices: AppServices
    @ObservedObject private var settings = SettingsStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Use the shared singleton instance
        _appServices = StateObject(wrappedValue: AppServices.shared)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            AdaptiveAppTheme(accent: self.settings.accentColor) {
                ContentView()
                    .environmentObject(self.menuBarManager)
                    .environmentObject(self.appServices)
            }
            // Drops the hairline the toolbar otherwise rules under itself. This
            // is the SwiftUI knob for it — not to be confused with the
            // `.toolbarBackground(Surface.bg, …)` that used to be here, which
            // PAINTED that band white and was one of the four surfaces fighting
            // over the top strip.
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        // 720, not 680: onboarding's own minimum is 700, so the smaller default
        // made the window jump on first launch.
        .defaultSize(width: 1040, height: 720)
        // State restoration otherwise reopens whatever frame the window last
        // had — including a screen-filling one from an older build. This is a
        // configure-and-glance window; it always opens compact.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    self.menuBarManager.openPreferencesFromUI()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
