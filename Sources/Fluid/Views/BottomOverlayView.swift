//
//  BottomOverlayView.swift
//  Fluid
//
//  Bottom overlay for transcription (alternative to notch overlay)
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

private enum OverlayShortcutResolver {
    static func shortcutDisplay(for mode: OverlayMode, settings: SettingsStore = .shared) -> String {
        switch mode {
        case .dictation:
            return settings.primaryDictationShortcutDisplayString
        case .edit, .write, .rewrite:
            return settings.rewriteModeHotkeyShortcut.displayString
        case .command:
            return settings.commandModeHotkeyShortcut?.displayString ?? "Not set"
        }
    }
}

enum RecordingOverlayHideOutcome: Equatable {
    case hidden
    case superseded
}

// MARK: - Overlay dark chrome (board 17)

/// Mode colours live here rather than on `OverlayMode.notchColor`, which the
/// recording notch owns and which is out of scope for the redesign.
private enum OverlayModePalette {
    static func fill(for mode: OverlayMode) -> Color {
        switch mode {
        case .dictation: return BasicsTokens.Dark.modeDictate
        case .edit, .write, .rewrite: return BasicsTokens.Dark.modeEdit
        case .command: return BasicsTokens.Dark.modeCommand
        }
    }

    /// The label colour to use on top of a 14%-tinted fill of the same hue.
    static func ink(for mode: OverlayMode) -> Color {
        switch mode {
        case .dictation: return BasicsTokens.Dark.modeDictateInk
        case .edit, .write, .rewrite: return BasicsTokens.Dark.modeEditInk
        case .command: return BasicsTokens.Dark.modeCommandInk
        }
    }
}

/// The shared shell for the three chip menus: one panel spec, one row spec.
private enum OverlayMenuChrome {
    static let panelRadius: CGFloat = 14
    static let rowRadius: CGFloat = 9
    static let rowHeight: CGFloat = 34

    @ViewBuilder
    static func rowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let fill: Color = isSelected
            ? BasicsTokens.Dark.accentStrong
            : (isHovered ? BasicsTokens.Dark.rowHover : Color.clear)
        let stroke: Color = isSelected ? BasicsTokens.Dark.accentBorder : Color.clear

        RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    /// The trailing shortcut / hint capsule on a menu row.
    @ViewBuilder
    static func shortcutCapsule(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .basicsMono(11)
            .foregroundStyle(isSelected ? BasicsTokens.Dark.accentInk : BasicsTokens.Dark.faint)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(
                Capsule().fill(
                    isSelected
                        ? BasicsTokens.Dark.accent.opacity(0.18)
                        : Color.white.opacity(0.05)
                )
            )
    }

    static func divider() -> some View {
        Rectangle()
            .fill(BasicsTokens.Dark.hairline)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

private struct OverlayMenuPanel: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: OverlayMenuChrome.panelRadius, style: .continuous)
                    .fill(BasicsTokens.Dark.menu)
                    .overlay(
                        RoundedRectangle(cornerRadius: OverlayMenuChrome.panelRadius, style: .continuous)
                            .strokeBorder(BasicsTokens.Dark.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 16)
            )
            .padding(6) // room for the shadow inside the borderless panel
            .frame(width: self.maxWidth + 12)
            .preferredColorScheme(.dark)
    }
}

extension View {
    fileprivate func overlayMenuPanel(maxWidth: CGFloat) -> some View {
        self.modifier(OverlayMenuPanel(maxWidth: maxWidth))
    }
}

private final class BottomOverlayPanel: NSPanel {
    var allowsOffscreenParking = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        self.allowsOffscreenParking ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

// MARK: - Bottom Overlay Window Controller

@MainActor
final class BottomOverlayWindowController {
    static let shared = BottomOverlayWindowController()

    private var window: NSPanel?
    private var audioSubscription: AnyCancellable?
    private var pendingResizeWorkItem: DispatchWorkItem?
    private var pendingReleaseTransitionResetWorkItem: DispatchWorkItem?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var targetScreen: NSScreen?
    private var releaseTransitionActiveUntil: Date?
    private var deferredResizePending = false
    private var presentationGeneration: UInt64 = 0
    private let dismissalDuration: TimeInterval = 0.02
    private var isHideInProgress = false
    private var activeHideGeneration: UInt64?
    private var hideWaiters: [CheckedContinuation<RecordingOverlayHideOutcome, Never>] = []

    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlayOffsetChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.positionWindow()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlaySizeChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSizeAndPositionUpdate(after: 0)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
                if NotchContentState.shared.isBottomOverlayPresented {
                    self.positionWindow()
                } else {
                    self.parkWindowOffscreen()
                }
            }
        }
    }

    /// Pay the one-time SwiftUI/WindowServer surface cost after launch and keep
    /// the static panel outside the entire desktop so its surface is not evicted.
    func prepare() {
        guard self.window == nil else { return }
        self.createWindow()
        self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
        guard let window else { return }

        self.parkWindowOffscreen()
        window.alphaValue = 1
        window.orderFrontRegardless()
        CATransaction.flush()
        Self.overlayBench("bottom_prepared")
    }

    func show(audioPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("bottom_show_start mode=\(mode.rawValue) windowExists=\(self.window != nil)")
        self.cancelInFlightHideForNewPresentation()
        self.presentationGeneration &+= 1

        self.endReleaseTransition(flushDeferredUpdate: false)
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        BottomOverlayPromptMenuController.shared.hide()
        BottomOverlayModeMenuController.shared.hide()
        BottomOverlayActionsMenuController.shared.hide()
        self.ensureMouseDownMonitors()

        // Create window if needed
        if self.window == nil {
            self.createWindow()
        }

        // Prepare the complete first frame while the cached panel is still
        // offscreen. Revealing the neutral shell first causes a visible flash
        // that reads as the overlay appearing twice.
        NotchContentState.shared.setBottomOverlayPresented(true)
        NotchContentState.shared.mode = mode
        switch mode {
        case .dictation: NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite: NotchContentState.shared.promptPickerMode = .edit
        case .command: break
        }
        NotchContentState.shared.updateTranscription("")
        NotchContentState.shared.bottomOverlayAudioLevel = 0
        NotchContentState.shared.setBottomOverlayDismissOffsetY(8)
        NotchContentState.shared.setBottomOverlayDismissing(false)

        self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
        self.positionWindow()

        // Submit one complete frame to WindowServer.
        self.window?.setAccessibilityChildren(nil)
        self.window?.setAccessibilityElement(true)
        self.window?.alphaValue = 1
        self.window?.orderFrontRegardless()
        self.window?.contentView?.displayIfNeeded()
        self.window?.displayIfNeeded()
        CATransaction.flush()
        Self.overlayBench("bottom_order_front elapsedMs=\(Self.elapsedMs(since: startedAt))")
        Self.overlayBench("bottom_visible elapsedMs=\(Self.elapsedMs(since: startedAt))")

        self.audioSubscription?.cancel()
        self.audioSubscription = audioPublisher
            .receive(on: DispatchQueue.main)
            .sink { level in
                NotchContentState.shared.bottomOverlayAudioLevel = level
            }
    }

    func hide() {
        guard !self.isHideInProgress else { return }
        self.isHideInProgress = true
        self.presentationGeneration &+= 1
        let currentGeneration = self.presentationGeneration
        self.activeHideGeneration = currentGeneration
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.performHideAndWait(generation: currentGeneration)
            self.completeHideOperation(generation: currentGeneration, outcome: outcome)
        }
    }

    /// Returns whether the panel finished hiding or a newer presentation
    /// superseded this request.
    func hideAndWait() async -> RecordingOverlayHideOutcome {
        if self.isHideInProgress {
            return await withCheckedContinuation { continuation in
                self.hideWaiters.append(continuation)
            }
        }

        self.isHideInProgress = true
        self.presentationGeneration &+= 1
        let currentGeneration = self.presentationGeneration
        self.activeHideGeneration = currentGeneration
        let outcome = await self.performHideAndWait(generation: currentGeneration)
        self.completeHideOperation(generation: currentGeneration, outcome: outcome)
        return outcome
    }

    private func completeHideOperation(generation: UInt64, outcome: RecordingOverlayHideOutcome) {
        guard self.activeHideGeneration == generation else { return }
        self.activeHideGeneration = nil
        self.isHideInProgress = false
        let waiters = self.hideWaiters
        self.hideWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: outcome) }
    }

    private func cancelInFlightHideForNewPresentation() {
        guard self.isHideInProgress else { return }
        self.activeHideGeneration = nil
        self.isHideInProgress = false
        let waiters = self.hideWaiters
        self.hideWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: .superseded) }
        Self.overlayBench("bottom_hide_cancelled_for_new_presentation")
    }

    private func performHideAndWait(generation currentGeneration: UInt64) async -> RecordingOverlayHideOutcome {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("bottom_hide_start windowExists=\(self.window != nil)")
        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }

        guard let window = self.window, NotchContentState.shared.isBottomOverlayPresented else {
            self.clearPresentationResources()
            self.endReleaseTransition(flushDeferredUpdate: false)
            NotchContentState.shared.setBottomOverlayDismissing(false)
            NotchContentState.shared.targetAppIcon = nil
            Self.overlayBench("bottom_hide_return reason=no_window")
            return .hidden
        }

        NotchContentState.shared.setBottomOverlayReleaseTransitioning(true)
        NotchContentState.shared.setBottomOverlayDismissOffsetY(8)
        NotchContentState.shared.setBottomOverlayDismissing(true)

        // SwiftUI owns the dismissal animation. Keeping AppKit alpha at 1
        // prevents an old implicit window animation from hiding a rapid restart.
        Self.overlayBench("bottom_hide_animation_start")
        await Task.yield()
        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }
        self.clearPresentationResources()

        try? await Task.sleep(nanoseconds: UInt64(self.dismissalDuration * 1_000_000_000))

        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }

        self.parkWindowOffscreen()
        window.alphaValue = 1
        NotchContentState.shared.setBottomOverlayPresented(false)
        self.endReleaseTransition(flushDeferredUpdate: false)
        NotchContentState.shared.setBottomOverlayDismissing(false)
        NotchContentState.shared.targetAppIcon = nil
        Self.overlayBench("bottom_hide_complete elapsedMs=\(Self.elapsedMs(since: startedAt))")
        return .hidden
    }

    private func clearPresentationResources() {
        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        self.pendingReleaseTransitionResetWorkItem?.cancel()
        self.targetScreen = nil
        self.removeMouseDownMonitors()
        BottomOverlayPromptMenuController.shared.hide()
        BottomOverlayModeMenuController.shared.hide()
        BottomOverlayActionsMenuController.shared.hide()
        NotchContentState.shared.setProcessing(false)
        NotchContentState.shared.bottomOverlayAudioLevel = 0
    }

    func setProcessing(_ processing: Bool) {
        Self.overlayBench("bottom_set_processing processing=\(processing)")
        NotchContentState.shared.setProcessing(processing)
    }

    func refreshSizeForContent() {
        self.scheduleSizeAndPositionUpdate()
    }

    func beginReleaseTransition(duration: TimeInterval = 0.28) {
        let now = Date()
        let deadline = now.addingTimeInterval(max(duration, 0.12))
        if let existingDeadline = self.releaseTransitionActiveUntil, existingDeadline > deadline {
            self.releaseTransitionActiveUntil = existingDeadline
        } else {
            self.releaseTransitionActiveUntil = deadline
        }

        self.pendingReleaseTransitionResetWorkItem?.cancel()

        guard let activeDeadline = self.releaseTransitionActiveUntil else { return }
        let resetWorkItem = DispatchWorkItem { [weak self] in
            self?.endReleaseTransition()
        }
        self.pendingReleaseTransitionResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(activeDeadline.timeIntervalSince(now), 0), execute: resetWorkItem)

        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        NotchContentState.shared.bottomOverlayAudioLevel = 0
        NotchContentState.shared.setBottomOverlayReleaseTransitioning(true)
    }

    func endReleaseTransition(flushDeferredUpdate: Bool = true) {
        self.pendingReleaseTransitionResetWorkItem?.cancel()
        self.pendingReleaseTransitionResetWorkItem = nil
        self.releaseTransitionActiveUntil = nil
        NotchContentState.shared.setBottomOverlayReleaseTransitioning(false)

        let shouldFlush = flushDeferredUpdate && self.deferredResizePending
        self.deferredResizePending = false

        if shouldFlush, self.window?.isVisible == true {
            self.scheduleSizeAndPositionUpdate(after: 0)
        }
    }

    private static func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: message, source: "OverlayBenchmark")
    }

    private static func elapsedMs(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private func scheduleSizeAndPositionUpdate(after delay: TimeInterval = 0.08) {
        if self.isReleaseTransitionActive {
            self.deferredResizePending = true
            return
        }

        self.pendingResizeWorkItem?.cancel()

        // Debounce rapid streaming updates to avoid resize thrash.
        let resizeWorkItem = DispatchWorkItem { [weak self] in
            self?.updateSizeAndPosition()
        }
        self.pendingResizeWorkItem = resizeWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: resizeWorkItem)
    }

    /// Update window size based on current SwiftUI content and re-position
    private func updateSizeAndPosition() {
        if self.isReleaseTransitionActive {
            self.deferredResizePending = true
            return
        }

        guard let window = window, let hostingView = window.contentView as? NSHostingView<BottomOverlayView> else { return }

        // Re-calculate fitting size for the new layout constants
        let newSize = hostingView.fittingSize

        // Avoid redundant content-size updates while AppKit is already resolving constraints.
        // Re-applying the same size can trigger unnecessary update-constraints churn.
        let currentSize = window.contentView?.frame.size ?? window.frame.size
        let widthChanged = abs(currentSize.width - newSize.width) > 0.5
        let heightChanged = abs(currentSize.height - newSize.height) > 0.5

        if widthChanged || heightChanged {
            // Resize from the current origin to avoid AppKit's default top-left anchoring,
            // which can visually push the overlay down before we re-position it.
            let currentOrigin = window.frame.origin
            let resizedFrame = NSRect(origin: currentOrigin, size: newSize)
            window.setFrame(resizedFrame, display: false)
        }

        // Re-position
        self.positionWindow()
    }

    private func createWindow() {
        let panel = BottomOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI handles shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayView()
        let hostingView = BottomOverlayHostingView(rootView: contentView)

        // Let SwiftUI determine the size
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        // Make hosting view fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.display()

        self.window = panel
    }

    private var isReleaseTransitionActive: Bool {
        guard let deadline = self.releaseTransitionActiveUntil else { return false }
        if deadline > Date() {
            return true
        }

        self.releaseTransitionActiveUntil = nil
        return false
    }

    private func ensureMouseDownMonitors() {
        if self.localMouseDownMonitor == nil {
            self.localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let clickPoint: NSPoint
                if let window = event.window {
                    clickPoint = window.convertPoint(toScreen: event.locationInWindow)
                } else {
                    clickPoint = NSEvent.mouseLocation
                }

                Task { @MainActor [weak self] in
                    self?.dismissMenusForClick(screenPoint: clickPoint)
                }
                return event
            }
        }

        if self.globalMouseDownMonitor == nil {
            self.globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                let clickPoint = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.dismissMenusForClick(screenPoint: clickPoint)
                }
            }
        }
    }

    private func removeMouseDownMonitors() {
        if let monitor = self.localMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMouseDownMonitor = nil
        }
        if let monitor = self.globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalMouseDownMonitor = nil
        }
    }

    @MainActor
    private func dismissMenusForClick(screenPoint: NSPoint) {
        guard self.window?.isVisible == true else { return }
        BottomOverlayPromptMenuController.shared.dismissIfNeeded(for: screenPoint)
        BottomOverlayModeMenuController.shared.dismissIfNeeded(for: screenPoint)
        BottomOverlayActionsMenuController.shared.dismissIfNeeded(for: screenPoint)
    }

    private func positionWindow() {
        // Safe check for window and screen availability
        guard let window = window else { return }
        guard NotchContentState.shared.isBottomOverlayPresented else {
            self.parkWindowOffscreen()
            return
        }
        (window as? BottomOverlayPanel)?.allowsOffscreenParking = false

        let screen = self.targetScreen ?? window.screen ?? OverlayScreenResolver.screenForCurrentPointer()
        guard let screen = screen else { return }

        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // Horizontal centering
        let x = fullFrame.midX - windowSize.width / 2

        // Vertical positioning with safety clamping
        let offset = SettingsStore.shared.overlayBottomOffset

        // The tab reserves a transparent shadow ring inside its window, so the
        // window's bottom edge sits that much below the visible surface. Take
        // it back off here, otherwise the offset setting silently lies by ~16px.
        let shadowPad = SettingsStore.shared.overlaySize == .pill ? PillShadowMetrics.shadowPad : 0

        // Calculate raw position
        var y = visibleFrame.minY + CGFloat(offset) - shadowPad

        // Safety Clamping:
        // 1. Min: Ensure the visible surface stays clear of the dock/visible area
        // 2. Max: Ensure it doesn't cross the top of the visible frame minus its own height
        let minY = visibleFrame.minY + 4 - shadowPad // Small buffer from absolute bottom
        let maxY = visibleFrame.maxY - windowSize.height - 40 // Buffer from top

        y = max(min(y, maxY), minY)

        // Apply position directly to avoid implicit frame animations during hover-driven resizes.
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func parkWindowOffscreen() {
        guard let window else { return }
        window.setAccessibilityChildren([])
        window.setAccessibilityElement(false)
        (window as? BottomOverlayPanel)?.allowsOffscreenParking = true
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        let edge = desktopFrame.isNull ? NSPoint(x: 100_000, y: 100_000) : NSPoint(
            x: desktopFrame.maxX + window.frame.width + 1024,
            y: desktopFrame.maxY + window.frame.height + 1024
        )
        window.setFrameOrigin(edge)
    }
}

