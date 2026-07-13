import AppKit
import SwiftUI

/// Owns the persistent notch HUD panel: creation, screen placement, and
/// suppression while the recording overlay owns the notch.
///
/// Mounted lazily by AppServices AFTER the UI-ready gate (never during app
/// launch — see AppServices' defensive-startup notes). MenuBarManager talks to
/// it through `NotchHUDController.active` so suppression never force-creates it.
@MainActor
final class NotchHUDController {
    /// Set while a controller exists; used by MenuBarManager's suppression
    /// hooks without triggering lazy creation.
    private(set) static weak var active: NotchHUDController?

    private let state = NotchHUDState()
    private var panel: NotchHUDPanel?
    /// Generation counter guards suppress/restore races: only the newest
    /// request may apply its visibility outcome (mirrors NotchOverlayManager's
    /// own state-machine guards).
    private var suppressionGeneration = 0

    private static let panelSize = CGSize(width: 640, height: 210)

    init() {
        Self.active = self
    }

    func start() {
        guard self.panel == nil else { return }
        self.createPanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DebugLogger.shared.info("Notch HUD started", source: "NotchHUD")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        self.panel?.orderOut(nil)
        self.panel = nil
        DebugLogger.shared.info("Notch HUD stopped", source: "NotchHUD")
    }

    /// Hide/show around the recording overlay. 150 ms fade, generation-guarded.
    func setSuppressed(_ suppressed: Bool) {
        guard self.state.isSuppressed != suppressed else { return }
        self.state.isSuppressed = suppressed
        self.suppressionGeneration += 1
        let generation = self.suppressionGeneration
        guard let panel = self.panel else { return }

        DebugLogger.shared.debug("Notch HUD suppressed=\(suppressed)", source: "NotchHUD")
        if suppressed {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self, self.suppressionGeneration == generation else { return }
                    self.panel?.orderOut(nil)
                }
            })
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    // MARK: - Panel lifecycle

    private func createPanel() {
        let screen = Self.hudScreen()
        self.state.closedSize = Self.closedNotchSize(for: screen)

        let panel = NotchHUDPanel(contentRect: Self.panelFrame(on: screen))
        let hosting = NSHostingView(rootView: NotchHUDRootView(state: self.state))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        DebugLogger.shared.info(
            "Notch HUD panel on screen=\(screen?.localizedName ?? "none") closed=\(self.state.closedSize)",
            source: "NotchHUD"
        )
    }

    @objc private func screenConfigurationChanged() {
        guard let panel = self.panel else { return }
        let screen = Self.hudScreen()
        self.state.closedSize = Self.closedNotchSize(for: screen)
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        DebugLogger.shared.info(
            "Notch HUD repositioned after screen change (screen=\(screen?.localizedName ?? "none"))",
            source: "NotchHUD"
        )
    }

    // MARK: - Geometry

    /// Prefer the screen with a physical notch; fall back to the main screen.
    private static func hudScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Fixed-size panel pinned top-center; SwiftUI animates content within it.
    private static func panelFrame(on screen: NSScreen?) -> NSRect {
        guard let screen else {
            return NSRect(origin: .zero, size: self.panelSize)
        }
        let f = screen.frame
        return NSRect(
            x: f.origin.x + (f.width - self.panelSize.width) / 2,
            y: f.origin.y + f.height - self.panelSize.height,
            width: self.panelSize.width,
            height: self.panelSize.height
        )
    }

    /// Physical notch footprint: screen width minus the menu-bar areas either
    /// side of the notch (+4 pt fudge for the corner curves). Non-notch
    /// displays get a Dynamic-Island-style 185×32.
    private static func closedNotchSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return CGSize(width: 185, height: 32) }
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea
        {
            return CGSize(
                width: screen.frame.width - left.width - right.width + 4,
                height: topInset
            )
        }
        return CGSize(width: 185, height: 32)
    }
}
