import AppKit
import Combine
import PromiseKit
import SwiftUI

enum MenuBarNavigationDestination: String {
    case customDictionary
    case preferences
}

@MainActor
final class MenuBarManager: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isSetup: Bool = false
    private var hostedWindow: NSWindow?

    // Cached menu items to avoid rebuilding entire menu
    private var statusMenuItem: NSMenuItem?
    private var copyLastTranscriptMenuItem: NSMenuItem?
    private var rollbackMenuItem: NSMenuItem?
    private var microphoneMenuItem: NSMenuItem?
    private var microphoneSubmenu: NSMenu?

    // References to app state
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()

    /// Overlay management (persistent, independent of window lifecycle)
    private var overlayVisible: Bool = false {
        didSet { self.updateNotchHUDSuppression() }
    }

    /// Track when AI processing is active.
    /// When recording stops, ASRService flips `isRunning` to false, which would normally hide the
    /// overlay. During post-processing we want the overlay to stay visible until processing ends.
    private var isProcessingActive: Bool = false {
        didSet {
            self.updateNotchHUDSuppression()
            // The menu-bar mark and the menu's status row both read this, so a
            // refining pass has to repaint them the way recording does.
            guard oldValue != self.isProcessingActive else { return }
            self.updateMenuBarIcon()
            self.updateMenu()
        }
    }

    /// The persistent notch task HUD must yield the notch to the recording
    /// overlay whenever the overlay is (or is about to be) on screen at the
    /// TOP position. `didSet` on the two state vars above covers every
    /// mutation site without sprinkling calls through the show/hide paths.
    /// Bottom-position overlay users keep the HUD visible throughout.
    private func updateNotchHUDSuppression() {
        let overlayOwnsNotch = SettingsStore.shared.overlayPosition == .top
            && (self.overlayVisible || self.isProcessingActive || NotchOverlayManager.shared.isCommandOutputExpanded)
        NotchHUDController.active?.setSuppressed(overlayOwnsNotch)
    }

    @Published var isRecording: Bool = false

    /// One-shot navigation requests from the menu bar into the main window UI.
    /// `ContentView` consumes this and clears it.
    @Published var requestedNavigationDestination: MenuBarNavigationDestination? = nil

    /// Track current overlay mode for notch
    private var currentOverlayMode: OverlayMode = .dictation

    // Track pending overlay operations to prevent spam
    private var pendingShowOperation: DispatchWorkItem?
    private var pendingHideOperation: DispatchWorkItem?
    private var pendingProcessingShowOperation: DispatchWorkItem?
    /// Show immediately so users see the processing state right away.
    private let processingVisualDelay: DispatchTimeInterval = .milliseconds(0)
    /// Legacy debounce used by generic processing callers. Successful dictation
    /// completion dispatches output first, then hides the overlay asynchronously.
    private let processingHideDelay: DispatchTimeInterval = .milliseconds(80)

    /// Subscription for forwarding audio levels to expanded command notch
    private var expandedModeAudioSubscription: AnyCancellable?

    func initializeMenuBar() {
        guard !self.isSetup else { return }

        // Ensure we're on main thread and app is active
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBarSafely()
        }
    }

    deinit {
        statusItem = nil
    }

    func configure(asrService: ASRService) {
        self.asrService = asrService
        if SettingsStore.shared.overlayPosition == .bottom {
            DispatchQueue.main.async {
                guard SettingsStore.shared.overlayPosition == .bottom else { return }
                BottomOverlayWindowController.shared.prepare()
            }
        }
        NotificationCenter.default.publisher(for: NSNotification.Name("OverlayPositionChanged"))
            .receive(on: DispatchQueue.main)
            .sink { _ in
                guard SettingsStore.shared.overlayPosition == .bottom else { return }
                BottomOverlayWindowController.shared.prepare()
            }
            .store(in: &self.cancellables)

        // Subscribe to recording state changes
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isRecording = isRunning
                self?.updateMenuBarIcon()
                self?.updateMenu()

                // Handle overlay lifecycle (independent of window state)
                self?.handleOverlayState(isRunning: isRunning, asrService: asrService)
            }
            .store(in: &self.cancellables)

        // Subscribe to partial transcription updates for streaming preview
        asrService.$partialTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard self != nil else { return }
                if NotchOverlayManager.shared.shouldShowOrTrackLivePreviewText {
                    NotchOverlayManager.shared.updateTranscriptionText(newText)
                }
            }
            .store(in: &self.cancellables)
    }

    private func handleOverlayState(isRunning: Bool, asrService: ASRService) {
        self.overlayBench("handle_state isRunning=\(isRunning) overlayVisible=\(self.overlayVisible) processing=\(self.isProcessingActive) mode=\(self.currentOverlayMode.rawValue)")

        // Dictionary training owns its recording controls, so showing the
        // regular dictation notch here would create two competing overlays.
        if asrService.isDictionaryTrainingCaptureActive {
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil
            if self.overlayVisible {
                self.overlayVisible = false
                NotchOverlayManager.shared.hide()
            }
            return
        }

        // Don't hide the overlay while AI processing is active.
        // Without this, the notch can disappear during the short "Refining..." phase because
        // `isRunning` becomes false before post-processing completes.
        if !isRunning, self.isProcessingActive {
            self.overlayBench("handle_state_return reason=processing_active")
            return
        }

        // Prevent rapid state changes that could cause cycles
        guard self.overlayVisible != isRunning else {
            self.overlayBench("handle_state_return reason=visibility_unchanged")
            return
        }

        if isRunning {
            // Cancel any pending hide operation
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil

            self.overlayVisible = true
            self.overlayBench("show_request mode=\(self.currentOverlayMode.rawValue)")

            // If expanded command output is showing, check if we should keep it or close it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Only keep expanded notch if this is a command mode recording (follow-up)
                // For other modes (dictation, rewrite), close it and show regular notch
                if self.currentOverlayMode == .command, NotchOverlayManager.shared.supportsCommandNotchUI {
                    // Enable recording visualization in the expanded notch
                    NotchContentState.shared.setRecordingInExpandedMode(true)

                    // Subscribe to audio levels and forward to expanded notch
                    self.expandedModeAudioSubscription = asrService.audioLevelPublisher
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            NotchContentState.shared.updateExpandedModeAudioLevel(level)
                        }

                    self.pendingShowOperation = nil
                    return
                } else {
                    // Close expanded command notch to transition to regular notch
                    NotchOverlayManager.shared.hideExpandedCommandOutput()
                }
            }

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.overlayVisible else { return }

                // Double-check expanded notch isn't showing (could have changed during delay)
                // But only block if we're in command mode
                if NotchOverlayManager.shared.isCommandOutputExpanded,
                   self.currentOverlayMode == .command,
                   NotchOverlayManager.shared.supportsCommandNotchUI
                {
                    self.pendingShowOperation = nil
                    return
                }

                // Show notch overlay
                self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
                NotchOverlayManager.shared.show(
                    audioLevelPublisher: asrService.audioLevelPublisher,
                    mode: self.currentOverlayMode
                )
                self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")

                self.pendingShowOperation = nil
            }
            self.pendingShowOperation = showItem
            DispatchQueue.main.async(execute: showItem)
        } else {
            // Cancel any pending show operation
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil

            self.overlayVisible = false
            self.overlayBench("hide_request delayMs=30")

            // If expanded command output is showing, don't hide it - let it stay visible
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Stop recording visualization in expanded notch
                NotchContentState.shared.setRecordingInExpandedMode(false)
                self.expandedModeAudioSubscription?.cancel()
                self.expandedModeAudioSubscription = nil

                self.pendingHideOperation = nil
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                // Hide notch overlay
                self.overlayBench("hide_workitem_execute")
                NotchOverlayManager.shared.hide()
                self.overlayBench("hide_workitem_return")

                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30), execute: hideItem)
        }
    }

    func showRecordingOverlayImmediately() {
        AutomaticDictionaryCorrectionTracker.shared.cancel()

        guard let asrService else {
            self.overlayBench("instant_show_return reason=no_asr_service")
            return
        }

        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil

        guard !self.overlayVisible else {
            self.overlayBench("instant_show_return reason=already_visible")
            return
        }

        self.overlayVisible = true
        self.overlayBench("instant_show_request mode=\(self.currentOverlayMode.rawValue)")

        if NotchOverlayManager.shared.isCommandOutputExpanded {
            if self.currentOverlayMode == .command, NotchOverlayManager.shared.supportsCommandNotchUI {
                NotchContentState.shared.setRecordingInExpandedMode(true)
                self.expandedModeAudioSubscription = asrService.audioLevelPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { level in
                        NotchContentState.shared.updateExpandedModeAudioLevel(level)
                    }
                return
            }
            NotchOverlayManager.shared.hideExpandedCommandOutput()
        }

        self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
        NotchOverlayManager.shared.show(
            audioLevelPublisher: asrService.audioLevelPublisher,
            mode: self.currentOverlayMode
        )
        self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")
    }

    func hideRecordingOverlayImmediately(reason: String) {
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil

        guard !self.isProcessingActive else {
            self.overlayBench("instant_hide_return reason=\(reason) processing_active")
            return
        }

        guard self.overlayVisible else {
            self.overlayBench("instant_hide_return reason=\(reason) already_hidden")
            return
        }

        self.overlayVisible = false
        self.overlayBench("instant_hide_request reason=\(reason)")

        if NotchOverlayManager.shared.isCommandOutputExpanded {
            NotchContentState.shared.setRecordingInExpandedMode(false)
            self.expandedModeAudioSubscription?.cancel()
            self.expandedModeAudioSubscription = nil
            self.overlayBench("instant_hide_return reason=expanded_command_output")
            return
        }

        NotchOverlayManager.shared.hide()
        self.overlayBench("instant_hide_return")
    }

    // MARK: - Public API for overlay management

    func updateOverlayTranscription(_ text: String) {
        NotchOverlayManager.shared.updateTranscriptionText(text)
    }

    func setOverlayMode(_ mode: OverlayMode) {
        self.overlayBench("set_mode mode=\(mode.rawValue)")
        self.currentOverlayMode = mode
        NotchOverlayManager.shared.setMode(mode)
    }

    func setProcessing(_ processing: Bool) {
        self.overlayBench("set_processing_request processing=\(processing) overlayVisible=\(self.overlayVisible) active=\(self.isProcessingActive)")

        // Track processing state to prevent hide during AI refinement
        self.isProcessingActive = processing
        self.updateMenuItemsText()

        if processing {
            self.pendingProcessingShowOperation?.cancel()
            // Cancel any pending hide - we want to keep the overlay visible for AI processing
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil
            self.overlayVisible = true

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isProcessingActive else { return }
                self.overlayBench("processing_show_workitem_execute delayMs=0")
                NotchOverlayManager.shared.setProcessing(true)
                self.overlayBench("processing_show_workitem_return")
                self.pendingProcessingShowOperation = nil
            }
            self.pendingProcessingShowOperation = showItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingVisualDelay, execute: showItem)
        } else {
            self.pendingProcessingShowOperation?.cancel()
            self.pendingProcessingShowOperation = nil
            // When processing ends, schedule the hide (unless expanded output is showing)
            self.overlayVisible = false

            // If expanded command output is showing, don't hide it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                self.pendingHideOperation = nil
                NotchOverlayManager.shared.setProcessing(processing)
                self.overlayBench("set_processing_return reason=expanded_command_output")
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                self.overlayBench("processing_hide_workitem_execute delayMs=80")
                NotchOverlayManager.shared.hide()
                self.overlayBench("processing_hide_workitem_return")
                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingHideDelay, execute: hideItem)
            NotchOverlayManager.shared.setProcessing(false)
            self.overlayBench("processing_forwarded processing=false hideDelayMs=80")
            return
        }
    }

    /// Ends processing and waits for the recording overlay's exit transition.
    /// Output paths normally call this asynchronously after insertion dispatch
    /// so the exit animation cannot delay text delivery.
    func finishProcessingAndHideOverlay() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        self.cancelPendingProcessingCompletionOperations()
        self.isProcessingActive = false
        self.overlayVisible = false

        NotchOverlayManager.shared.setProcessing(false)
        self.overlayBench("finish_hide_request")
        let hideOutcome = await NotchOverlayManager.shared.hideAndWait()
        self.overlayBench(
            "finish_hide_complete outcome=\(hideOutcome) elapsedMs=\(Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))"
        )
    }

    /// Ends processing without dismissing an actionable overlay, such as the
    /// AI fallback state that offers reprocessing and settings actions.
    func finishProcessingKeepingOverlayVisible() {
        self.cancelPendingProcessingCompletionOperations()
        self.isProcessingActive = false
        // Keep the physical overlay visible, but release recording/processing
        // ownership so the next recording can establish a fresh lifecycle.
        self.overlayVisible = false
        NotchOverlayManager.shared.setProcessing(false)
        self.overlayBench("finish_keep_visible")
    }

    private func cancelPendingProcessingCompletionOperations() {
        self.pendingProcessingShowOperation?.cancel()
        self.pendingProcessingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil
    }

    private func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: "manager \(message)", source: "OverlayBenchmark")
    }

    private func setupMenuBarSafely() {
        do {
            try self.setupMenuBar()
            self.isSetup = true
        } catch {
            // If setup fails, retry after delay
            DebugLogger.shared.error("MenuBar setup failed, retrying: \(error)", source: "MenuBarManager")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupMenuBarSafely()
            }
        }
    }

    private func setupMenuBar() throws {
        // Ensure we're not already set up
        guard !self.isSetup else { return }

        // Variable length, not square: the recording and refining marks are the
        // tile PLUS a trailing glyph, so the item has to be allowed to grow.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            throw NSError(domain: "MenuBarManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create status item"])
        }

        // Set initial icon
        self.updateMenuBarIcon()

        // Create menu
        self.menu = NSMenu()
        self.menu?.autoenablesItems = false
        self.menu?.delegate = self
        statusItem.menu = self.menu

        self.updateMenu()
    }

    /// What the status item is currently saying. Recording wins over refining
    /// because capture is the state the user can still act on.
    private var menuBarIconState: MenuBarIconGenerator.State {
        if self.isRecording { return .recording }
        if self.isProcessingActive { return .refining }
        return .idle
    }

    private func updateMenuBarIcon() {
        guard let statusItem = statusItem else { return }

        // Drawn, not shipped as a PNG: the mark changes SHAPE per state, and a
        // template image has no colour of its own to change instead.
        statusItem.button?.image = MenuBarIconGenerator.image(for: self.menuBarIconState)
    }

    private func buildMenuStructure() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        // Status indicator with hotkey info
        self.statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        self.statusMenuItem?.isEnabled = false
        if let statusItem = statusMenuItem {
            menu.addItem(statusItem)
        }

        let copyLastTranscriptItem = NSMenuItem(
            title: "Copy last transcript",
            action: #selector(copyLastTranscript(_:)),
            keyEquivalent: ""
        )
        copyLastTranscriptItem.target = self
        menu.addItem(copyLastTranscriptItem)
        self.copyLastTranscriptMenuItem = copyLastTranscriptItem

        menu.addItem(.separator())

        // Open Main Window
        let openItem = NSMenuItem(title: "Open Basics Voice", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Preferences
        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        let customDictionaryItem = NSMenuItem(
            title: "Dictionary",
            action: #selector(openCustomDictionary),
            keyEquivalent: ""
        )
        customDictionaryItem.target = self
        menu.addItem(customDictionaryItem)

        let microphoneSubmenu = NSMenu(title: "Microphone")
        let microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = microphoneSubmenu
        menu.addItem(microphoneMenuItem)
        self.microphoneMenuItem = microphoneMenuItem
        self.microphoneSubmenu = microphoneSubmenu

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let rollbackMenuItem = NSMenuItem(
            title: "Roll back to previous version…",
            action: #selector(rollbackToPreviousVersion(_:)),
            keyEquivalent: ""
        )
        rollbackMenuItem.target = self
        rollbackMenuItem.isEnabled = SimpleUpdater.shared.hasRollbackBackup()
        menu.addItem(rollbackMenuItem)
        self.rollbackMenuItem = rollbackMenuItem

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Basics Voice",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Now update the text content
        self.updateMenuItemsText()
    }

    private func updateMenu() {
        // If menu structure hasn't been built yet, build it
        if self.statusMenuItem == nil {
            self.buildMenuStructure()
        } else {
            // Just update the text of existing items
            self.updateMenuItemsText()
        }
    }

    private func updateMenuItemsText() {
        // Status, then the shortcut on the same line behind a middot. Three
        // states, matching the three menu-bar marks.
        let stateLabel: String
        switch self.menuBarIconState {
        case .idle: stateLabel = "Ready to record"
        case .recording: stateLabel = "Recording"
        case .refining: stateLabel = "Refining"
        }
        let hotkeyDisplay = SettingsStore.shared.primaryDictationShortcutDisplayString
        self.statusMenuItem?.title = hotkeyDisplay.isEmpty
            ? stateLabel
            : "\(stateLabel) · \(hotkeyDisplay)"
        self.copyLastTranscriptMenuItem?.isEnabled = self.canCopyLastTranscript
        self.microphoneMenuItem?.isEnabled = true

        // Update rollback availability text
        self.rollbackMenuItem?.isEnabled = SimpleUpdater.shared.hasRollbackBackup()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            self.updateMenuItemsText()
            self.refreshMicrophoneMenu()
        }
    }

    private func refreshMicrophoneMenu() {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()
        // One faint row rather than an empty menu, so the submenu never renders
        // at zero height while devices are being enumerated.
        let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        submenu.addItem(loadingItem)

        DispatchQueue.global(qos: .userInitiated).async {
            let inputDevices = AudioDevice.listInputDevices()
            let defaultInputUID = AudioDevice.getDefaultInputDevice()?.uid

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.populateMicrophoneMenu(
                    inputDevices: inputDevices,
                    defaultInputUID: defaultInputUID
                )
            }
        }
    }

    private func populateMicrophoneMenu(inputDevices: [AudioDevice.Device], defaultInputUID: String?) {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()

        guard !inputDevices.isEmpty else {
            let emptyItem = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        let followSystemItem = NSMenuItem(
            title: "Use macOS default microphone",
            action: #selector(toggleMicrophoneSelectionMode(_:)),
            keyEquivalent: ""
        )
        followSystemItem.target = self
        followSystemItem.state = SettingsStore.shared.microphoneSelectionMode == .system ? .on : .off
        followSystemItem.isEnabled = !self.isRecording
        submenu.addItem(followSystemItem)
        submenu.addItem(.separator())

        let currentUID = self.currentPreferredInputUID(defaultInputUID: defaultInputUID)

        for device in inputDevices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            // The system-default device keeps its label, but as a quiet tag on
            // the trailing lane instead of a "(System Default)" suffix that
            // pushed long device names off the panel.
            if device.uid == defaultInputUID {
                item.attributedTitle = Self.deviceTitle(device.name, taggedWith: "SYSTEM")
            }
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == currentUID ? .on : .off
            item.isEnabled = !self.isRecording
            submenu.addItem(item)
        }

        if self.isRecording {
            submenu.addItem(.separator())
            let recordingItem = NSMenuItem(title: "Unavailable while recording", action: nil, keyEquivalent: "")
            recordingItem.isEnabled = false
            submenu.addItem(recordingItem)
        }
    }

    /// A device row with a right-aligned micro tag. The tab stop is what puts
    /// every tag in one lane no matter how long the device names are.
    private static func deviceTitle(_ name: String, taggedWith tag: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 220)]

        let title = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .paragraphStyle: paragraph,
            ]
        )
        title.append(NSAttributedString(
            string: "\t\(tag)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.8,
                .paragraphStyle: paragraph,
            ]
        ))
        return title
    }

    private func currentPreferredInputUID(defaultInputUID: String?) -> String? {
        switch SettingsStore.shared.microphoneSelectionMode {
        case .system:
            return defaultInputUID
        case .manual:
            return SettingsStore.shared.preferredInputDeviceUID ?? defaultInputUID
        }
    }

    private var canCopyLastTranscript: Bool {
        !self.isProcessingActive && TranscriptionHistoryStore.shared.latestClipboardText != nil
    }

    @objc private func copyLastTranscript(_ sender: Any?) {
        guard self.canCopyLastTranscript,
              let text = TranscriptionHistoryStore.shared.latestClipboardText
        else {
            DebugLogger.shared.info("Menu action: Copy last transcript requested but history is empty", source: "MenuBarManager")
            return
        }

        _ = ClipboardService.copyToClipboard(text)
        DebugLogger.shared.info("Menu action: Copied latest transcription to clipboard", source: "MenuBarManager")
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard self.isRecording == false else { return }
        guard let uid = sender.representedObject as? String, !uid.isEmpty else { return }

        SettingsStore.shared.recordInputDeviceSelection(uid)
        if SettingsStore.shared.shouldSyncInputSelectionToSystemDefault() {
            _ = AudioDevice.setDefaultInputDevice(uid: uid)
        }

        self.refreshMicrophoneMenu()
    }

    @objc private func toggleMicrophoneSelectionMode(_ sender: NSMenuItem) {
        guard self.isRecording == false else { return }

        let nextMode: SettingsStore.MicrophoneSelectionMode =
            SettingsStore.shared.microphoneSelectionMode == .system ? .manual : .system
        let currentSystemInputUID = AudioDevice.getDefaultInputDevice()?.uid
        let availableInputUIDs = Set(AudioDevice.listInputDevices().map(\.uid))
        let restoredSystemInputUID = SettingsStore.shared.setMicrophoneSelectionMode(
            nextMode,
            currentSystemInputUID: currentSystemInputUID,
            availableInputUIDs: availableInputUIDs
        )

        let preferredInputUID = SettingsStore.shared.preferredInputDeviceUID ?? ""
        if nextMode == .manual,
           preferredInputUID.isEmpty,
           let defaultUID = currentSystemInputUID
        {
            SettingsStore.shared.preferredInputDeviceUID = defaultUID
        }

        if nextMode == .system, let restoredSystemInputUID {
            _ = AudioDevice.setDefaultInputDevice(uid: restoredSystemInputUID)
        }

        self.refreshMicrophoneMenu()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        DebugLogger.shared.info("🔎 Menu action: Check for Updates…", source: "MenuBarManager")

        // Call the AppDelegate's manual update check method if available
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.checkForUpdatesManually()
            return
        }

        // Fallback: perform direct, tolerant check so the menu item always does something
        Task { @MainActor in
            do {
                try await SimpleUpdater.shared.checkAndUpdate(
                    owner: "altic-dev",
                    repo: "Fluid-oss",
                    includePrerelease: SettingsStore.shared.betaReleasesEnabled
                )
                ChromeAlerts.updateAvailable().runModal()
            } catch {
                if let pmkError = error as? PMKError, pmkError.isCancelled {
                    ChromeAlerts.upToDate(isBeta: SettingsStore.shared.betaReleasesEnabled).runModal()
                } else {
                    ChromeAlerts.updateCheckFailed(error).runModal()
                }
            }
        }
    }

    @objc private func rollbackToPreviousVersion(_ sender: Any?) {
        let availableVersion = SimpleUpdater.shared.latestRollbackVersion() ?? ""
        // The build being left behind — named in the success panel so "report a
        // bug" has something concrete to be about.
        let versionRolledBackFrom = ChromeAlerts.currentVersion

        guard !availableVersion.isEmpty else {
            if ChromeAlerts.noRollbackBackup().runModal() == .alertFirstButtonReturn {
                self.openPreviousBuildPicker()
            }
            return
        }

        guard ChromeAlerts.confirmRollback(to: availableVersion).runModal() == .alertFirstButtonReturn
        else { return }

        Task { @MainActor in
            do {
                try await SimpleUpdater.shared.rollbackToLatestBackup()
                let success = ChromeAlerts.rollbackSucceeded(
                    to: availableVersion,
                    from: versionRolledBackFrom
                )
                if success.runModal() == .alertFirstButtonReturn {
                    self.openIssueReportingPage()
                }
            } catch {
                ChromeAlerts.rollbackFailed(error, currentVersion: versionRolledBackFrom).runModal()
            }
        }
    }

    private func openIssueReportingPage() {
        guard let url = URL(string: "https://github.com/altic-dev/Fluid-oss/issues/new/choose") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPreviousBuildPicker() {
        Task { @MainActor in
            do {
                let options = try await SimpleUpdater.shared.fetchRecentReleaseBuildOptions(
                    owner: "altic-dev",
                    repo: "Fluid-oss",
                    limit: 3,
                    includePrerelease: SettingsStore.shared.betaReleasesEnabled
                )
                self.presentPreviousBuildPicker(options)
            } catch {
                self.openAllReleasesPage()
            }
        }
    }

    private func presentPreviousBuildPicker(_ options: [SimpleUpdater.ReleaseBuildOption]) {
        guard !options.isEmpty else {
            self.openAllReleasesPage()
            return
        }

        let picker = ChromeAlerts.previousBuildPicker()

        for option in options {
            picker.addButton(withTitle: option.version)
        }
        picker.addButton(withTitle: ChromeAlerts.allReleasesButton)
        picker.addButton(withTitle: ChromeAlerts.cancelButton)

        let response = picker.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let index = response.rawValue - first

        if index >= 0, index < options.count {
            NSWorkspace.shared.open(options[index].url)
            return
        }
        if index == options.count {
            self.openAllReleasesPage()
        }
    }

    private func openAllReleasesPage() {
        guard let url = URL(string: "https://github.com/altic-dev/Fluid-oss/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openMainWindow() {
        // First, unhide the app if it's hidden
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        // Activate the app and bring it to the front
        NSApp.activate(ignoringOtherApps: true)

        var mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        if let hostedWindow,
           mainWindows.contains(where: { $0 !== hostedWindow })
        {
            hostedWindow.close()
            self.hostedWindow = nil
            mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        }

        // Find an existing *non-minimized* primary window.
        // Important: avoid programmatic deminiaturize() — it creates internal window transform animations
        // (NSWindowTransformAnimation) that have been unstable on macOS 26.x for this app.
        if let window = mainWindows.first {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
            if let hostedWindow, window !== hostedWindow {
                self.hostedWindow = nil
            }
        } else if let window = hostedWindow, window.isReleasedWhenClosed == false {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
        } else {
            // If there is no suitable window (or it's minimized), create a fresh one.
            self.createAndShowMainWindow()
        }

        // Final attempt: ensure app is active and visible
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isFluidMainWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        guard window.canBecomeKey else { return false }
        guard window.isMiniaturized == false else { return false }
        return window.title == "FluidVoice" || window.title.contains("FluidVoice")
    }

    @objc private func openPreferences() {
        self.openNavigationDestination(.preferences)
    }

    @objc private func openCustomDictionary() {
        self.openNavigationDestination(.customDictionary)
    }

    private func openNavigationDestination(_ destination: MenuBarNavigationDestination) {
        // Ensure a fresh one-shot request every time the menu item is clicked.
        self.requestedNavigationDestination = nil
        self.requestedNavigationDestination = destination

        self.openMainWindow()

        // Nudge again after the window is front-most, so an already-open ContentView
        // will still switch tabs even if it consumed a previous navigation request.
        DispatchQueue.main.async { [weak self] in
            self?.requestedNavigationDestination = nil
            self?.requestedNavigationDestination = destination
        }
    }

    /// Public entry-point for non-menu UI surfaces (e.g. overlay controls) to open Preferences.
    func openPreferencesFromUI() {
        self.openPreferences()
    }

    /// Create and present a fresh main window hosting `ContentView`
    private func createAndShowMainWindow() {
        // Build the SwiftUI root view with required environment
        let rootView = AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
            ContentView()
                .environmentObject(self)
                .environmentObject(AppServices.shared)
        }

        // Host inside an AppKit window
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Bundle.main.fluidAppDisplayName
        window.animationBehavior = .none
        window.minSize = self.mainWindowMinimumSize
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        Self.applyBasicsChrome(to: window)
        window.setFrame(self.defaultWindowFrame(), display: false)
        self.bringToFront(window)
        self.hostedWindow = window

        // Bring app to front in case we're running as an accessory app (no Dock)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// The titlebar otherwise draws its own material, leaving a lighter band
    /// across the top with a visible seam against the page. Make it transparent
    /// and paint the window in the app ground so the chrome and the backdrop
    /// are one plain colour.
    /// The titlebar keeps its OWN reserved band and the content area begins
    /// below it — no overlap.
    ///
    /// Deliberately NOT here: `.fullSizeContentView`, a hidden title, and any
    /// `ignoresSafeArea` on the split view. Those were tried to pull the sidebar
    /// up to the window's top edge, and each one broke something at a different
    /// layer — the first nav row was clipped behind the traffic lights, and a
    /// hidden title collapses the titlebar's leading space so the
    /// `.primaryAction` toolbar group slides to the left. A genuine full-height
    /// sidebar needs `NavigationSplitView` replaced with a custom split layout,
    /// not a window flag.
    ///
    /// What DOES belong here: a transparent titlebar painted in the app ground,
    /// so the band is one plain colour continuous with the page rather than the
    /// system's own lighter material with a seam under it.
    static func applyBasicsChrome(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        // The window ground is only ever visible in ONE place: the strip above
        // the sidebar, because the detail pane paints its own white up under
        // the titlebar already. So the ground is the SIDEBAR tone — that makes
        // the left of the strip continuous with the sidebar and the right
        // continuous with the page, and the band stops reading as a band.
        window.backgroundColor = NSColor(BasicsTokens.Surface.sidebar)
        window.isOpaque = true
        // No titlebar band at all: the content view fills the window and the
        // traffic lights float over it. Note this is NOT paired with
        // `ignoresSafeArea` on the split view — SwiftUI still reports the
        // titlebar's height as safe area, so the nav rows stay clear of the
        // lights while the sidebar's own background runs to the top edge.
        // Pairing the two is what clipped the first row in an earlier attempt.
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        Self.allowFullHeightSidebar(in: window)
    }

    /// `NavigationSplitView` is an `NSSplitViewController` underneath, and the
    /// AppKit knob that lets a sidebar occupy the titlebar's height is
    /// `NSSplitViewItem.allowsFullHeightLayout`. SwiftUI does not surface it, so
    /// reach the controller and set it — without this the split view lays itself
    /// out BELOW the titlebar no matter what the window's style mask says, and
    /// the window ground shows through as a band across the top.
    private static func allowFullHeightSidebar(in window: NSWindow) {
        guard let root = window.contentViewController else { return }
        var queue: [NSViewController] = [root]
        while let controller = queue.first {
            queue.removeFirst()
            if let split = controller as? NSSplitViewController,
               let sidebar = split.splitViewItems.first
            {
                sidebar.allowsFullHeightLayout = true
                // Leave the divider invisible — a line here would reinstate the
                // seam the design is trying to remove.
                sidebar.titlebarSeparatorStyle = .none
                split.splitViewItems.dropFirst().forEach { $0.titlebarSeparatorStyle = .none }
                return
            }
            queue.append(contentsOf: controller.children)
        }
    }

    private func ensureUsableMainWindow(_ window: NSWindow) {
        // If the window is too small (e.g., height collapsed), reset to the default frame.
        let minSize = self.mainWindowMinimumSize
        window.minSize = minSize

        let frame = window.frame
        if frame.height < minSize.height || frame.width < minSize.width {
            window.setFrame(self.defaultWindowFrame(), display: false)
        }

        // Also walk back frames far LARGER than the default (a maximised
        // carry-over, or a frame saved by an earlier build). A resize within
        // reason is respected; a screen-filling one is not what this window is
        // for.
        let defaultSize = self.defaultWindowFrame().size
        if frame.width > defaultSize.width * 1.5 || frame.height > defaultSize.height * 1.5 {
            window.setFrame(self.defaultWindowFrame(), display: false)
        }
    }

    private func defaultWindowFrame() -> NSRect {
        // Compact by design. This is a configure-and-glance window, not a
        // workspace — the product is used through the overlays, so the window
        // sizes like Willow and its peers rather than filling the screen.
        let size = NSSize(width: 1040, height: 680)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private var mainWindowMinimumSize: NSSize {
        let window = AppTheme.dark.metrics.window
        return NSSize(width: window.mainMinWidth, height: window.mainMinHeight)
    }

    private func bringToFront(_ window: NSWindow) {
        // Keep ordering explicit to avoid "opened but behind other apps" behavior.
        if window.alphaValue <= 0.01 {
            window.alphaValue = 1
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Alert copy

/// Every modal panel the app raises outside its own window, in ONE string table.
///
/// macOS draws the box; these four rules decide what goes in it (Paper board
/// `19 — Chrome`, section `S5 · Alert copy`):
///
/// 1. The first line is the OUTCOME, not the event.
/// 2. The informative text says what happens NEXT.
/// 3. Buttons are verbs, and the safe one is the default (index 0).
/// 4. A raw error goes on its own last line, after a blank line.
///
/// Both update paths read from here — `MenuBarManager`'s own fallback check and
/// `AppDelegate.checkForUpdatesManually()` — so the two can no longer disagree
/// about what the app is called or whether it is up to date.
enum ChromeAlerts {

    /// The product name as it is spoken everywhere else in the UI. The bundle's
    /// display name is still the upstream `FluidVoice`, so it cannot be used.
    static let productName = "Basics Voice"

    /// The build the user is running right now.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Title + informative text + buttons, assembled the same way every time.
    /// Button 0 is the default and, by rule 2, the safe one wherever the choice
    /// is destructive.
    private static func alert(
        _ title: String,
        _ message: String,
        style: NSAlert.Style = .informational,
        buttons: [String] = ["OK"]
    ) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        return alert
    }

    /// Rule 4: the raw error is diagnostic, so it survives verbatim — but it
    /// sits under a plain-English line rather than replacing one.
    private static func withRawError(_ message: String, _ error: Error) -> String {
        "\(message)\n\n\(error.localizedDescription)"
    }

    // MARK: Updates

    /// 01 — the check found a newer build and the install has already started.
    /// The version is deliberately absent: `checkAndUpdate` does not report
    /// which build it picked, and an invented number would be worse than none.
    static func updateAvailable() -> NSAlert {
        self.alert(
            "Update available",
            "The new build is downloading now and installs itself. "
                + "\(self.productName) relaunches when it finishes."
        )
    }

    /// 02 / 03 — nothing newer, on whichever channel the user is on.
    static func upToDate(isBeta: Bool) -> NSAlert {
        self.alert(
            isBeta ? "You’re up to date on beta" : "You’re up to date",
            isBeta
                ? "\(self.productName) \(self.currentVersion) is the newest build in the beta channel."
                : "\(self.productName) \(self.currentVersion) is the newest stable build."
        )
    }

    /// 04 — the check itself could not run, so nothing is known either way.
    static func updateCheckFailed(_ error: Error) -> NSAlert {
        self.alert(
            "Update check failed",
            self.withRawError(
                "\(self.productName) couldn’t reach the release server, so it doesn’t know "
                    + "whether a newer build exists. Try again later.",
                error
            )
        )
    }

    /// 11 — the background check found a build and the snooze has expired.
    static func updateFound(version: String) -> NSAlert {
        self.alert(
            "\(self.productName) \(version) is available",
            "Install it now and the app relaunches on its own. Later means we ask again tomorrow.",
            buttons: ["Install now", "Later"]
        )
    }

    // MARK: Rollback

    /// 05 — nothing was ever kept on this machine.
    static func noRollbackBackup() -> NSAlert {
        self.alert(
            "No backup to roll back to",
            "This Mac has never kept a previous build of \(self.productName). "
                + "You can download an older release from GitHub instead.",
            buttons: ["Get previous builds", "Cancel"]
        )
    }

    /// 06 — the destructive confirmation. Cancel is not the default because the
    /// user asked for this explicitly, but the panel says exactly what survives.
    static func confirmRollback(to version: String) -> NSAlert {
        self.alert(
            "Roll back to \(version)?",
            "\(self.productName) restores the backed-up build and relaunches. "
                + "Your settings, dictionary and history stay as they are.",
            style: .warning,
            buttons: ["Roll back", "Cancel"]
        )
    }

    /// 07 — done. Button 0 still opens the issue page, as it always did.
    static func rollbackSucceeded(to version: String, from previousVersion: String) -> NSAlert {
        self.alert(
            "Rolled back to \(version)",
            "\(self.productName) relaunches in a moment. If \(previousVersion) broke something "
                + "for you, say what — it goes straight to the issue tracker.",
            buttons: ["Report a bug", "Done"]
        )
    }

    /// 08 — the restore threw. Rule 4 again: reassurance first, raw error last.
    static func rollbackFailed(_ error: Error, currentVersion: String) -> NSAlert {
        self.alert(
            "Roll back failed",
            self.withRawError(
                "The backup couldn’t be restored, so \(self.productName) is still on "
                    + "\(currentVersion). Nothing was removed.",
                error
            ),
            style: .critical
        )
    }

    /// 09 — the manual download picker. It ships with NO buttons: the caller
    /// appends one per real release, then `allReleasesButton` and
    /// `cancelButton`, so the index arithmetic on the response still holds.
    static func previousBuildPicker() -> NSAlert {
        self.alert(
            "Download an older build",
            "Pick a release to download. Installing it is manual — "
                + "drag the app into Applications yourself.",
            buttons: []
        )
    }

    static let allReleasesButton = "All releases"
    static let cancelButton = "Cancel"

    // MARK: Local model

    /// 10 — the one-time offer to move onto the faster local model.
    static func fasterModelOffer() -> NSAlert {
        self.alert(
            "Fluid-1 runs 2.2× faster now",
            "A 3.77 GB build of Fluid-1 is ready for Apple silicon. Your current model "
                + "keeps working until the new one finishes verifying.",
            buttons: ["Download it", "Keep current model"]
        )
    }
}