@MainActor
final class BottomOverlayPromptMenuController {
    static let shared = BottomOverlayPromptMenuController()

    private var menuWindow: NSPanel?
    private var hostingView: NSHostingView<BottomOverlayPromptMenuView>?
    private var selectorFrameInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var menuMaxWidth: CGFloat = 220
    private var menuGap: CGFloat = 6

    private var isHoveringSelector = false
    private var isHoveringMenu = false
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingPositionWorkItem: DispatchWorkItem?

    private init() {}

    func updateAnchor(selectorFrameInScreen: CGRect, parentWindow: NSWindow?, maxWidth: CGFloat, menuGap: CGFloat) {
        guard selectorFrameInScreen.width > 0, selectorFrameInScreen.height > 0 else { return }

        let resolvedMaxWidth = max(maxWidth, 120)
        let widthChanged = abs(self.menuMaxWidth - resolvedMaxWidth) > 0.5

        self.selectorFrameInScreen = selectorFrameInScreen
        self.parentWindow = parentWindow
        self.menuMaxWidth = resolvedMaxWidth
        self.menuGap = max(menuGap, 0)

        if self.menuWindow?.isVisible == true {
            if widthChanged {
                self.updateMenuContent()
            }
            self.attachToParentWindowIfNeeded()
            self.scheduleMenuPositionUpdate()
        }
    }

    func selectorHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func menuHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func toggleFromTap() {
        if self.menuWindow?.isVisible == true {
            self.hide()
            return
        }
        self.showMenuIfPossible()
    }

    func hide() {
        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil
        self.pendingHideWorkItem?.cancel()
        self.pendingHideWorkItem = nil
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil

        self.isHoveringSelector = false
        self.isHoveringMenu = false

        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    func dismissIfNeeded(for screenPoint: NSPoint) {
        guard self.menuWindow?.isVisible == true else { return }
        let insideMenu = self.menuWindow?.frame.contains(screenPoint) ?? false
        let insideSelector = self.selectorFrameInScreen.contains(screenPoint)
        if !insideMenu, !insideSelector {
            self.hide()
        }
    }

    private func updateVisibility() {
        let shouldShow = self.isHoveringSelector || self.isHoveringMenu

        if shouldShow {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil

            if self.menuWindow?.isVisible == true {
                self.scheduleMenuPositionUpdate()
                return
            }

            self.pendingShowWorkItem?.cancel()
            let showTask = DispatchWorkItem { [weak self] in
                self?.showMenuIfPossible()
            }
            self.pendingShowWorkItem = showTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: showTask)
            return
        }

        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil

        self.pendingHideWorkItem?.cancel()
        let hideTask = DispatchWorkItem { [weak self] in
            self?.hideIfNotHovered()
        }
        self.pendingHideWorkItem = hideTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: hideTask)
    }

    private func hideIfNotHovered() {
        guard !self.isHoveringSelector, !self.isHoveringMenu else { return }
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil
        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    private func scheduleMenuPositionUpdate() {
        guard self.pendingPositionWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPositionWorkItem = nil
            self.updateMenuSizeAndPosition()
        }

        self.pendingPositionWorkItem = task
        DispatchQueue.main.async(execute: task)
    }

    private func showMenuIfPossible() {
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        self.createWindowIfNeeded()
        self.updateMenuContent()
        self.attachToParentWindowIfNeeded()
        self.updateMenuSizeAndPosition()
        self.menuWindow?.orderFrontRegardless()
    }

    private func createWindowIfNeeded() {
        guard self.menuWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayPromptMenuView(
            promptMode: self.resolvedPromptMode(),
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.menuWindow = panel
    }

    private func updateMenuContent() {
        let rootView = BottomOverlayPromptMenuView(
            promptMode: self.resolvedPromptMode(),
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )
        self.hostingView?.rootView = rootView
    }

    private func resolvedPromptMode() -> SettingsStore.PromptMode {
        switch NotchContentState.shared.mode {
        case .dictation:
            return .dictate
        case .edit, .write, .rewrite:
            return .edit
        case .command:
            return NotchContentState.shared.promptPickerMode.normalized
        }
    }

    private func attachToParentWindowIfNeeded() {
        guard let menuWindow = self.menuWindow else { return }

        if let currentParent = menuWindow.parent, currentParent !== self.parentWindow {
            currentParent.removeChildWindow(menuWindow)
        }

        if let parentWindow = self.parentWindow, menuWindow.parent !== parentWindow {
            parentWindow.addChildWindow(menuWindow, ordered: .above)
        }
    }

    private func updateMenuSizeAndPosition() {
        guard let menuWindow = self.menuWindow, let hostingView = self.hostingView else { return }
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        let preferredX = self.selectorFrameInScreen.midX - (fittingSize.width / 2)
        let preferredY = self.selectorFrameInScreen.maxY + self.menuGap

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: self.selectorFrameInScreen.midX, y: self.selectorFrameInScreen.midY)) })
            ?? NSScreen.main

        var targetX = preferredX
        var targetY = preferredY

        if let screen {
            let visible = screen.visibleFrame
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 8

            if fittingSize.width < visible.width - (horizontalInset * 2) {
                targetX = max(visible.minX + horizontalInset, min(preferredX, visible.maxX - fittingSize.width - horizontalInset))
            } else {
                targetX = visible.minX + horizontalInset
            }

            if fittingSize.height < visible.height - (verticalInset * 2) {
                targetY = max(visible.minY + verticalInset, min(preferredY, visible.maxY - fittingSize.height - verticalInset))
            } else {
                targetY = visible.minY + verticalInset
            }
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        let currentFrame = menuWindow.frame
        let frameTolerance: CGFloat = 0.5
        let isSameFrame =
            abs(currentFrame.origin.x - targetFrame.origin.x) <= frameTolerance &&
            abs(currentFrame.origin.y - targetFrame.origin.y) <= frameTolerance &&
            abs(currentFrame.size.width - targetFrame.size.width) <= frameTolerance &&
            abs(currentFrame.size.height - targetFrame.size.height) <= frameTolerance

        if !isSameFrame {
            menuWindow.setFrame(targetFrame, display: false)
        }
    }
}

@MainActor
final class BottomOverlayModeMenuController {
    static let shared = BottomOverlayModeMenuController()

    private var menuWindow: NSPanel?
    private var hostingView: NSHostingView<BottomOverlayModeMenuView>?
    private var selectorFrameInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var menuMaxWidth: CGFloat = 220
    private var menuGap: CGFloat = 6

    private var isHoveringSelector = false
    private var isHoveringMenu = false
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingPositionWorkItem: DispatchWorkItem?

    private init() {}

