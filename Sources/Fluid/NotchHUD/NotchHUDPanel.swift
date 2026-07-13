import AppKit

/// The always-on, non-activating panel that hosts the notch HUD.
///
/// Config rationale (all values verified against a working notch companion app):
/// - `.borderless + .nonactivatingPanel`: interactable without stealing focus
///   from the frontmost app.
/// - `level = .statusBar`: above normal windows, but BELOW the recording
///   overlay's `.screenSaver` panel, so during dictation the overlay always wins.
/// - `.canJoinAllSpaces + .fullScreenAuxiliary + .stationary`: visible on every
///   Space including fullscreen apps, ignores Exposé.
/// - Clear background + `isOpaque = false`: fully transparent regions pass
///   clicks through to the menu bar underneath.
final class NotchHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.appearance = NSAppearance(named: .darkAqua)
        self.animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
