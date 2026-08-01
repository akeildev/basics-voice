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
                    .background(BasicsWindowChrome())
            }
            // The toolbar otherwise paints its own material over the ground.
            .toolbarBackground(BasicsTokens.Surface.bg, for: .windowToolbar)
        }
        .defaultSize(width: 1040, height: 680)
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

/// Applies the Basics window chrome to whichever window hosts this view.
///
/// SwiftUI's `WindowGroup` builds its own `NSWindow`, so the AppKit-side
/// treatment in `MenuBarManager.applyBasicsChrome` never reaches it. This
/// zero-size representable reaches up to its host window and applies the same
/// transparent titlebar + ground-coloured background, so the chrome and the
/// page are one plain colour on both window paths.
private struct BasicsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            MenuBarManager.applyBasicsChrome(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        MenuBarManager.applyBasicsChrome(to: window)
    }
}