    func updateAnchor(selectorFrameInScreen: CGRect, parentWindow: NSWindow?, maxWidth: CGFloat, menuGap: CGFloat) {
        guard selectorFrameInScreen.width > 0, selectorFrameInScreen.height > 0 else { return }

        let resolvedMaxWidth = max(maxWidth, 120)
        let widthChanged = abs(self.menuMaxWidth - resolvedMaxWidth) > 0.5

        self.selectorFrameInScreen = selectorFrameInScreen
        self.parentWindow = parentWindow
        self.menuMaxWidth = resolvedMaxWidth
        self.menuGap = max(menuGap, 0)

        if self.menuWindow?.isVisible == true {
            if widthChanged {
                self.updateMenuContent()
            }
            self.attachToParentWindowIfNeeded()
            self.scheduleMenuPositionUpdate()
        }
    }

    func selectorHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func menuHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func toggleFromTap() {
        if self.menuWindow?.isVisible == true {
            self.hide()
            return
        }
        self.showMenuIfPossible()
    }

    func hide() {
        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil
        self.pendingHideWorkItem?.cancel()
        self.pendingHideWorkItem = nil
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil

        self.isHoveringSelector = false
        self.isHoveringMenu = false

        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    func dismissIfNeeded(for screenPoint: NSPoint) {
        guard self.menuWindow?.isVisible == true else { return }
        let insideMenu = self.menuWindow?.frame.contains(screenPoint) ?? false
        let insideSelector = self.selectorFrameInScreen.contains(screenPoint)
        if !insideMenu, !insideSelector {
            self.hide()
        }
    }

    private func updateVisibility() {
        let shouldShow = self.isHoveringSelector || self.isHoveringMenu

        if shouldShow {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil

            if self.menuWindow?.isVisible == true {
                self.scheduleMenuPositionUpdate()
                return
            }

            self.pendingShowWorkItem?.cancel()
            let showTask = DispatchWorkItem { [weak self] in
                self?.showMenuIfPossible()
            }
            self.pendingShowWorkItem = showTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: showTask)
            return
        }

        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil

        self.pendingHideWorkItem?.cancel()
        let hideTask = DispatchWorkItem { [weak self] in
            self?.hideIfNotHovered()
        }
        self.pendingHideWorkItem = hideTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: hideTask)
    }

    private func hideIfNotHovered() {
        guard !self.isHoveringSelector, !self.isHoveringMenu else { return }
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil
        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    private func scheduleMenuPositionUpdate() {
        guard self.pendingPositionWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPositionWorkItem = nil
            self.updateMenuSizeAndPosition()
        }

        self.pendingPositionWorkItem = task
        DispatchQueue.main.async(execute: task)
    }

    private func showMenuIfPossible() {
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        self.createWindowIfNeeded()
        self.updateMenuContent()
        self.attachToParentWindowIfNeeded()
        self.updateMenuSizeAndPosition()
        self.menuWindow?.orderFrontRegardless()
    }

    private func createWindowIfNeeded() {
        guard self.menuWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayModeMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.menuWindow = panel
    }

    private func updateMenuContent() {
        let rootView = BottomOverlayModeMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )
        self.hostingView?.rootView = rootView
    }

    private func attachToParentWindowIfNeeded() {
        guard let menuWindow = self.menuWindow else { return }

        if let currentParent = menuWindow.parent, currentParent !== self.parentWindow {
            currentParent.removeChildWindow(menuWindow)
        }

        if let parentWindow = self.parentWindow, menuWindow.parent !== parentWindow {
            parentWindow.addChildWindow(menuWindow, ordered: .above)
        }
    }

    private func updateMenuSizeAndPosition() {
        guard let menuWindow = self.menuWindow, let hostingView = self.hostingView else { return }
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        let preferredX = self.selectorFrameInScreen.midX - (fittingSize.width / 2)
        let preferredY = self.selectorFrameInScreen.maxY + self.menuGap

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: self.selectorFrameInScreen.midX, y: self.selectorFrameInScreen.midY)) })
            ?? NSScreen.main

        var targetX = preferredX
        var targetY = preferredY

        if let screen {
            let visible = screen.visibleFrame
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 8

            if fittingSize.width < visible.width - (horizontalInset * 2) {
                targetX = max(visible.minX + horizontalInset, min(preferredX, visible.maxX - fittingSize.width - horizontalInset))
            } else {
                targetX = visible.minX + horizontalInset
            }

            if fittingSize.height < visible.height - (verticalInset * 2) {
                targetY = max(visible.minY + verticalInset, min(preferredY, visible.maxY - fittingSize.height - verticalInset))
            } else {
                targetY = visible.minY + verticalInset
            }
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        let currentFrame = menuWindow.frame
        let frameTolerance: CGFloat = 0.5
        let isSameFrame =
            abs(currentFrame.origin.x - targetFrame.origin.x) <= frameTolerance &&
            abs(currentFrame.origin.y - targetFrame.origin.y) <= frameTolerance &&
            abs(currentFrame.size.width - targetFrame.size.width) <= frameTolerance &&
            abs(currentFrame.size.height - targetFrame.size.height) <= frameTolerance

        if !isSameFrame {
            menuWindow.setFrame(targetFrame, display: false)
        }
    }
}

@MainActor
final class BottomOverlayActionsMenuController {
    static let shared = BottomOverlayActionsMenuController()

    private var menuWindow: NSPanel?
    private var hostingView: NSHostingView<BottomOverlayActionsMenuView>?
    private var selectorFrameInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var menuMaxWidth: CGFloat = 220
    private var menuGap: CGFloat = 6

    private var isHoveringSelector = false
    private var isHoveringMenu = false
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingPositionWorkItem: DispatchWorkItem?

    private init() {}

    func updateAnchor(selectorFrameInScreen: CGRect, parentWindow: NSWindow?, maxWidth: CGFloat, menuGap: CGFloat) {
        guard selectorFrameInScreen.width > 0, selectorFrameInScreen.height > 0 else { return }

        let resolvedMaxWidth = max(maxWidth, 120)
        let widthChanged = abs(self.menuMaxWidth - resolvedMaxWidth) > 0.5

        self.selectorFrameInScreen = selectorFrameInScreen
        self.parentWindow = parentWindow
        self.menuMaxWidth = resolvedMaxWidth
        self.menuGap = max(menuGap, 0)

        if self.menuWindow?.isVisible == true {
            if widthChanged {
                self.updateMenuContent()
            }
            self.attachToParentWindowIfNeeded()
            self.scheduleMenuPositionUpdate()
        }
    }

    func selectorHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func menuHoverChanged(_ hovering: Bool) {
        // Hover-open disabled: menu is click/tap driven.
    }

    func toggleFromTap() {
        if self.menuWindow?.isVisible == true {
            self.hide()
            return
        }
        self.showMenuIfPossible()
    }

    func hide() {
        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil
        self.pendingHideWorkItem?.cancel()
        self.pendingHideWorkItem = nil
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil

        self.isHoveringSelector = false
        self.isHoveringMenu = false

        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    func dismissIfNeeded(for screenPoint: NSPoint) {
        guard self.menuWindow?.isVisible == true else { return }
        let insideMenu = self.menuWindow?.frame.contains(screenPoint) ?? false
        let insideSelector = self.selectorFrameInScreen.contains(screenPoint)
        if !insideMenu, !insideSelector {
            self.hide()
        }
    }

    private func updateVisibility() {
        let shouldShow = self.isHoveringSelector || self.isHoveringMenu

        if shouldShow {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil

            if self.menuWindow?.isVisible == true {
                self.scheduleMenuPositionUpdate()
                return
            }

            self.pendingShowWorkItem?.cancel()
            let showTask = DispatchWorkItem { [weak self] in
                self?.showMenuIfPossible()
            }
            self.pendingShowWorkItem = showTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: showTask)
            return
        }

        self.pendingShowWorkItem?.cancel()
        self.pendingShowWorkItem = nil

        self.pendingHideWorkItem?.cancel()
        let hideTask = DispatchWorkItem { [weak self] in
            self?.hideIfNotHovered()
        }
        self.pendingHideWorkItem = hideTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: hideTask)
    }

    private func hideIfNotHovered() {
        guard !self.isHoveringSelector, !self.isHoveringMenu else { return }
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil
        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
    }

    private func scheduleMenuPositionUpdate() {
        guard self.pendingPositionWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPositionWorkItem = nil
            self.updateMenuSizeAndPosition()
        }

        self.pendingPositionWorkItem = task
        DispatchQueue.main.async(execute: task)
    }

    private func showMenuIfPossible() {
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        self.createWindowIfNeeded()
        self.updateMenuContent()
        self.attachToParentWindowIfNeeded()
        self.updateMenuSizeAndPosition()
        self.menuWindow?.orderFrontRegardless()
    }

    private func createWindowIfNeeded() {
        guard self.menuWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayActionsMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.menuWindow = panel
    }

    private func updateMenuContent() {
        let rootView = BottomOverlayActionsMenuView(
            maxWidth: self.menuMaxWidth,
            onHoverChanged: { [weak self] hovering in
                self?.menuHoverChanged(hovering)
            },
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )
        self.hostingView?.rootView = rootView
    }

    private func attachToParentWindowIfNeeded() {
        guard let menuWindow = self.menuWindow else { return }

        if let currentParent = menuWindow.parent, currentParent !== self.parentWindow {
            currentParent.removeChildWindow(menuWindow)
        }

        if let parentWindow = self.parentWindow, menuWindow.parent !== parentWindow {
            parentWindow.addChildWindow(menuWindow, ordered: .above)
        }
    }

    private func updateMenuSizeAndPosition() {
        guard let menuWindow = self.menuWindow, let hostingView = self.hostingView else { return }
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        let preferredX = self.selectorFrameInScreen.midX - (fittingSize.width / 2)
        let preferredY = self.selectorFrameInScreen.maxY + self.menuGap

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: self.selectorFrameInScreen.midX, y: self.selectorFrameInScreen.midY)) })
            ?? NSScreen.main

        var targetX = preferredX
        var targetY = preferredY

        if let screen {
            let visible = screen.visibleFrame
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 8

            if fittingSize.width < visible.width - (horizontalInset * 2) {
                targetX = max(visible.minX + horizontalInset, min(preferredX, visible.maxX - fittingSize.width - horizontalInset))
            } else {
                targetX = visible.minX + horizontalInset
            }

            if fittingSize.height < visible.height - (verticalInset * 2) {
                targetY = max(visible.minY + verticalInset, min(preferredY, visible.maxY - fittingSize.height - verticalInset))
            } else {
                targetY = visible.minY + verticalInset
            }
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        let currentFrame = menuWindow.frame
        let frameTolerance: CGFloat = 0.5
        let isSameFrame =
            abs(currentFrame.origin.x - targetFrame.origin.x) <= frameTolerance &&
            abs(currentFrame.origin.y - targetFrame.origin.y) <= frameTolerance &&
            abs(currentFrame.size.width - targetFrame.size.width) <= frameTolerance &&
            abs(currentFrame.size.height - targetFrame.size.height) <= frameTolerance

        if !isSameFrame {
            menuWindow.setFrame(targetFrame, display: false)
        }
    }
}

private struct BottomOverlayModeMenuView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var settings = SettingsStore.shared

    let maxWidth: CGFloat
    let onHoverChanged: (Bool) -> Void
    let onDismissRequested: () -> Void

    @State private var hoveredRowID: String?

    private var normalizedOverlayMode: OverlayMode {
        switch self.contentState.mode {
        case .dictation:
            return .dictation
        case .edit, .write, .rewrite:
            return .edit
        case .command:
            return .command
        }
    }

    @ViewBuilder
    private func modeRow(_ title: String, mode: OverlayMode, rowID: String) -> some View {
        let isSelected = self.normalizedOverlayMode == mode
        let isHovered = self.hoveredRowID == rowID
        let shortcut = OverlayShortcutResolver.shortcutDisplay(for: mode, settings: self.settings)
        let isInert = self.contentState.isProcessing

        Button(action: {
            guard !isInert else { return }
            self.contentState.onOverlayModeSwitchRequested?(mode)
            self.onDismissRequested()
        }) {
            HStack(alignment: .center, spacing: 10) {
                // Fixed lane so the three labels line up whether ticked or not.
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BasicsTokens.Dark.accent)
                    }
                }
                .frame(width: 14)

                Text(title)
                    .basicsLabel(13)
                    .foregroundStyle(
                        isSelected
                            ? BasicsTokens.Dark.accentInk
                            : (isHovered ? BasicsTokens.Dark.ink : BasicsTokens.Dark.inkSubtle)
                    )
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !shortcut.isEmpty {
                    OverlayMenuChrome.shortcutCapsule(shortcut, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: OverlayMenuChrome.rowHeight)
            .background(OverlayMenuChrome.rowBackground(isSelected: isSelected, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .disabled(isInert)
        .opacity(isInert ? 0.45 : 1)
        .onHover { hovering in
            self.hoveredRowID = (hovering && !isInert) ? rowID : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            self.modeRow("Dictate", mode: .dictation, rowID: "dictate")
            self.modeRow("Edit", mode: .edit, rowID: "edit")

            OverlayMenuChrome.divider()

            self.modeRow("Command", mode: .command, rowID: "command")
        }
        .overlayMenuPanel(maxWidth: self.maxWidth)
        .onHover { hovering in
            self.onHoverChanged(hovering)
        }
    }
}

/// The white pill that marks "this prompt comes from a per-app binding".
private struct OverlayAppBadge: View {
    var body: some View {
        Text("App")
            .basicsLabel(10)
            .tracking(BasicsTokens.Tracking.wide(at: 10) * 0.25)
            .foregroundStyle(BasicsTokens.Dark.ground)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(Color.white.opacity(0.9)))
    }
}

private struct BottomOverlayPromptMenuView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared

    let promptMode: SettingsStore.PromptMode
    let maxWidth: CGFloat
    let onHoverChanged: (Bool) -> Void
    let onDismissRequested: () -> Void
    @State private var hoveredRowID: String?

    private var privateAILocked: Bool {
        self.promptMode.normalized == .dictate && PrivateAIProviderPromptFormat.isAvailable(settings: self.settings)
    }

    /// One shape for every row in this menu: tick lane, label, optional trailing
    /// badge. `trailing` carries the App-binding badge and the not-available hint.
    @ViewBuilder
    private func promptRow<Trailing: View>(
        title: String,
        rowID: String,
        isSelected: Bool,
        isEnabled: Bool,
        @ViewBuilder trailing: () -> Trailing,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = self.hoveredRowID == rowID

        Button(action: {
            guard isEnabled else { return }
            action()
        }) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BasicsTokens.Dark.accent)
                    }
                }
                .frame(width: 14)

                Text(title)
                    .basicsLabel(13)
                    .foregroundStyle(
                        isSelected
                            ? BasicsTokens.Dark.accentInk
                            : (isHovered ? BasicsTokens.Dark.ink : BasicsTokens.Dark.inkSubtle)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                trailing()
            }
            .padding(.horizontal, 10)
            .frame(height: OverlayMenuChrome.rowHeight)
            .background(OverlayMenuChrome.rowBackground(isSelected: isSelected, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering in
            self.hoveredRowID = (hovering && isEnabled) ? rowID : nil
        }
    }

    @ViewBuilder
    private func offRow() -> some View {
        let activeSlot = self.contentState.activeDictationShortcutSlot ?? .primary
        let isSelected = self.settings.dictationPromptSelection(for: activeSlot) == .off
        self.promptRow(
            title: "Off",
            rowID: "off",
            isSelected: isSelected,
            isEnabled: true,
            trailing: { EmptyView() }
        ) {
            if self.promptMode.normalized == .dictate {
                self.contentState.onDictationPromptSelectionRequested?(.off)
            } else {
                self.settings.setDictationPromptSelection(.off)
            }
            self.restoreTypingTargetApp()
            self.onDismissRequested()
        }
    }

    @ViewBuilder
    private func defaultRow(selectedID: String?) -> some View {
        let activeSlot = self.contentState.activeDictationShortcutSlot ?? .primary
        let isSelected = !self.privateAILocked && (
            self.promptMode.normalized == .dictate
                ? (self.settings.dictationPromptSelection(for: activeSlot) == .default)
                : (selectedID == nil)
        )
        self.promptRow(
            title: "Default",
            rowID: "default",
            isSelected: isSelected,
            isEnabled: !self.privateAILocked,
            trailing: { EmptyView() }
        ) {
            if self.promptMode.normalized == .dictate {
                self.contentState.onDictationPromptSelectionRequested?(.default)
            } else {
                self.settings.setSelectedPromptID(nil, for: self.promptMode)
            }
            self.restoreTypingTargetApp()
            self.onDismissRequested()
        }
    }

    @ViewBuilder
    private func privateAIRow() -> some View {
        let activeSlot = self.contentState.activeDictationShortcutSlot ?? .primary
        let isAvailable = PrivateAIProviderPromptFormat.isAvailable(settings: self.settings)
        let isSelected = self.settings.dictationPromptSelection(for: activeSlot) == .privateAI
        self.promptRow(
            title: PrivateAIProviderFeature.displayName,
            rowID: PrivateAIProviderFeature.shared.providerID,
            isSelected: isSelected,
            isEnabled: isAvailable,
            trailing: {
                if !isAvailable {
                    Text("not available")
                        .basicsMono(11)
                        .foregroundStyle(BasicsTokens.Dark.faint)
                }
            }
        ) {
            self.contentState.onDictationPromptSelectionRequested?(.privateAI)
            self.restoreTypingTargetApp()
            self.onDismissRequested()
        }
        .help(isAvailable ? "Use \(PrivateAIProviderFeature.displayName)" : "Select \(PrivateAIProviderFeature.displayName) to enable this prompt")
    }

    @ViewBuilder
    private func profileRow(_ profile: SettingsStore.DictationPromptProfile, selectedID: String?) -> some View {
        let activeSlot = self.contentState.activeDictationShortcutSlot ?? .primary
        let isSelected = !self.privateAILocked && (
            self.promptMode.normalized == .dictate
                ? (self.settings.dictationPromptSelection(for: activeSlot) == .profile(profile.id))
                : (selectedID == profile.id)
        )
        let isAppBound = self.isAppBoundProfile(profile, activeSlot: activeSlot)
        self.promptRow(
            title: profile.name.isEmpty ? "Untitled" : profile.name,
            rowID: profile.id,
            isSelected: isSelected,
            isEnabled: !self.privateAILocked,
            trailing: {
                if isAppBound {
                    OverlayAppBadge()
                }
            }
        ) {
            if self.promptMode.normalized == .dictate {
                self.contentState.onDictationPromptSelectionRequested?(.profile(profile.id))
            } else {
                self.settings.setSelectedPromptID(profile.id, for: self.promptMode)
            }
            self.restoreTypingTargetApp()
            self.onDismissRequested()
        }
    }

    /// True when the frontmost app's prompt binding resolves to THIS profile, so
    /// the badge in the menu matches the badge on the chip that opened it.
    private func isAppBoundProfile(
        _ profile: SettingsStore.DictationPromptProfile,
        activeSlot: SettingsStore.DictationShortcutSlot
    ) -> Bool {
        let bundleID = self.activeAppMonitor.activeAppBundleID
        if self.promptMode.normalized == .dictate {
            guard self.settings.isAppDictationPromptBindingActive(for: activeSlot, appBundleID: bundleID) else {
                return false
            }
            return self.settings.resolvedDictationPromptProfile(for: activeSlot, appBundleID: bundleID)?.id == profile.id
        }
        guard self.settings.hasAppPromptBinding(for: self.promptMode, appBundleID: bundleID) else { return false }
        return self.settings.resolvedPromptProfile(for: self.promptMode, appBundleID: bundleID)?.id == profile.id
    }

    var body: some View {
        let selectedID = self.settings.selectedPromptID(for: self.promptMode)
        let profiles = self.settings.promptProfiles(for: self.promptMode)

        VStack(alignment: .leading, spacing: 2) {
            if self.promptMode.normalized == .dictate {
                self.offRow()

                OverlayMenuChrome.divider()
            }

            if !self.privateAILocked {
                self.defaultRow(selectedID: selectedID)
            }

            if self.promptMode.normalized == .dictate && PrivateFeatures.privateAIProvider {
                self.privateAIRow()
            }

            if !self.privateAILocked && !profiles.isEmpty {
                OverlayMenuChrome.divider()

                ForEach(profiles) { profile in
                    self.profileRow(profile, selectedID: selectedID)
                }
            }
        }
        .overlayMenuPanel(maxWidth: self.maxWidth)
        .onHover { hovering in
            self.onHoverChanged(hovering)
        }
    }

    private func restoreTypingTargetApp() {
        let pid = NotchContentState.shared.recordingTargetPID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let pid { _ = TypingService.activateApp(pid: pid) }
        }
    }
}

private struct BottomOverlayActionsMenuView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared

    let maxWidth: CGFloat
    let onHoverChanged: (Bool) -> Void
    let onDismissRequested: () -> Void

    @State private var hoveredRowID: String?

    private var canReprocessLast: Bool {
        !self.historyStore.entries.isEmpty && !self.contentState.isProcessing
    }

    private var latestEntry: TranscriptionHistoryEntry? {
        self.historyStore.entries.first
    }

    private var canCopyLast: Bool {
        guard !self.contentState.isProcessing else { return false }
        return self.latestEntry?.clipboardText != nil
    }

    private var canPasteLast: Bool {
        self.canCopyLast
    }

    private var canUndoLastAI: Bool {
        guard !self.contentState.isProcessing else { return false }
        guard let latest = self.latestEntry else { return false }
        let raw = latest.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return latest.wasAIProcessed && !raw.isEmpty
    }

    private func actionRow(
        title: String,
        icon: String,
        rowID: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = self.hoveredRowID == rowID

        return Button(action: {
            guard enabled else { return }
            action()
            self.onDismissRequested()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(enabled ? BasicsTokens.Dark.accent : BasicsTokens.Dark.muted)
                    .frame(width: 14)

                Text(title)
                    .basicsLabel(13)
                    .foregroundStyle(isHovered ? BasicsTokens.Dark.ink : BasicsTokens.Dark.inkSubtle)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: OverlayMenuChrome.rowHeight)
            .background(OverlayMenuChrome.rowBackground(isSelected: false, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering in
            guard enabled else {
                self.hoveredRowID = nil
                return
            }
            self.hoveredRowID = hovering ? rowID : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            self.actionRow(
                title: "Reprocess last dictation",
                icon: "arrow.clockwise",
                rowID: "reprocess_last",
                enabled: self.canReprocessLast
            ) {
                self.contentState.onReprocessLastRequested?()
            }

            self.actionRow(
                title: "Copy last transcription",
                icon: "doc.on.doc",
                rowID: "copy_last",
                enabled: self.canCopyLast
            ) {
                self.contentState.onCopyLastRequested?()
            }

            self.actionRow(
                title: "Paste last transcription",
                icon: "arrow.down.doc",
                rowID: "paste_last",
                enabled: self.canPasteLast
            ) {
                self.contentState.onPasteLastRequested?()
            }

            OverlayMenuChrome.divider()

            self.actionRow(
                title: "Undo AI on last",
                icon: "arrow.uturn.backward",
                rowID: "undo_ai_last",
                enabled: self.canUndoLastAI
            ) {
                self.contentState.onUndoLastAIRequested?()
            }
        }
        .overlayMenuPanel(maxWidth: self.maxWidth)
        .onHover { hovering in
            self.onHoverChanged(hovering)
        }
    }
}

private struct PromptSelectorAnchorReader: NSViewRepresentable {
    let onFrameChange: (CGRect, NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorReportingView {
        let view = AnchorReportingView()
        view.onFrameChange = self.onFrameChange
        return view
    }

    func updateNSView(_ nsView: AnchorReportingView, context: Context) {
        nsView.onFrameChange = self.onFrameChange
        nsView.reportFrame(force: true)
    }

    final class AnchorReportingView: NSView {
        var onFrameChange: ((CGRect, NSWindow?) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []
        private var lastReportedFrameInScreen: CGRect = .null
        private weak var lastReportedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.installWindowObservers()
            self.reportFrame(force: true)
        }

        override func layout() {
            super.layout()
            self.reportFrame()
        }

        deinit {
            self.cleanup()
        }

        func cleanup() {
            for observer in self.windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.windowObservers.removeAll()
        }

        private func installWindowObservers() {
            self.cleanup()
            guard let window = self.window else { return }

            let center = NotificationCenter.default
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
        }

        func reportFrame(force: Bool = false) {
            guard let window = self.window else {
                if force || !self.lastReportedFrameInScreen.isNull {
                    self.lastReportedFrameInScreen = .null
                    self.lastReportedWindow = nil
                    self.onFrameChange?(CGRect.zero, nil)
                }
                return
            }

            let frameInWindow = self.convert(self.bounds, to: nil)
            let frameInScreen = window.convertToScreen(frameInWindow)
            let frameTolerance: CGFloat = 0.5
            let hasLastFrame = !self.lastReportedFrameInScreen.isNull
            let frameChanged = !hasLastFrame ||
                abs(frameInScreen.origin.x - self.lastReportedFrameInScreen.origin.x) > frameTolerance ||
                abs(frameInScreen.origin.y - self.lastReportedFrameInScreen.origin.y) > frameTolerance ||
                abs(frameInScreen.size.width - self.lastReportedFrameInScreen.size.width) > frameTolerance ||
                abs(frameInScreen.size.height - self.lastReportedFrameInScreen.size.height) > frameTolerance
            let windowChanged = self.lastReportedWindow !== window

            guard force || frameChanged || windowChanged else { return }

            self.lastReportedFrameInScreen = frameInScreen
            self.lastReportedWindow = window
            self.onFrameChange?(frameInScreen, window)
        }
    }
}

private enum PillShadowMetrics {
    // Keep in sync with the pill shadow in BottomOverlayView.body.
    static let radius: CGFloat = 10
    static let yOffset: CGFloat = 4
    /// Transparent ring reserved around the tab so the (content-sized) window
    /// doesn't clip its drop shadow. Subtracted again when positioning, so the
    /// bottom-offset setting means the gap you can actually see.
    static let shadowPad: CGFloat = radius + abs(yOffset) + 2
    /// Hit-test inset must cover the visible shadow extent so the shadow
    /// region doesn't intercept clicks.
    static let hitTestInset: CGFloat = shadowPad
}

private final class BottomOverlayHostingView: NSHostingView<BottomOverlayView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if SettingsStore.shared.overlaySize == .pill {
            let visibleOverlayBounds = self.bounds.insetBy(
                dx: PillShadowMetrics.hitTestInset,
                dy: PillShadowMetrics.hitTestInset
            )
            guard visibleOverlayBounds.contains(point) else { return nil }
        }
        return super.hitTest(point)
    }
}

private struct DynamicPreviewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

// MARK: - Bottom Overlay SwiftUI View

struct BottomOverlayView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var appServices = AppServices.shared
    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringModeChip = false
    @State private var isHoveringPromptChip = false
    @State private var isHoveringActionsChip = false
    @State private var isHoveringSettingsChip = false
    @State private var modeSelectorFrameInScreen: CGRect = .zero
    @State private var modeSelectorWindow: NSWindow?
    @State private var promptSelectorFrameInScreen: CGRect = .zero
    @State private var promptSelectorWindow: NSWindow?
    @State private var actionsSelectorFrameInScreen: CGRect = .zero
    @State private var actionsSelectorWindow: NSWindow?
    @State private var dynamicPreviewMeasuredHeight: CGFloat = 0
    @State private var frozenDynamicPreviewHeight: CGFloat?
    @State private var dynamicPreviewResizeBucket: Int = 0
    @State private var processingStatusVisible = false
    @State private var lastResolvedAppIcon: NSImage?
    @State private var borderAnimationStartedAt: Date?

    struct LayoutConstants {
        let hPadding: CGFloat
        let vPadding: CGFloat
        let waveformWidth: CGFloat
        let waveformHeight: CGFloat
        let iconSize: CGFloat
        let transFontSize: CGFloat
        let modeFontSize: CGFloat
        let cornerRadius: CGFloat
        let barCount: Int
        let barWidth: CGFloat
        let barSpacing: CGFloat
        let minBarHeight: CGFloat
        let maxBarHeight: CGFloat
        let containerWidth: CGFloat
        let overlayWidth: CGFloat
        let overlayHeight: CGFloat
        let previewBoxHeight: CGFloat
        /// Vertical gap between the chip row, the waveform row and the preview.
        let contentGap: CGFloat
        let usesFixedCanvas: Bool
        let showsTopControls: Bool
        let showsPreview: Bool
        let showsModeLabel: Bool
        /// The app icon / mode dot to the left of the waveform. The tab drops
        /// it so the waveform is the only thing on the surface.
        var showsLeadingGlyph: Bool = true
        /// How much of the bar's travel the OUTERMOST bar keeps. The profile
        /// tapers from the centre outward; on a big panel a hard taper looks
        /// like a proper waveform, but on the tab it leaves the end bars nearly
        /// still and the whole thing reads as dead. The tab keeps them moving.
        var barPeakFloor: CGFloat = 0.18

        static func get(for size: SettingsStore.OverlaySize) -> LayoutConstants {
            switch size {
            case .pill:
                // The tab: a 64x24 sliver that floats just clear of the bottom
                // edge. Waveform only — no app icon, no mode dot, no label, so
                // it never competes with whatever else lives at the notch.
                // Six bars rather than eight: at this width eight read as a
                // dotted line, and the whole point of the tab is the movement.
                return LayoutConstants(
                    hPadding: 14,
                    vPadding: 5,
                    waveformWidth: 36,
                    waveformHeight: 14,
                    iconSize: 0,
                    transFontSize: 10,
                    modeFontSize: 9,
                    cornerRadius: 12,
                    barCount: 6,
                    barWidth: 3.0,
                    barSpacing: 3.5,
                    minBarHeight: 3,
                    maxBarHeight: 14,
                    containerWidth: 64,
                    overlayWidth: 64,
                    overlayHeight: 24,
                    previewBoxHeight: 0,
                    contentGap: 0,
                    usesFixedCanvas: false,
                    showsTopControls: false,
                    showsPreview: false,
                    showsModeLabel: false,
                    showsLeadingGlyph: false,
                    barPeakFloor: 0.62
                )
            case .small:
                return LayoutConstants(
                    hPadding: 18,
                    vPadding: 16,
                    waveformWidth: 90,
                    waveformHeight: 20,
                    iconSize: 16,
                    transFontSize: 13,
                    modeFontSize: 12,
                    cornerRadius: 14,
                    barCount: 7,
                    barWidth: 3.0,
                    barSpacing: 10,
                    minBarHeight: 5,
                    maxBarHeight: 20,
                    containerWidth: 300,
                    overlayWidth: 300,
                    overlayHeight: 124,
                    previewBoxHeight: 0,
                    contentGap: 14,
                    usesFixedCanvas: false,
                    showsTopControls: false,
                    showsPreview: true,
                    showsModeLabel: true
                )
            case .medium:
                return LayoutConstants(
                    hPadding: 16,
                    vPadding: 15,
                    waveformWidth: 130,
                    waveformHeight: 32,
                    iconSize: 20,
                    transFontSize: 13,
                    modeFontSize: 12,
                    cornerRadius: 18,
                    barCount: 9,
                    barWidth: 4.0,
                    barSpacing: 11,
                    minBarHeight: 6,
                    maxBarHeight: 32,
                    containerWidth: 420,
                    overlayWidth: 420,
                    overlayHeight: 168,
                    previewBoxHeight: 0,
                    contentGap: 14,
                    usesFixedCanvas: false,
                    showsTopControls: true,
                    showsPreview: true,
                    showsModeLabel: true
                )
            case .large:
                return LayoutConstants(
                    hPadding: 22,
                    vPadding: 20,
                    waveformWidth: 180,
                    waveformHeight: 48,
                    iconSize: 26,
                    transFontSize: 14,
                    modeFontSize: 14,
                    cornerRadius: 24,
                    barCount: 11,
                    barWidth: 5.0,
                    barSpacing: 12.0,
                    minBarHeight: 8,
                    maxBarHeight: 48,
                    containerWidth: 600,
                    overlayWidth: 600,
                    overlayHeight: 288,
                    previewBoxHeight: 92,
                    contentGap: 14,
                    usesFixedCanvas: true,
                    showsTopControls: true,
                    showsPreview: true,
                    showsModeLabel: true
                )
            }
        }
    }

    private var layout: LayoutConstants {
        LayoutConstants.get(for: self.settings.overlaySize)
    }

    private var isCompactControls: Bool {
        self.settings.overlaySize == .medium
    }

    private var isPillSize: Bool {
        self.settings.overlaySize == .pill
    }

    /// The overlay's own mode palette (Basics ramp). `OverlayMode.notchColor`
    /// still drives the recording notch, which is out of scope here.
    private var modeColor: Color {
        OverlayModePalette.fill(for: self.contentState.mode)
    }

    /// Mode label colour when it sits on an accent-tinted fill.
    private var modeInk: Color {
        OverlayModePalette.ink(for: self.contentState.mode)
    }

    private var modeLabel: String {
        switch self.contentState.mode {
        case .dictation: return "Dictate"
        case .edit, .rewrite, .write: return "Edit"
        case .command: return "Command"
        }
    }

    private var displayedAppIcon: NSImage? {
        self.contentState.targetAppIcon ?? self.activeAppMonitor.activeAppIcon ?? self.lastResolvedAppIcon
    }

    private var processingLabel: String {
        switch self.contentState.mode {
        case .dictation: return "Refining..."
        case .edit, .rewrite, .write: return "Thinking..."
        case .command: return "Working..."
        }
    }

    private static let transientOverlayStatusTexts: Set<String> = [
        "Transcribing",
        "Refining",
        "Thinking",
        "Working",
        "Transcribing...",
        "Refining...",
        "Thinking...",
        "Working...",
    ]

    /// ContentView writes transient status strings into transcriptionText while processing
    /// (e.g. "Transcribing...", "Refining..."). Prefer that when present.
    private var processingStatusText: String {
        let t = self.contentState.transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.transientOverlayStatusTexts.contains(t) else { return self.processingLabel }
        return t
    }

    private var hasTranscription: Bool {
        !self.transcriptionPreviewText.isEmpty
    }

    private var normalizedOverlayMode: OverlayMode {
        switch self.contentState.mode {
        case .dictation:
            return .dictation
        case .edit, .write, .rewrite:
            return .edit
        case .command:
            return .command
        }
    }

    private var activePromptMode: SettingsStore.PromptMode? {
        switch self.normalizedOverlayMode {
        case .dictation:
            return .dictate
        case .edit:
            return .edit
        case .command, .write, .rewrite:
            return nil
        }
    }

    private var isPromptSelectableMode: Bool {
        self.activePromptMode != nil
    }

    private var promptResolutionBundleID: String? {
        self.activeAppMonitor.activeAppBundleID
    }

    private var activeDictationShortcutSlot: SettingsStore.DictationShortcutSlot {
        self.contentState.activeDictationShortcutSlot ?? .primary
    }

    private var isAppPromptOverrideActive: Bool {
        guard let activePromptMode else { return false }
        if activePromptMode.normalized == .dictate {
            return self.settings.isAppDictationPromptBindingActive(
                for: self.activeDictationShortcutSlot,
                appBundleID: self.promptResolutionBundleID
            )
        }
        return self.settings.hasAppPromptBinding(
            for: activePromptMode,
            appBundleID: self.promptResolutionBundleID
        )
    }

    private var selectedPromptLabel: String {
        guard let activePromptMode else { return "N/A" }
        if activePromptMode.normalized == .dictate {
            return self.settings.dictationPromptDisplayName(
                for: self.activeDictationShortcutSlot,
                appBundleID: self.promptResolutionBundleID
            )
        }
        if let profile = self.settings.resolvedPromptProfile(
            for: activePromptMode,
            appBundleID: self.promptResolutionBundleID
        ) {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled" : name
        }
        return "Default"
    }

    private var promptSelectorDisplayLabel: String {
        let label = self.selectedPromptLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Default" }

        let maxLength: Int
        if self.isCompactControls {
            maxLength = self.isAppPromptOverrideActive ? 8 : 14
        } else {
            maxLength = self.isAppPromptOverrideActive ? 11 : 16
        }

        guard label.count > maxLength else { return label }
        let prefixLength = max(maxLength - 3, 1)
        return "\(label.prefix(prefixLength))..."
    }

    /// Distance from the chip to the menu it opens. The menu panel reserves its
    /// own 6pt transparent ring for the drop shadow, which supplies the gap.
    private var promptMenuGap: CGFloat {
        0
    }

    /// Menu width (board 17: all three chip menus are 280 wide).
    private var promptSelectorMaxWidth: CGFloat {
        280
    }

    private var previewMaxHeight: CGFloat {
        self.layout.usesFixedCanvas ? self.layout.previewBoxHeight : self.layout.transFontSize * 4.2
    }

    private var shouldReservePreviewArea: Bool {
        self.layout.showsPreview &&
            (self.settings.enableStreamingPreview || self.contentState.isAIProcessingFailureVisible)
    }

    private var overlayFrameHeight: CGFloat? {
        guard self.layout.usesFixedCanvas else { return nil }
        return self.shouldReservePreviewArea ? self.layout.overlayHeight : nil
    }

    private var previewMaxWidth: CGFloat {
        if self.layout.usesFixedCanvas {
            return self.layout.waveformWidth * 2.2
        }

        return max(self.layout.waveformWidth * 2.2, self.layout.containerWidth - self.layout.hPadding * 2)
    }

    private var dynamicPreviewBaseMinHeight: CGFloat {
        guard self.shouldReservePreviewArea else { return 0 }
        let verticalPadding = self.settings.overlaySize == .small
            ? max(2, self.transcriptionVerticalPadding - 1)
            : self.transcriptionVerticalPadding
        return self.estimatedPreviewLineHeight + verticalPadding * 2
    }

    private var effectiveDynamicPreviewLockedHeight: CGFloat? {
        guard self.contentState.isBottomOverlayReleaseTransitioning else { return nil }
        guard let frozenDynamicPreviewHeight else { return nil }
        return max(frozenDynamicPreviewHeight, self.dynamicPreviewBaseMinHeight)
    }

    private var effectiveDynamicPreviewMinHeight: CGFloat {
        self.effectiveDynamicPreviewLockedHeight ?? self.dynamicPreviewBaseMinHeight
    }

    private var estimatedPreviewLineHeight: CGFloat {
        max(self.layout.transFontSize * 1.25, self.layout.transFontSize + 2)
    }

    private var currentPreviewSizingText: String {
        guard self.shouldReservePreviewArea else { return "" }
        if self.shouldShowProcessingPreview {
            return self.processingPreviewText
        }
        return self.shouldShowProcessingStatus ? self.processingStatusText : self.transcriptionPreviewText
    }

    private var shouldShowProcessingStatus: Bool {
        self.shouldReservePreviewArea && self.contentState.isProcessing && self.processingStatusVisible
    }

    private var shouldShowAIProcessingFailure: Bool {
        self.shouldReservePreviewArea && self.contentState.isAIProcessingFailureVisible && !self.contentState.isProcessing
    }

    private var shouldSuppressPreviewDuringRelease: Bool {
        if self.shouldShowProcessingPreview {
            return false
        }
        return self.contentState.isBottomOverlayReleaseTransitioning || self.contentState.isBottomOverlayDismissing
    }

    private func previewResizeBucket(for previewText: String) -> Int {
        guard self.shouldReservePreviewArea else { return 0 }
        if self.shouldShowAIProcessingFailure { return 1 }
        let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self.shouldShowProcessingStatus ? 1 : 0 }

        if self.settings.overlaySize == .small {
            return 1
        }

        let newlineCount = trimmed.filter { $0 == "\n" }.count
        let estimatedCharacterWidth = max(self.layout.transFontSize * 0.56, 1)
        let characterCapacity = max(Int((self.previewMaxWidth / estimatedCharacterWidth).rounded(.down)), 12)
        let estimatedWrappedLines = max(1, (trimmed.count + characterCapacity - 1) / characterCapacity)
        let maxVisibleLines = max(Int((self.previewMaxHeight / max(self.estimatedPreviewLineHeight, 1)).rounded(.down)), 1)
        return min(max(estimatedWrappedLines + newlineCount, 1), maxVisibleLines)
    }

    private func refreshDynamicPreviewSizeIfNeeded(for previewText: String) {
        guard self.shouldReservePreviewArea else { return }
        guard !self.layout.usesFixedCanvas else { return }
        let nextBucket = self.previewResizeBucket(for: previewText)
        guard nextBucket != self.dynamicPreviewResizeBucket else { return }
        self.dynamicPreviewResizeBucket = nextBucket
        BottomOverlayWindowController.shared.refreshSizeForContent()
    }

    private var transcriptionVerticalPadding: CGFloat {
        max(4, self.layout.vPadding / 2)
    }

    private var transcriptionPreviewText: String {
        let preview = self.contentState.cachedPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !self.contentState.isProcessing else { return self.contentState.cachedPreviewText }
        guard Self.transientOverlayStatusTexts.contains(preview) else { return self.contentState.cachedPreviewText }
        return ""
    }

    private var processingPreviewText: String {
        guard self.contentState.isProcessing else { return "" }
        let preview = self.transcriptionPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.transientOverlayStatusTexts.contains(preview) else { return "" }
        return self.transcriptionPreviewText
    }

    private var shouldShowProcessingPreview: Bool {
        !self.processingPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func richPreviewText(_ previewText: String) -> Text {
        Text(previewText)
            .foregroundColor(BasicsTokens.Dark.ink)
    }

    private var overlayAnimatedOffsetY: CGFloat {
        if self.contentState.isBottomOverlayDismissing {
            return self.contentState.bottomOverlayDismissOffsetY
        }
        return 0
    }

    private var overlayAnimatedScale: CGFloat {
        self.contentState.isBottomOverlayDismissing ? 0.985 : 1.0
    }

    private var overlayAnimatedOpacity: Double {
        1.0
    }

    /// The neutral chip: a capsule on the panel, not a black pill floating above it.
    private func chipBackground(isHovered: Bool, disabled: Bool) -> some View {
        Capsule()
            .fill(isHovered && !disabled ? BasicsTokens.Dark.chipFillHover : BasicsTokens.Dark.chipFill)
            .overlay(
                Capsule().strokeBorder(
                    isHovered && !disabled ? BasicsTokens.Dark.chipBorderHover : BasicsTokens.Dark.chipBorder,
                    lineWidth: 1
                )
            )
    }

    /// The mode chip is the one green moment on this surface, tinted with the
    /// current mode's own hue.
    private func modeChipBackground(isHovered: Bool, disabled: Bool) -> some View {
        Capsule()
            .fill(self.modeColor.opacity(isHovered && !disabled ? 0.20 : 0.14))
            .overlay(
                Capsule().strokeBorder(
                    self.modeColor.opacity(isHovered && !disabled ? 0.44 : 0.32),
                    lineWidth: 1
                )
            )
    }

    private var chipHeight: CGFloat {
        self.isCompactControls ? 22 : 24
    }

    private func closePromptMenu() {
        BottomOverlayPromptMenuController.shared.hide()
    }

    private func rememberAppIcon(_ icon: NSImage?) {
        guard let icon else { return }
        self.lastResolvedAppIcon = icon
    }

    private func handlePromptSelectorHover(_ hovering: Bool) {
        // Hover-open disabled by design.
    }

    private func handlePromptSelectorFrameChange(_ frameInScreen: CGRect, window: NSWindow?) {
        self.promptSelectorFrameInScreen = frameInScreen
        self.promptSelectorWindow = window
        guard self.layout.showsTopControls, self.isPromptSelectableMode, !self.contentState.isProcessing else {
            BottomOverlayPromptMenuController.shared.hide()
            return
        }

        BottomOverlayPromptMenuController.shared.updateAnchor(
            selectorFrameInScreen: frameInScreen,
            parentWindow: window,
            maxWidth: self.promptSelectorMaxWidth,
            menuGap: self.promptMenuGap
        )
    }

    private func requestModeSwitch(_ mode: OverlayMode) {
        guard !self.contentState.isProcessing else { return }
        self.contentState.onOverlayModeSwitchRequested?(mode)
        BottomOverlayModeMenuController.shared.hide()
    }

    private func closeModeMenu() {
        BottomOverlayModeMenuController.shared.hide()
    }

    private func closeActionsMenu() {
        BottomOverlayActionsMenuController.shared.hide()
    }

    private func handleModeSelectorHover(_ hovering: Bool) {
        guard !self.contentState.isProcessing else {
            self.closeModeMenu()
            return
        }
        BottomOverlayModeMenuController.shared.selectorHoverChanged(hovering)
    }

    private func handleModeSelectorFrameChange(_ frameInScreen: CGRect, window: NSWindow?) {
        self.modeSelectorFrameInScreen = frameInScreen
        self.modeSelectorWindow = window
        guard self.layout.showsTopControls, !self.contentState.isProcessing else {
            BottomOverlayModeMenuController.shared.hide()
            return
        }

        BottomOverlayModeMenuController.shared.updateAnchor(
            selectorFrameInScreen: frameInScreen,
            parentWindow: window,
            maxWidth: self.promptSelectorMaxWidth,
            menuGap: self.promptMenuGap
        )
    }

    private func handleActionsSelectorHover(_ hovering: Bool) {
        let actionsDisabled = self.historyStore.entries.isEmpty || self.contentState.isProcessing
        guard !actionsDisabled else {
            self.closeActionsMenu()
            return
        }
        BottomOverlayActionsMenuController.shared.selectorHoverChanged(hovering)
    }

    private func handleActionsSelectorFrameChange(_ frameInScreen: CGRect, window: NSWindow?) {
        self.actionsSelectorFrameInScreen = frameInScreen
        self.actionsSelectorWindow = window
        let actionsDisabled = self.historyStore.entries.isEmpty || self.contentState.isProcessing
        guard self.layout.showsTopControls, !actionsDisabled else {
            BottomOverlayActionsMenuController.shared.hide()
            return
        }

        BottomOverlayActionsMenuController.shared.updateAnchor(
            selectorFrameInScreen: frameInScreen,
            parentWindow: window,
            maxWidth: self.promptSelectorMaxWidth,
            menuGap: self.promptMenuGap
        )
    }

    /// Uppercase micro-label that names a chip. Large canvas only — at medium the
    /// chips have to speak for themselves.
    private func chipCaption(_ text: String) -> some View {
        Text(text)
            .basicsMicroLabel(11)
            .foregroundStyle(BasicsTokens.Dark.faint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var chipChevron: some View {
        Image(systemName: "chevron.up")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(BasicsTokens.Dark.muted)
    }

    private var modeSelectorTrigger: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(self.modeColor)
                .frame(width: 5, height: 5)
            Text(self.modeLabel)
                .basicsLabel(12)
                .foregroundStyle(self.modeInk)
                .lineLimit(1)
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(self.modeInk)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .frame(height: self.chipHeight)
        .background(
            self.modeChipBackground(
                isHovered: self.isHoveringModeChip,
                disabled: self.contentState.isProcessing
            )
        )
    }

    private var modeSelectorView: some View {
        self.modeSelectorTrigger
            .background(
                PromptSelectorAnchorReader { frameInScreen, window in
                    self.handleModeSelectorFrameChange(frameInScreen, window: window)
                }
                .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHoveringModeChip = hovering && !self.contentState.isProcessing
            }
            .onTapGesture {
                guard self.layout.showsTopControls, !self.contentState.isProcessing else { return }
                self.closePromptMenu()
                self.closeActionsMenu()
                BottomOverlayModeMenuController.shared.updateAnchor(
                    selectorFrameInScreen: self.modeSelectorFrameInScreen,
                    parentWindow: self.modeSelectorWindow,
                    maxWidth: self.promptSelectorMaxWidth,
                    menuGap: self.promptMenuGap
                )
                BottomOverlayModeMenuController.shared.toggleFromTap()
            }
    }

    private var promptSelectorTrigger: some View {
        HStack(spacing: 7) {
            Text(self.promptSelectorDisplayLabel)
                .basicsLabel(12)
                .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                .lineLimit(1)
                .truncationMode(.tail)
            if self.isAppPromptOverrideActive {
                OverlayAppBadge()
            }
            self.chipChevron
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .frame(height: self.chipHeight)
        .background(
            self.chipBackground(
                isHovered: self.isHoveringPromptChip,
                disabled: !self.isPromptSelectableMode || self.contentState.isProcessing
            )
        )
    }

    private var promptSelectorView: some View {
        Group {
            if self.isPromptSelectableMode {
                self.promptSelectorTrigger
                    .background(
                        PromptSelectorAnchorReader { frameInScreen, window in
                            self.handlePromptSelectorFrameChange(frameInScreen, window: window)
                        }
                        .allowsHitTesting(false)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        self.isHoveringPromptChip = hovering && !self.contentState.isProcessing
                    }
                    .onTapGesture {
                        guard self.layout.showsTopControls, self.isPromptSelectableMode, !self.contentState.isProcessing else { return }
                        self.closeModeMenu()
                        self.closeActionsMenu()
                        BottomOverlayPromptMenuController.shared.updateAnchor(
                            selectorFrameInScreen: self.promptSelectorFrameInScreen,
                            parentWindow: self.promptSelectorWindow,
                            maxWidth: self.promptSelectorMaxWidth,
                            menuGap: self.promptMenuGap
                        )
                        BottomOverlayPromptMenuController.shared.toggleFromTap()
                    }
            } else {
                self.promptSelectorTrigger
                    .opacity(0.6)
                    .onHover { _ in
                        self.isHoveringPromptChip = false
                    }
            }
        }
    }

    private var actionsSelectorTrigger: some View {
        let actionsDisabled = self.historyStore.entries.isEmpty || self.contentState.isProcessing
        return HStack(spacing: 7) {
            Text("Actions")
                .basicsLabel(12)
                .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                .lineLimit(1)
            self.chipChevron
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .frame(height: self.chipHeight)
        .background(
            self.chipBackground(
                isHovered: self.isHoveringActionsChip,
                disabled: actionsDisabled
            )
        )
        .opacity(actionsDisabled ? 0.45 : 1)
    }

    private var actionsSelectorView: some View {
        let actionsDisabled = self.historyStore.entries.isEmpty || self.contentState.isProcessing
        return self.actionsSelectorTrigger
            .background(
                PromptSelectorAnchorReader { frameInScreen, window in
                    self.handleActionsSelectorFrameChange(frameInScreen, window: window)
                }
                .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHoveringActionsChip = hovering && !actionsDisabled
                self.handleActionsSelectorHover(hovering)
            }
            .onTapGesture {
                guard self.layout.showsTopControls, !actionsDisabled else { return }
                self.closePromptMenu()
                self.closeModeMenu()
                BottomOverlayActionsMenuController.shared.updateAnchor(
                    selectorFrameInScreen: self.actionsSelectorFrameInScreen,
                    parentWindow: self.actionsSelectorWindow,
                    maxWidth: self.promptSelectorMaxWidth,
                    menuGap: self.promptMenuGap
                )
                BottomOverlayActionsMenuController.shared.toggleFromTap()
            }
            .help(
                self.historyStore.entries.isEmpty
                    ? "No saved dictation history available"
                    : "Reprocess the latest dictation using current AI settings"
            )
    }

    private var settingsChip: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(BasicsTokens.Dark.inkSubtle)
            .frame(width: self.chipHeight, height: self.chipHeight)
            .background(
                self.chipBackground(
                    isHovered: self.isHoveringSettingsChip,
                    disabled: false
                )
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHoveringSettingsChip = hovering
            }
            .onTapGesture {
                self.closePromptMenu()
                self.closeModeMenu()
                self.closeActionsMenu()
                self.contentState.onOpenPreferencesRequested?()
            }
            .help("Open Preferences")
    }

    private func failureIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BasicsTokens.Dark.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(BasicsTokens.Dark.iconButton))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var aiProcessingFailureView: some View {
        HStack(spacing: 12) {
            Text(self.contentState.aiProcessingFailureMessage)
                .basicsProse(self.layout.transFontSize)
                .foregroundStyle(
                    self.contentState.canRetryAIProcessingFailure
                        ? BasicsTokens.Dark.ink
                        : BasicsTokens.Dark.warning
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if self.contentState.canRetryAIProcessingFailure {
                self.failureIconButton(systemName: "arrow.clockwise", help: "Try again") {
                    self.contentState.clearAIProcessingFailure()
                    self.contentState.onReprocessLastRequested?()
                }
            }

            self.failureIconButton(systemName: "xmark", help: "Dismiss") {
                self.contentState.clearAIProcessingFailure()
                NotchOverlayManager.shared.hide()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollablePreviewText(_ previewText: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                self.richPreviewText(previewText)
                    .font(BasicsTokens.prose(self.layout.transFontSize))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: previewText) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func dynamicPreviewText(_ previewText: String) -> some View {
        if self.settings.overlaySize == .small {
            self.richPreviewText(previewText)
                .font(BasicsTokens.prose(self.layout.transFontSize))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            self.richPreviewText(previewText)
                .font(BasicsTokens.prose(self.layout.transFontSize))
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .lineLimit(Int(self.previewMaxHeight / max(self.estimatedPreviewLineHeight, 1)))
                .truncationMode(.head)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The 92pt bordered canvas the large overlay reserves for the transcript.
    private func largePreviewCanvas<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(
                maxWidth: .infinity,
                minHeight: self.layout.previewBoxHeight,
                maxHeight: self.layout.previewBoxHeight,
                alignment: .bottomLeading
            )
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                            .strokeBorder(BasicsTokens.Dark.hairline, lineWidth: 1)
                    )
            )
    }

    /// Separator between the waveform row and the preview at small / medium.
    private var previewHairline: some View {
        Rectangle()
            .fill(BasicsTokens.Dark.hairline)
            .frame(height: 1)
    }

    /// Chip row — mode, prompt, actions, and (large only) the gear.
    private var topControlsRow: some View {
        HStack(spacing: self.isCompactControls ? 8 : 10) {
            if !self.isCompactControls {
                self.chipCaption("Mode")
            }
            self.modeSelectorView

            if !self.isCompactControls {
                self.chipCaption("AI prompt")
            }
            self.promptSelectorView

            self.actionsSelectorView

            Spacer(minLength: 8)

            if !self.isCompactControls {
                self.settingsChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Target-app icon (or mode dot), waveform, mode label + engine status.
    private var waveformRow: some View {
        let appIcon = self.displayedAppIcon
        let isWarmingUp = !self.appServices.asr.isAsrReady &&
            (self.appServices.asr.isLoadingModel || self.appServices.asr.isDownloadingModel)
        let showModelLoading = self.layout.showsModeLabel && isWarmingUp

        return HStack(spacing: self.layout.showsLeadingGlyph ? max(self.layout.hPadding / 1.5, 10) : 0) {
            if self.layout.showsLeadingGlyph {
                VStack(spacing: 2) {
                    if showModelLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if let appIcon = appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: self.layout.iconSize, height: self.layout.iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: self.layout.iconSize / 4, style: .continuous))
                    } else if !self.layout.showsModeLabel {
                        Circle()
                            .fill(self.modeColor)
                            .frame(
                                width: max(self.layout.iconSize * 0.45, 7),
                                height: max(self.layout.iconSize * 0.45, 7)
                            )
                    }
                }
                .frame(width: self.layout.iconSize, height: self.layout.iconSize)
                .opacity((appIcon != nil || showModelLoading || !self.layout.showsModeLabel) ? 1 : 0)
            }

            if self.layout.showsModeLabel {
                Spacer(minLength: 8)
            }

            BottomWaveformView(
                color: self.modeColor,
                layout: self.layout,
                isEngineWarmingUp: isWarmingUp
            )
            .frame(width: self.layout.waveformWidth, height: self.layout.waveformHeight)

            if self.layout.showsModeLabel {
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    // At medium and large the mode CHIP already names the mode, so
                    // the label next to the waveform would say it twice.
                    if !self.layout.showsTopControls {
                        Text(self.modeLabel)
                            .basicsLabel(self.layout.modeFontSize)
                            .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if isWarmingUp, self.settings.overlaySize != .small {
                        Text(self.appServices.asr.modelPreparationStatusText)
                            .basicsProse(max(self.layout.modeFontSize - 2, 10))
                            .foregroundStyle(BasicsTokens.Dark.warning)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: self.layout.iconSize, alignment: .trailing)
            }
        }
    }

    /// The 92pt canvas at large: failure row, streaming partials, or the frozen
    /// transcript — whichever the panel is currently carrying.
    @ViewBuilder
    private var fixedCanvasPreviewContent: some View {
        if self.shouldSuppressPreviewDuringRelease {
            Color.clear
        } else if self.shouldShowAIProcessingFailure {
            self.aiProcessingFailureView
        } else if self.shouldShowProcessingPreview {
            self.scrollablePreviewText(self.processingPreviewText)
        } else if self.shouldShowProcessingStatus || self.contentState.isProcessing {
            // The waveform sweep carries processing state; the canvas stays empty.
            Color.clear
        } else if self.hasTranscription, !self.transcriptionPreviewText.isEmpty {
            self.scrollablePreviewText(self.transcriptionPreviewText)
        } else {
            Color.clear
        }
    }

    /// The same content at small / medium, where the panel grows to fit instead
    /// of scrolling inside a fixed box.
    private var dynamicPreviewContent: some View {
        Group {
            if self.shouldSuppressPreviewDuringRelease {
                Color.clear
            } else if self.shouldShowAIProcessingFailure {
                self.aiProcessingFailureView
            } else if self.shouldShowProcessingPreview {
                self.dynamicPreviewText(self.processingPreviewText)
            } else if self.hasTranscription, !self.contentState.isProcessing,
                      !self.transcriptionPreviewText.isEmpty
            {
                self.dynamicPreviewText(self.transcriptionPreviewText)
            } else {
                Color.clear
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DynamicPreviewHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .frame(
            maxWidth: .infinity,
            minHeight: self.effectiveDynamicPreviewMinHeight,
            maxHeight: self.effectiveDynamicPreviewLockedHeight,
            alignment: .leading
        )
    }

    /// Panel ground. Pill keeps its own darker body and the rotating rim; every
    /// other size is the flat card with a single hairline border.
    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: self.layout.cornerRadius, style: .continuous)
                .fill(self.isPillSize ? BasicsTokens.Dark.panel : BasicsTokens.Dark.card)
                .shadow(
                    color: Color.black.opacity(self.isPillSize ? 0.55 : 0.52),
                    radius: self.isPillSize ? PillShadowMetrics.radius : 32,
                    x: 0,
                    y: self.isPillSize ? PillShadowMetrics.yOffset : 12
                )

            if self.isPillSize {
                // A bright highlight that slowly rotates around the edge. Paused
                // under reduce-motion to avoid continuous redraws.
                if self.reduceMotion || !self.contentState.isBottomOverlayPresented {
                    RoundedRectangle(cornerRadius: self.layout.cornerRadius, style: .continuous)
                        .strokeBorder(Self.pillRimGradient(angle: 0), lineWidth: 1.2)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let seconds = max(
                            0,
                            timeline.date.timeIntervalSince(self.borderAnimationStartedAt ?? timeline.date)
                        )
                        let angle = (seconds.truncatingRemainder(dividingBy: 6.0) / 6.0) * 360.0
                        RoundedRectangle(cornerRadius: self.layout.cornerRadius, style: .continuous)
                            .strokeBorder(Self.pillRimGradient(angle: angle), lineWidth: 1.2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: self.layout.cornerRadius, style: .continuous)
                    .strokeBorder(BasicsTokens.Dark.border, lineWidth: 1)
            }
        }
    }

    private static func pillRimGradient(angle: Double) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(0.06), location: 0.00),
                .init(color: .white.opacity(0.55), location: 0.13),
                .init(color: .white.opacity(0.10), location: 0.30),
                .init(color: .white.opacity(0.03), location: 0.55),
                .init(color: .white.opacity(0.22), location: 0.80),
                .init(color: .white.opacity(0.06), location: 1.00),
            ]),
            center: .center,
            angle: .degrees(angle)
        )
    }

    var body: some View {
        VStack(alignment: self.isPillSize ? .center : .leading, spacing: self.layout.contentGap) {
            if self.layout.showsTopControls {
                self.topControlsRow
            }

            // The large canvas is a fixed 288pt, so the three rows push apart
            // instead of stacking at the top.
            if self.layout.usesFixedCanvas {
                Spacer(minLength: 0)
            }

            self.waveformRow

            if self.layout.usesFixedCanvas {
                Spacer(minLength: 0)
            }

            if self.shouldReservePreviewArea {
                if self.layout.usesFixedCanvas {
                    self.largePreviewCanvas {
                        self.fixedCanvasPreviewContent
                    }
                } else {
                    self.previewHairline
                    self.dynamicPreviewContent
                }
            }
        }
        .padding(.horizontal, self.layout.hPadding)
        .padding(.vertical, self.layout.vPadding)
        .frame(maxWidth: .infinity, alignment: self.isPillSize ? .center : .leading)
        .background(self.panelBackground)
        .transaction { transaction in
            if self.shouldSuppressPreviewDuringRelease {
                transaction.animation = nil
            }
        }
        .frame(
            width: self.layout.usesFixedCanvas ? self.layout.overlayWidth : self.layout.containerWidth,
            height: self.overlayFrameHeight,
            alignment: .top
        )
        // Reserve space around the tab so its drop shadow isn't clipped by the (content-sized) window.
        .padding(self.isPillSize ? PillShadowMetrics.shadowPad : 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .scaleEffect(self.overlayAnimatedScale, anchor: .center)
        .offset(y: self.overlayAnimatedOffsetY)
        .opacity(self.overlayAnimatedOpacity)
        .animation(.timingCurve(0.22, 0.0, 0.2, 1.0, duration: 0.02), value: self.contentState.isBottomOverlayDismissing)
        .onChange(of: self.settings.overlaySize) { _, _ in
            self.dynamicPreviewResizeBucket = self.previewResizeBucket(for: self.currentPreviewSizingText)
            self.frozenDynamicPreviewHeight = nil
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onChange(of: self.contentState.isBottomOverlayPresented) { _, presented in
            self.borderAnimationStartedAt = presented ? Date() : nil
        }
        .onChange(of: self.settings.enableStreamingPreview) { _, _ in
            self.dynamicPreviewResizeBucket = self.previewResizeBucket(for: self.currentPreviewSizingText)
            self.frozenDynamicPreviewHeight = nil
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onChange(of: self.contentState.cachedPreviewText) { _, _ in
            self.refreshDynamicPreviewSizeIfNeeded(for: self.currentPreviewSizingText)
        }
        .onChange(of: self.contentState.mode) { _, _ in
            if !self.isPromptSelectableMode || self.contentState.isProcessing {
                self.closePromptMenu()
            }
            self.closeModeMenu()
            self.closeActionsMenu()
            self.isHoveringModeChip = false
            self.isHoveringPromptChip = false
            self.isHoveringActionsChip = false
            self.isHoveringSettingsChip = false
            switch self.contentState.mode {
            case .dictation: self.contentState.promptPickerMode = .dictate
            case .edit, .write, .rewrite: self.contentState.promptPickerMode = .edit
            case .command: break
            }
            if !self.layout.usesFixedCanvas {
                self.dynamicPreviewResizeBucket = self.previewResizeBucket(for: self.currentPreviewSizingText)
                BottomOverlayWindowController.shared.refreshSizeForContent()
            }
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            self.processingStatusVisible = processing
            if processing {
                self.closePromptMenu()
                self.closeModeMenu()
                self.closeActionsMenu()
            }
            self.isHoveringModeChip = false
            self.isHoveringPromptChip = false
            self.isHoveringActionsChip = false
            self.isHoveringSettingsChip = false
            if !self.layout.usesFixedCanvas {
                self.refreshDynamicPreviewSizeIfNeeded(for: self.currentPreviewSizingText)
            }
        }
        .onChange(of: self.contentState.isAIProcessingFailureVisible) { _, _ in
            guard !self.layout.usesFixedCanvas else { return }
            self.refreshDynamicPreviewSizeIfNeeded(for: self.currentPreviewSizingText)
        }
        .onChange(of: self.processingStatusVisible) { _, _ in
            guard !self.layout.usesFixedCanvas else { return }
            self.refreshDynamicPreviewSizeIfNeeded(for: self.currentPreviewSizingText)
        }
        .onChange(of: self.contentState.isBottomOverlayReleaseTransitioning) { _, transitioning in
            guard self.shouldReservePreviewArea else {
                self.frozenDynamicPreviewHeight = nil
                return
            }
            guard !self.layout.usesFixedCanvas else { return }
            if transitioning {
                let measuredHeight = self.dynamicPreviewMeasuredHeight > 0
                    ? self.dynamicPreviewMeasuredHeight
                    : self.effectiveDynamicPreviewMinHeight
                self.frozenDynamicPreviewHeight = max(measuredHeight, self.dynamicPreviewBaseMinHeight)
            } else {
                self.frozenDynamicPreviewHeight = nil
                BottomOverlayWindowController.shared.refreshSizeForContent()
            }
        }
        .onPreferenceChange(DynamicPreviewHeightPreferenceKey.self) { measuredHeight in
            guard !self.layout.usesFixedCanvas else { return }
            guard measuredHeight > 0 else { return }
            self.dynamicPreviewMeasuredHeight = measuredHeight
        }
        .onAppear {
            self.rememberAppIcon(self.contentState.targetAppIcon ?? self.activeAppMonitor.activeAppIcon)
            self.dynamicPreviewResizeBucket = self.previewResizeBucket(for: self.currentPreviewSizingText)
        }
        .onReceive(self.contentState.$targetAppIcon) { icon in
            self.rememberAppIcon(icon)
        }
        .onDisappear {
            self.closePromptMenu()
            self.closeModeMenu()
            self.closeActionsMenu()
            self.isHoveringModeChip = false
            self.isHoveringPromptChip = false
            self.isHoveringActionsChip = false
            self.isHoveringSettingsChip = false
        }
        // TODO: Add tap-to-expand for command mode history (future enhancement)
        // .contentShape(Rectangle())
        // .onTapGesture {
        //     if contentState.mode == .command && !contentState.commandConversationHistory.isEmpty {
        //         NotchOverlayManager.shared.onNotchClicked?()
        //     }
        // }
    }
}

// MARK: - Bottom Waveform View (reads from NotchContentState)

struct BottomWaveformView: View {
    let color: Color
    let layout: BottomOverlayView.LayoutConstants
    /// Engine still downloading or loading — the bars go inert rather than
    /// pretending to listen.
    var isEngineWarmingUp: Bool = false

    @ObservedObject private var contentState = NotchContentState.shared
    // Initialize with max possible bar count (11 for large) to prevent index-out-of-range before onAppear
    @State private var barHeights: [CGFloat] = Array(repeating: 6, count: 11)
    @State private var noiseThreshold: CGFloat = .init(SettingsStore.shared.visualizerNoiseThreshold)

    private var barCount: Int {
        self.layout.barCount
    }

    private var barWidth: CGFloat {
        self.layout.barWidth
    }

    private var barSpacing: CGFloat {
        self.layout.barSpacing
    }

    private var minHeight: CGFloat {
        self.layout.minBarHeight
    }

    private var maxHeight: CGFloat {
        self.layout.maxBarHeight
    }

    private var isPillStyle: Bool {
        !self.layout.showsModeLabel
    }

    private var isProcessingVisualActive: Bool {
        self.contentState.isProcessing || self.isReleaseAnimationActive
    }

    private var currentGlowIntensity: CGFloat {
        if self.isPillStyle || self.isEngineWarmingUp {
            return 0.0
        }
        return self.isProcessingVisualActive ? 0.0 : 0.35
    }

    private var currentGlowRadius: CGFloat {
        if self.isPillStyle || self.isEngineWarmingUp {
            return 0.0
        }
        return self.isProcessingVisualActive ? 0.0 : 4
    }

    private var barFillColor: Color {
        if self.isEngineWarmingUp {
            return BasicsTokens.Dark.barInert
        }
        if self.isProcessingVisualActive {
            return BasicsTokens.Dark.barProcessing
        }
        // The tab dropped its icon and label, so the bars are the only thing
        // left that can say which mode is running — they carry the mode colour
        // at every size now.
        return self.color
    }

    private var isReleaseAnimationActive: Bool {
        self.contentState.isBottomOverlayReleaseTransitioning || self.contentState.isBottomOverlayDismissing
    }

    /// Safe accessor for bar heights to prevent index-out-of-range crashes
    private func safeBarHeight(at index: Int) -> CGFloat {
        guard index >= 0 && index < self.barHeights.count else {
            return self.minHeight
        }
        return self.barHeights[index]
    }

    var body: some View {
        ZStack {
            self.barsView
                .foregroundStyle(self.barFillColor)

            if self.isProcessingVisualActive {
                CompositorShimmerSweep(duration: 1.05, peakOpacity: 0.9)
                    .mask {
                        self.barsView
                    }
                    .shadow(color: .white.opacity(0.28), radius: 2.5, x: 0, y: 0)
            }
        }
        .onChange(of: self.contentState.bottomOverlayAudioLevel) { _, level in
            guard !self.isReleaseAnimationActive else { return }
            if !self.contentState.isProcessing {
                self.updateBars(level: level)
            }
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            guard !self.isReleaseAnimationActive else { return }
            if processing {
                self.setFlatProcessingBars()
            } else {
                // Resume from silence; next audio tick will animate up.
                self.updateBars(level: 0)
            }
        }
        .onChange(of: self.layout.barCount) { _, newCount in
            self.barHeights = Array(repeating: self.minHeight, count: newCount)
        }
        .onAppear {
            // Ensure bar count matches current layout
            if self.barHeights.count != self.barCount {
                self.barHeights = Array(repeating: self.minHeight, count: self.barCount)
            }
            if self.isReleaseAnimationActive {
                self.barHeights = Array(repeating: self.minHeight, count: self.barCount)
            } else if self.contentState.isProcessing {
                self.setFlatProcessingBars()
            } else {
                self.updateBars(level: 0)
            }
        }
        .onDisappear {
            // No timers to clean up.
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when user changes sensitivity setting
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != self.noiseThreshold {
                self.noiseThreshold = newThreshold
            }
        }
    }

    private var barsView: some View {
        HStack(spacing: self.barSpacing) {
            ForEach(0..<self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: self.barWidth / 2)
                    .frame(width: self.barWidth, height: self.displayHeight(at: index))
                    .shadow(
                        color: self.color.opacity(self.isReleaseAnimationActive ? 0 : self.currentGlowIntensity),
                        radius: self.isReleaseAnimationActive ? 0 : self.currentGlowRadius,
                        x: 0,
                        y: 0
                    )
            }
        }
    }

    private func displayHeight(at index: Int) -> CGFloat {
        if self.isReleaseAnimationActive || self.contentState.isProcessing || self.isEngineWarmingUp {
            return self.minHeight
        }
        return self.safeBarHeight(at: index)
    }

    private func visualizerPeakHeight(at index: Int) -> CGFloat {
        let centerDistance = abs(CGFloat(index) - CGFloat(self.barCount - 1) / 2)
        let maxDistance = max(CGFloat(self.barCount - 1) / 2, 1)
        let normalizedDistance = min(centerDistance / maxDistance, 1)
        let floor = self.layout.barPeakFloor
        let factor = max(floor, 0.96 - normalizedDistance * (0.96 - floor))
        return self.minHeight + (self.maxHeight - self.minHeight) * factor
    }

    private func setFlatProcessingBars() {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        // During AI processing we want the visualizer to settle to silence (flat).
        withAnimation(.easeOut(duration: 0.18)) {
            for i in 0..<self.barCount {
                self.barHeights[i] = self.minHeight
            }
        }
    }

    private func updateBars(level: CGFloat) {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        let normalizedLevel = min(max(level, 0), 1)
        let denominator = max(1.0 - self.noiseThreshold, 0.001)
        let adjustedLevel = max(min((normalizedLevel - self.noiseThreshold) / denominator, 1.0), 0.0)
        // Lower exponent => normal speech pushes the bars higher (taller "waves" while talking).
        let amplifiedLevel = pow(adjustedLevel, 0.55)

        withAnimation(.easeOut(duration: 0.08)) {
            for i in 0..<self.barCount {
                let peakHeight = self.visualizerPeakHeight(at: i)
                let variation = 0.92 + 0.08 * cos(CGFloat(i) * 1.45)
                let nextHeight = self.minHeight + (peakHeight - self.minHeight) * amplifiedLevel * variation
                self.barHeights[i] = min(self.maxHeight, max(self.minHeight, nextHeight))
            }
        }
    }
}
