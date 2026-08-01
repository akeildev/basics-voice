//
//  SettingsView.swift
//  fluid
//
//  The Preferences page. Rebuilt for the Basics redesign against boards
//  11 / 11b / 11c / 11d / 11e / 11f (states 11g, alerts 15): settings sit
//  directly on the surface separated by 1px hairlines, labels left and every
//  control in a right-hand lane. Cards are reserved for the four grouped
//  moments the boards keep — the update hero, audio storage, the primary
//  dictation shortcut group, and the filler-word editor.
//
//  This is a re-skin plus a re-organisation into the boards' section order.
//  Every binding, store key, notification name and NSAlert action is the same
//  one the previous version used; only the presentation and the UI strings
//  changed.
//

import AppKit
import AVFoundation
import PromiseKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService {
        self.appServices.asr
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @Binding var appear: Bool
    @Binding var visualizerNoiseThreshold: Double
    @Binding var selectedInputUID: String
    @Binding var selectedOutputUID: String
    @Binding var microphoneSelectionMode: SettingsStore.MicrophoneSelectionMode
    @Binding var inputDevices: [AudioDevice.Device]
    @Binding var outputDevices: [AudioDevice.Device]
    @Binding var accessibilityEnabled: Bool
    @Binding var primaryDictationShortcuts: [HotkeyShortcut]
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?
    @Binding var commandModeShortcut: HotkeyShortcut?
    @Binding var pokeShortcut: HotkeyShortcut?
    @Binding var taskShortcut: HotkeyShortcut?
    @Binding var rewriteShortcut: HotkeyShortcut
    @Binding var cancelRecordingShortcut: HotkeyShortcut
    @Binding var pasteLastTranscriptionShortcut: HotkeyShortcut?
    @Binding var commandModeShortcutEnabled: Bool
    @Binding var pokeShortcutEnabled: Bool
    @Binding var taskShortcutEnabled: Bool
    @Binding var rewriteShortcutEnabled: Bool
    @Binding var pasteLastTranscriptionShortcutEnabled: Bool
    @Binding var hotkeyManagerInitialized: Bool
    @Binding var hotkeyMode: HotkeyActivationMode
    @Binding var enableStreamingPreview: Bool
    @Binding var copyToClipboard: Bool

    // CRITICAL FIX: Cache default device names to avoid CoreAudio calls during view body evaluation.
    // Querying AudioDevice.getDefaultInputDevice() in the view body triggers HALSystem::InitializeShell()
    // which races with SwiftUI's AttributeGraph metadata processing and causes EXC_BAD_ACCESS crashes.
    @State private var cachedDefaultInputName: String = ""
    @State private var cachedDefaultOutputName: String = ""

    // Analytics consent UI state (default ON; user can opt-out)
    @State private var shareAnonymousAnalytics: Bool = SettingsStore.shared.shareAnonymousAnalytics
    @State private var showAnalyticsPrivacy: Bool = false
    @State private var pendingAnalyticsValue: Bool? = nil
    @State private var showAreYouSureToStopAnalytics: Bool = false
    @State private var rollbackVersion: String = ""
    @State private var isRollingBack: Bool = false
    @State private var audioHistoryBudgetText: String = Self.audioBudgetText(for: SettingsStore.shared.audioHistoryBudgetGB)
    @State private var audioHistoryUsageBytes: Int64 = DictationAudioHistoryStore.shared.audioUsageBytes()

    let hotkeyManager: GlobalHotkeyManager?
    let menuBarManager: MenuBarManager
    let startRecording: () -> Void
    let refreshDevices: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void
    let revealAppInFinder: () -> Void
    let openApplicationsFolder: () -> Void

    // MARK: - Bindings

    private var inputDeviceSelection: Binding<String> {
        Binding(
            get: { self.selectedInputUID },
            set: { newUID in
                guard !newUID.isEmpty else { return }
                guard !self.asr.isRunning else {
                    DebugLogger.shared.warning(
                        "Cannot change input device during recording",
                        source: "SettingsView"
                    )
                    return
                }

                self.selectedInputUID = newUID
                SettingsStore.shared.recordInputDeviceSelection(newUID)
                if SettingsStore.shared.shouldSyncInputSelectionToSystemDefault() {
                    _ = AudioDevice.setDefaultInputDevice(uid: newUID)
                }
            }
        )
    }

    private var outputDeviceSelection: Binding<String> {
        Binding(
            get: { self.selectedOutputUID },
            set: { newUID in
                guard !newUID.isEmpty else { return }
                guard !self.asr.isRunning else {
                    DebugLogger.shared.warning(
                        "Cannot change output device during recording",
                        source: "SettingsView"
                    )
                    return
                }

                self.selectedOutputUID = newUID
                SettingsStore.shared.preferredOutputDeviceUID = newUID
                _ = AudioDevice.setDefaultOutputDevice(uid: newUID)
            }
        )
    }

    private var hotkeyModeSelection: Binding<HotkeyActivationMode> {
        Binding(
            get: { self.hotkeyMode },
            set: { newValue in
                self.hotkeyMode = newValue
                SettingsStore.shared.hotkeyMode = newValue
                self.hotkeyManager?.setHotkeyMode(newValue)
            }
        )
    }

    private var copyToClipboardBinding: Binding<Bool> {
        Binding(
            get: { self.copyToClipboard },
            set: { newValue in
                self.copyToClipboard = newValue
                SettingsStore.shared.copyTranscriptionToClipboard = newValue
            }
        )
    }

    private var streamingPreviewBinding: Binding<Bool> {
        Binding(
            get: { self.enableStreamingPreview },
            set: { newValue in
                self.enableStreamingPreview = newValue
                SettingsStore.shared.enableStreamingPreview = newValue
            }
        )
    }

    private var isRecordingAnyShortcut: Bool {
        self.activeShortcutRecordingTarget != nil
    }

    private func isRecording(_ target: ShortcutRecordingTarget) -> Bool {
        self.activeShortcutRecordingTarget == target
    }

    private var analyticsToggleBinding: Binding<Bool> {
        Binding(
            get: {
                self.pendingAnalyticsValue ?? self.shareAnonymousAnalytics
            },
            set: { newValue in
                // User is trying to turn OFF → ask first
                if self.shareAnonymousAnalytics == true, newValue == false {
                    self.pendingAnalyticsValue = false
                    self.showAreYouSureToStopAnalytics = true

                    return
                }

                // Normal ON path
                self.shareAnonymousAnalytics = newValue
                self.applyAnalyticsConsentChange(newValue)
            }
        )
    }

    private var analyticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.showAreYouSureToStopAnalytics },
            set: { newValue in
                // Only open modal if we have a pending value
                if newValue {
                    if self.pendingAnalyticsValue != nil {
                        self.showAreYouSureToStopAnalytics = true
                    }
                } else {
                    // Closing the modal: reset pending state
                    self.showAreYouSureToStopAnalytics = false
                    self.pendingAnalyticsValue = nil
                }
            }
        )
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    private var launchAtStartupBinding: Binding<Bool> {
        Binding(
            get: { self.settings.launchAtStartupEnabled },
            set: { self.settings.setLaunchAtStartup($0) }
        )
    }

    private func dictationPromptSelectionBinding(for slot: SettingsStore.DictationShortcutSlot) -> Binding<String> {
        Binding(
            get: {
                switch self.settings.dictationPromptSelection(for: slot) {
                case .off:
                    return "__OFF__"
                case .default:
                    return "__DEFAULT__"
                case .privateAI:
                    return PrivateAIProviderPromptFormat.promptSelectionID
                case let .profile(id):
                    return id
                }
            },
            set: { newValue in
                switch newValue {
                case "__OFF__":
                    self.settings.setDictationPromptSelection(.off, for: slot)
                case "__DEFAULT__":
                    guard !PrivateAIProviderPromptFormat.isAvailable(settings: self.settings) else { return }
                    self.settings.setDictationPromptSelection(.default, for: slot)
                case PrivateAIProviderPromptFormat.promptSelectionID:
                    guard PrivateAIProviderPromptFormat.isAvailable(settings: self.settings) else { return }
                    self.settings.setDictationPromptSelection(.privateAI, for: slot)
                default:
                    guard !PrivateAIProviderPromptFormat.isAvailable(settings: self.settings) else { return }
                    self.settings.setDictationPromptSelection(.profile(newValue), for: slot)
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        SettingsPersistentScrollView(theme: self.theme, colorScheme: self.colorScheme) {
            VStack(alignment: .leading, spacing: 26) {
                self.pageHead
                self.appearanceSection
                self.appSection
                self.permissionsSection
                self.updatesAndStorageChapter
                self.soundsAndOverlayChapter
                self.shortcutsChapter
                self.dictationOutputChapter
                self.devicesAndDiagnosticsChapter
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .background(self.theme.palette.contentBackground)
        }
        .sheet(isPresented: self.$showAnalyticsPrivacy) {
            AnalyticsPrivacyView()
                .frame(minWidth: 520, minHeight: 520)
                .appTheme(self.theme)
        }
        .sheet(isPresented: self.analyticsConfirmationBinding) {
            AnalyticsConfirmationView(
                onConfirm: {
                    if let pending = pendingAnalyticsValue {
                        self.shareAnonymousAnalytics = pending
                        self.applyAnalyticsConsentChange(pending)
                    }
                    self.pendingAnalyticsValue = nil
                    self.showAreYouSureToStopAnalytics = false
                },
                onCancel: {
                    self.pendingAnalyticsValue = nil
                    self.showAreYouSureToStopAnalytics = false
                }
            )
        }
        .onAppear {
            Task { @MainActor in
                // Ensure the shared audio startup gate is scheduled. Safe to call repeatedly.
                await AudioStartupGate.shared.scheduleOpenAfterInitialUISettled()
                await AudioStartupGate.shared.waitUntilOpen()

                self.refreshDevices()

                // Sync input device selection after refresh
                if !self.inputDevices.isEmpty {
                    let inputValid = self.inputDevices.contains { $0.uid == self.selectedInputUID }
                    if !inputValid || self.selectedInputUID.isEmpty {
                        if let defaultUID = AudioDevice.getDefaultInputDevice()?.uid,
                           self.inputDevices.contains(where: { $0.uid == defaultUID })
                        {
                            self.selectedInputUID = defaultUID
                        } else {
                            self.selectedInputUID = self.inputDevices.first?.uid ?? ""
                        }
                    }
                }

                // Sync output device selection after refresh
                if !self.outputDevices.isEmpty {
                    let outputValid = self.outputDevices.contains { $0.uid == self.selectedOutputUID }
                    if !outputValid || self.selectedOutputUID.isEmpty {
                        if let prefUID = SettingsStore.shared.preferredOutputDeviceUID,
                           self.outputDevices.contains(where: { $0.uid == prefUID })
                        {
                            self.selectedOutputUID = prefUID
                        } else if let defaultUID = AudioDevice.getDefaultOutputDevice()?.uid,
                                  self.outputDevices.contains(where: { $0.uid == defaultUID })
                        {
                            self.selectedOutputUID = defaultUID
                        } else {
                            self.selectedOutputUID = self.outputDevices.first?.uid ?? ""
                        }
                    }
                }

                // CRITICAL FIX: Populate cached default device names after onAppear, not during view body evaluation.
                // This avoids the CoreAudio/SwiftUI AttributeGraph race condition that causes EXC_BAD_ACCESS.
                self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""
                self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
                self.refreshRollbackState()
                self.settings.refreshLaunchAtStartupStatus(clearError: true, logMismatch: false)
                self.refreshAudioHistoryUsage()
            }
        }
        .onChange(of: self.visualizerNoiseThreshold) { _, newValue in
            SettingsStore.shared.visualizerNoiseThreshold = newValue
        }
        .onChange(of: self.inputDevices) { _, newDevices in
            // Update cached default device name when device list changes
            self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""

            guard !newDevices.isEmpty else { return }

            switch self.microphoneSelectionMode {
            case .system:
                if let defaultUID = AudioDevice.getDefaultInputDevice()?.uid,
                   newDevices.contains(where: { $0.uid == defaultUID })
                {
                    self.selectedInputUID = defaultUID
                } else if !newDevices.contains(where: { $0.uid == self.selectedInputUID }) {
                    self.selectedInputUID = newDevices.first?.uid ?? ""
                }
            case .manual:
                if let preferredUID = SettingsStore.shared.preferredInputDeviceUID,
                   newDevices.contains(where: { $0.uid == preferredUID })
                {
                    self.selectedInputUID = preferredUID
                } else if let defaultUID = AudioDevice.getDefaultInputDevice()?.uid,
                          newDevices.contains(where: { $0.uid == defaultUID })
                {
                    self.selectedInputUID = defaultUID
                } else {
                    self.selectedInputUID = newDevices.first?.uid ?? ""
                }
            }
        }
        .onChange(of: self.outputDevices) { _, newDevices in
            // Update cached default device name when device list changes
            self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""

            guard !newDevices.isEmpty else { return }

            let currentValid = newDevices.contains { $0.uid == self.selectedOutputUID }
            guard !currentValid else { return }

            if let prefUID = SettingsStore.shared.preferredOutputDeviceUID,
               newDevices.contains(where: { $0.uid == prefUID })
            {
                self.selectedOutputUID = prefUID
            } else if let defaultUID = AudioDevice.getDefaultOutputDevice()?.uid,
                      newDevices.contains(where: { $0.uid == defaultUID })
            {
                self.selectedOutputUID = defaultUID
            } else {
                self.selectedOutputUID = newDevices.first?.uid ?? ""
            }
        }
    }

    // MARK: - Page furniture

    private var pageHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text("Preferences")
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
        }
    }

    private func chapterHead(_ title: String, trailing: AnyView? = nil) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Spacer(minLength: 12)
            if let trailing {
                trailing
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Chapters
    //
    // Boards 11b–11f are the same scrolling page below board 11, so each one
    // becomes a chapter head plus its sections. Grouped because a ViewBuilder
    // block takes ten children at most.

    private var updatesAndStorageChapter: some View {
        Group {
            self.chapterHead("Updates & storage")
            self.updatesSection
            self.storageSection
        }
    }

    private var soundsAndOverlayChapter: some View {
        Group {
            self.chapterHead("Sounds & overlay")
            self.soundsSection
            self.overlaySection
        }
    }

    private var shortcutsChapter: some View {
        Group {
            self.chapterHead("Shortcuts", trailing: AnyView(self.hotkeyStatusChip))
            self.shortcutsRegion
        }
    }

    private var dictationOutputChapter: some View {
        Group {
            self.chapterHead("Dictation output")
            self.howTextLandsSection
            self.whileYouDictateSection
        }
    }

    private var devicesAndDiagnosticsChapter: some View {
        Group {
            self.chapterHead("Devices & diagnostics")
            self.audioDevicesSection
            self.fillerWordsSection
            self.diagnosticsSection
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        PrefSection(title: "Appearance") {
            PrefRows {
                PrefRow(
                    title: "Accent colour",
                    helper: "Basics green is the default. The accent is used once per region — never as decoration.",
                    verticalPadding: 12
                ) {
                    HStack(spacing: 6) {
                        ForEach(SettingsStore.AccentColorOption.allCases) { option in
                            AccentSwatch(
                                option: option,
                                isSelected: self.settings.accentColorOption == option
                            ) {
                                self.settings.accentColorOption = option
                            }
                        }
                    }
                }

                PrefRow(
                    title: "Theme",
                    helper: "Follows macOS by default. The recording overlay is always dark.",
                    verticalPadding: 12
                ) {
                    PrefSegmentedControl(
                        options: SettingsStore.ThemePreference.allCases.map {
                            PrefSegmentedControl<SettingsStore.ThemePreference>.Option(
                                id: $0.rawValue,
                                title: $0.displayName,
                                value: $0
                            )
                        },
                        selection: Binding(
                            get: { self.settings.themePreference },
                            set: { self.settings.themePreference = $0 }
                        )
                    )
                }
            }
        }
    }

    // MARK: - App

    private var appSection: some View {
        PrefSection(title: "App") {
            PrefRows {
                PrefRow(
                    title: "Launch at login",
                    helper: "Starts \(self.appDisplayName) when you log in. Mirrors the real macOS login-item state.",
                    footnote: self.settings.launchAtStartupErrorMessage,
                    footnoteTone: .warning
                ) {
                    PrefSwitch(isOn: self.launchAtStartupBinding, label: "Launch at login")
                }

                PrefRow(
                    title: "Show window when launched at login",
                    helper: "Off means it starts silently in the menu bar. Opening the app yourself always shows the window."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.showMainWindowAtLoginLaunch },
                            set: { SettingsStore.shared.showMainWindowAtLoginLaunch = $0 }
                        ),
                        label: "Show window when launched at login"
                    )
                }

                PrefRow(
                    title: "Hide from Dock & App Switcher",
                    helper: "Menu bar only. Takes effect after a restart."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.hideFromDockAndAppSwitcher },
                            set: { SettingsStore.shared.hideFromDockAndAppSwitcher = $0 }
                        ),
                        label: "Hide from Dock and App Switcher"
                    )
                }

                PrefRowShell {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share anonymous analytics")
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Usage and performance only. Never transcription text or prompts.")
                                .basicsProse(14)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("What we collect") {
                                self.showAnalyticsPrivacy = true
                            }
                            .buttonStyle(.plain)
                            .basicsButtonLabel(13)
                            .foregroundStyle(self.theme.palette.accent)
                        }
                    }
                } control: {
                    PrefSwitch(isOn: self.analyticsToggleBinding, label: "Share anonymous analytics")
                }

                PrefRow(
                    title: "Backup & restore",
                    helper: "Settings, prompt profiles, history and stats as one JSON file. API keys are never included."
                ) {
                    HStack(spacing: 8) {
                        Button("Export…") { self.exportBackup() }
                            .fluidButton(.secondary, size: .medium)
                        Button("Import…") { self.importBackup() }
                            .fluidButton(.secondary, size: .medium)
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        PrefSection(title: "Permissions") {
            PrefRows {
                self.microphonePermissionRow
                self.accessibilityPermissionRow
            }

            if self.asr.micStatus != .authorized {
                PrefInstructions(
                    title: "How to enable microphone access",
                    steps: self.asr.micStatus == .notDetermined
                        ? ["Click Grant access above.", "Choose Allow in the system dialog."]
                        : [
                            "Click Open Settings above.",
                            "Find \(self.appDisplayName) in the microphone list.",
                            "Toggle \(self.appDisplayName) on to allow access.",
                        ]
                )
            }
        }
    }

    private var microphonePermissionRow: some View {
        PrefRowShell(verticalPadding: 13) {
            HStack(spacing: 10) {
                PrefStatusDot(tone: self.asr.micStatus == .authorized ? .brand : .warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.microphoneStatusTitle)
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if self.asr.micStatus != .authorized {
                        Text("Microphone access is required for voice recording.")
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } control: {
            HStack(spacing: 10) {
                switch self.asr.micStatus {
                case .authorized:
                    PrefChip(text: "Granted", tone: .brand)
                case .notDetermined:
                    Button("Grant access") { self.asr.requestMicAccess() }
                        .fluidButton(.primary, size: .medium)
                default:
                    Button("Open Settings") { self.asr.openSystemSettingsForMic() }
                        .fluidButton(.primary, size: .medium)
                }
            }
        }
    }

    private var microphoneStatusTitle: String {
        switch self.asr.micStatus {
        case .authorized: return "Microphone access granted"
        case .denied: return "Microphone access denied"
        default: return "Microphone access not determined"
        }
    }

    private var accessibilityPermissionRow: some View {
        PrefRowShell(verticalPadding: 13) {
            HStack(spacing: 10) {
                PrefStatusDot(tone: self.accessibilityEnabled ? .brand : .warning)
                Text(
                    self.accessibilityEnabled
                        ? "Accessibility granted — global shortcuts active"
                        : "Accessibility permission required"
                )
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)
            }
        } control: {
            if self.accessibilityEnabled {
                PrefChip(text: "Granted", tone: .brand)
            } else {
                Button("Open accessibility settings") { self.openAccessibilitySettings() }
                    .fluidButton(.primary, size: .medium)
            }
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        PrefSection(title: "Updates") {
            self.updateHero

            PrefRows {
                PrefRow(
                    title: "Automatic updates",
                    helper: "Check for a new release once an hour and install it in the background."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.autoUpdateCheckEnabled },
                            set: { SettingsStore.shared.autoUpdateCheckEnabled = $0 }
                        ),
                        label: "Automatic updates"
                    )
                }

                PrefRow(
                    title: "Beta releases",
                    helper: "Opt in to preview builds that may be unstable.",
                    footnote: SettingsStore.shared.betaReleasesEnabled
                        ? "Beta opt-in enabled. Update checks include both stable and beta builds."
                        : nil,
                    footnoteTone: .warning
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.betaReleasesEnabled },
                            set: { SettingsStore.shared.betaReleasesEnabled = $0 }
                        ),
                        label: "Beta releases"
                    )
                }

                PrefRowShell {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rollback")
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(
                                self.rollbackVersion.isEmpty
                                    ? "Restores the previous build and relaunches. No rollback backup found."
                                    : "Restores the previous build and relaunches. Rollback target:"
                            )
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                            if !self.rollbackVersion.isEmpty {
                                Text(self.rollbackVersion)
                                    .basicsMono(12)
                                    .foregroundStyle(self.theme.palette.primaryText)
                            }
                        }
                    }
                } control: {
                    HStack(spacing: 8) {
                        Button("Get previous builds…") { self.openPreviousBuildPicker() }
                            .fluidButton(.secondary, size: .medium)

                        Button(
                            self.rollbackVersion.isEmpty
                                ? "Rollback"
                                : "Rollback to \(self.rollbackVersion)"
                        ) {
                            self.performRollback()
                        }
                        .fluidButton(.secondary, size: .medium)
                        .disabled(self.rollbackVersion.isEmpty || self.isRollingBack)
                    }
                    .opacity(self.isRollingBack ? 0.7 : 1)
                }
            }
        }
    }

    private var updateHero: some View {
        PrefCard {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(self.appDisplayName)
                            .basicsLabel(22)
                            .foregroundStyle(self.theme.palette.primaryText)
                        PrefChip(text: "v\(self.currentAppVersion)", tone: .brand, isMono: true)
                    }
                    Text(self.updateHeroHelper)
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("Release notes") { self.openAllReleasesPage() }
                        .fluidButton(.secondary, size: .medium)
                    Button("Check now") { self.checkForUpdates() }
                        .fluidButton(.primary, size: .medium)
                }
            }
        }
    }

    private var updateHeroHelper: String {
        let cadence = SettingsStore.shared.autoUpdateCheckEnabled
            ? "\(self.appDisplayName) checks GitHub releases once an hour."
            : "Automatic update checks are off — check by hand."
        guard let lastCheck = SettingsStore.shared.lastUpdateCheckDate else {
            return "No update check yet. \(cadence)"
        }
        return "Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened)). \(cadence)"
    }

    // MARK: - Storage

    private var storageSection: some View {
        PrefSection(title: "Storage") {
            PrefRows {
                PrefRow(
                    title: "Save transcription history",
                    helper: "Keeps transcripts locally so History and Stats have something to show."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.saveTranscriptionHistory },
                            set: {
                                SettingsStore.shared.saveTranscriptionHistory = $0
                                self.refreshAudioHistoryUsage()
                            }
                        ),
                        label: "Save transcription history"
                    )
                }

                PrefRow(
                    title: "Save audio with history",
                    helper: "Stores the microphone audio next to each transcript so you can replay it."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.saveAudioWithTranscriptionHistory },
                            set: {
                                SettingsStore.shared.saveAudioWithTranscriptionHistory = $0
                                self.refreshAudioHistoryUsage()
                            }
                        ),
                        label: "Save audio with history"
                    )
                }
                .disabled(!SettingsStore.shared.saveTranscriptionHistory)
                .opacity(SettingsStore.shared.saveTranscriptionHistory ? 1 : 0.45)
            }

            if SettingsStore.shared.saveTranscriptionHistory,
               SettingsStore.shared.saveAudioWithTranscriptionHistory
            {
                self.audioStorageCard
            }
        }
    }

    private var audioStorageCard: some View {
        PrefCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Audio storage")
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(DictationAudioHistoryStore.formattedGigabytes(self.audioHistoryUsageBytes)) GB")
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.primaryText)
                        Text("/ \(Self.audioBudgetText(for: SettingsStore.shared.audioHistoryBudgetGB)) GB budget")
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }

                    PrefMeter(fraction: self.audioHistoryUsageFraction())
                }

                PrefHairline()

                HStack(alignment: .center, spacing: 24) {
                    HStack(spacing: 10) {
                        Text("Budget")
                            .basicsLabel(13)
                            .foregroundStyle(self.theme.palette.secondaryText)

                        PrefFieldChrome(width: 104) {
                            HStack(spacing: 6) {
                                TextField("4", text: self.$audioHistoryBudgetText)
                                    .textFieldStyle(.plain)
                                    .basicsMono(13)
                                    .foregroundStyle(self.theme.palette.primaryText)
                                    .onSubmit { self.applyAudioHistoryBudget() }
                                Text("GB")
                                    .basicsMono(12)
                                    .foregroundStyle(self.theme.palette.tertiaryText)
                            }
                        }

                        Button("Apply") { self.applyAudioHistoryBudget() }
                            .fluidButton(.secondary, size: .medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button("Export ZIP…") { self.exportAudioZip() }
                            .fluidButton(.secondary, size: .medium)

                        Button("Delete audio") { self.deleteSavedAudio() }
                            .fluidCompactButton(
                                size: .medium,
                                foreground: BasicsTokens.Semantic.danger
                            )
                            .disabled(self.audioHistoryUsageBytes <= 0)
                    }
                }

                Text("Export writes a ZIP with manifest.jsonl and WAV audio. Lowering the budget below current usage prunes the oldest audio first and keeps every transcript.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sounds

    private var soundsSection: some View {
        PrefSection(title: "Sounds") {
            PrefRows {
                PrefRow(
                    title: "Sound cue",
                    helper: "Plays when recording starts. Some cues also play on stop. Choosing one previews it."
                ) {
                    self.prefMenu(SettingsStore.shared.transcriptionStartSound.displayName) {
                        Picker("", selection: Binding(
                            get: { SettingsStore.shared.transcriptionStartSound },
                            set: { newValue in
                                SettingsStore.shared.transcriptionStartSound = newValue
                                TranscriptionSoundPlayer.shared.playPreview(sound: newValue)
                            }
                        )) {
                            ForEach(SettingsStore.TranscriptionStartSound.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if SettingsStore.shared.transcriptionStartSound != .none {
                    PrefRow(
                        title: "Cue volume",
                        helper: "Hidden entirely when the cue is set to None."
                    ) {
                        PrefSlider(
                            value: Binding(
                                get: { Double(SettingsStore.shared.transcriptionSoundVolume) },
                                set: { SettingsStore.shared.transcriptionSoundVolume = Float($0) }
                            ),
                            range: 0...1,
                            step: 0.05,
                            readout: "\(Int((SettingsStore.shared.transcriptionSoundVolume * 100).rounded()))%",
                            onEditingChanged: { editing in
                                if !editing {
                                    TranscriptionSoundPlayer.shared.playPreviewAtVolume(
                                        SettingsStore.shared.transcriptionSoundVolume
                                    )
                                }
                            }
                        )
                    }

                    PrefRow(
                        title: "Independent volume",
                        helper: "Cue volume stays constant regardless of system volume; mute is still respected. It briefly changes system volume during playback."
                    ) {
                        PrefSwitch(
                            isOn: Binding(
                                get: { SettingsStore.shared.transcriptionSoundIndependentVolume },
                                set: { SettingsStore.shared.transcriptionSoundIndependentVolume = $0 }
                            ),
                            label: "Independent volume"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Recording overlay

    private var overlaySection: some View {
        PrefSection(title: "Recording overlay") {
            PrefRows {
                PrefRow(title: "Position", helper: nil, verticalPadding: 13) {
                    self.prefMenu(self.settings.overlayPosition.displayName, width: 170) {
                        Picker("", selection: self.$settings.overlayPosition) {
                            ForEach(SettingsStore.OverlayPosition.allCases, id: \.self) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if self.settings.overlayPosition == .bottom {
                    PrefRow(title: "Size", helper: nil, verticalPadding: 13) {
                        self.prefMenu(self.settings.overlaySize.displayName, width: 170) {
                            Picker("", selection: self.$settings.overlaySize) {
                                ForEach(SettingsStore.OverlaySize.allCases, id: \.self) { size in
                                    Text(size.displayName).tag(size)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    }

                    PrefRow(
                        title: "Bottom offset",
                        helper: "Distance from the bottom of the screen, 20–500 px. Only applies at the bottom position.",
                        verticalPadding: 13
                    ) {
                        PrefStepper(
                            readout: "\(Int(self.settings.overlayBottomOffset)) px",
                            canDecrease: self.settings.overlayBottomOffset > 20,
                            canIncrease: self.settings.overlayBottomOffset < 500,
                            onDecrease: {
                                self.settings.overlayBottomOffset = max(20, self.settings.overlayBottomOffset - 10)
                            },
                            onIncrease: {
                                self.settings.overlayBottomOffset = min(500, self.settings.overlayBottomOffset + 10)
                            }
                        )
                    }
                } else {
                    PrefRow(
                        title: "Notch style",
                        helper: "Replaces Size and Bottom offset when the position is Top of screen.",
                        verticalPadding: 13
                    ) {
                        self.prefMenu(self.settings.notchPresentationMode.displayName, width: 170) {
                            Picker("", selection: self.$settings.notchPresentationMode) {
                                ForEach(SettingsStore.NotchPresentationMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                }

                PrefRow(
                    title: "Preview length",
                    helper: "How many recent characters the notch or pill shows while you speak.",
                    verticalPadding: 13
                ) {
                    PrefStepper(
                        readout: "\(self.settings.transcriptionPreviewCharLimit) chars",
                        canDecrease: self.settings.transcriptionPreviewCharLimit
                            > SettingsStore.transcriptionPreviewCharLimitRange.lowerBound,
                        canIncrease: self.settings.transcriptionPreviewCharLimit
                            < SettingsStore.transcriptionPreviewCharLimitRange.upperBound,
                        onDecrease: {
                            self.settings.transcriptionPreviewCharLimit = max(
                                SettingsStore.transcriptionPreviewCharLimitRange.lowerBound,
                                self.settings.transcriptionPreviewCharLimit - SettingsStore.transcriptionPreviewCharLimitStep
                            )
                        },
                        onIncrease: {
                            self.settings.transcriptionPreviewCharLimit = min(
                                SettingsStore.transcriptionPreviewCharLimitRange.upperBound,
                                self.settings.transcriptionPreviewCharLimit + SettingsStore.transcriptionPreviewCharLimitStep
                            )
                        }
                    )
                }

                PrefRow(title: "Live preview", helper: nil, verticalPadding: 13) {
                    PrefSwitch(isOn: self.streamingPreviewBinding, label: "Live preview")
                }

                PrefRowShell(verticalPadding: 13) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            Text("Visualiser sensitivity")
                                .basicsLabel(15)
                                .foregroundStyle(self.theme.palette.primaryText)
                            Button("Reset") {
                                self.visualizerNoiseThreshold = 0.4
                                SettingsStore.shared.visualizerNoiseThreshold = self.visualizerNoiseThreshold
                            }
                            .fluidButton(.secondary, size: .compact)
                        }
                        Text("How readily the waveform reacts to sound. Default 0.40.")
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } control: {
                    HStack(spacing: 10) {
                        Text("More")
                            .basicsMicroLabel(10)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        PrefSlider(
                            value: self.$visualizerNoiseThreshold,
                            range: 0.01...0.8,
                            step: 0.01,
                            readout: nil,
                            width: 120
                        )
                        Text("Less")
                            .basicsMicroLabel(10)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        Text(String(format: "%.2f", self.visualizerNoiseThreshold))
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            // Board 11c carries this as a standing line. It names only what the
            // view actually disables — the device pickers, the microphone-mode
            // toggle and faster recording start.
            PrefNote(
                text: "Device settings are locked while a recording is running.",
                tone: self.asr.isRunning ? .warning : .neutral
            )
        }
    }

    // MARK: - Shortcuts

    private var hotkeyStatusChip: some View {
        Group {
            if self.accessibilityEnabled {
                if self.isRecordingAnyShortcut {
                    PrefChip(text: "Recording…", tone: .warning)
                } else if self.hotkeyManagerInitialized {
                    PrefChip(text: "Active", tone: .brand, systemImage: "checkmark")
                } else {
                    PrefChip(text: "Initialising…", tone: .muted)
                }
            } else {
                PrefChip(text: "Blocked", tone: .warning)
            }
        }
    }

    @ViewBuilder
    private var shortcutsRegion: some View {
        if self.accessibilityEnabled {
            self.primaryDictationSection
            self.modeShortcutsSection
        } else {
            self.accessibilityBlockedSection
        }
    }

    private var accessibilityBlockedSection: some View {
        PrefSection(title: "Accessibility required") {
            PrefBanner(
                title: "Accessibility permission required",
                message: "Every shortcut row and the activation options stay hidden until this is granted."
            )

            PrefInstructions(
                title: "Follow these steps to enable Accessibility",
                steps: [
                    "Click Open accessibility settings below.",
                    "In the Accessibility window, click the + button.",
                    "Select \(self.appDisplayName) — use Reveal in Finder if you need to locate it.",
                    "Click Open, then toggle \(self.appDisplayName) on in the list.",
                ]
            )

            HStack(spacing: 8) {
                Button("Open accessibility settings") { self.openAccessibilitySettings() }
                    .fluidButton(.primary, size: .medium)
                Button("Reveal in Finder") { self.revealAppInFinder() }
                    .fluidButton(.secondary, size: .medium)
                Button("Open Applications") { self.openApplicationsFolder() }
                    .fluidButton(.secondary, size: .medium)
            }
        }
    }

    private var primaryDictationSection: some View {
        PrefSection(title: "Primary dictation") {
            PrefCard(padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22), spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 24) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hold to dictate")
                                .basicsLabel(15)
                                .foregroundStyle(self.theme.palette.primaryText)
                            Text("Any keyboard shortcut, auxiliary mouse button, or modified click. More than one can be bound.")
                                .basicsProse(14)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(self.isAddingPrimaryShortcut ? "Cancel" : "Add shortcut") {
                            let addTarget = ShortcutRecordingTarget.primaryDictation(.add)
                            if self.isAddingPrimaryShortcut {
                                self.shortcutRecordingMessage = nil
                                self.activeShortcutRecordingTarget = nil
                            } else {
                                DebugLogger.shared.debug(
                                    "Starting to record new primary dictation shortcut",
                                    source: "SettingsView"
                                )
                                self.shortcutRecordingMessage = nil
                                self.activeShortcutRecordingTarget = addTarget
                            }
                        }
                        .fluidButton(.secondary, size: .medium)
                        .disabled(!self.isAddingPrimaryShortcut && self.isRecordingAnyShortcut)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(self.primaryDictationShortcuts.enumerated()), id: \.offset) { index, shortcut in
                            self.primaryDictationRow(shortcut: shortcut, index: index)
                        }

                        if self.isAddingPrimaryShortcut {
                            self.primaryDictationCaptureRow
                        }

                        self.dictationPromptRow
                    }
                }
            }
        }
    }

    private var isAddingPrimaryShortcut: Bool {
        self.isRecording(.primaryDictation(.add))
    }

    private func primaryDictationRow(shortcut: HotkeyShortcut, index: Int) -> some View {
        let target = ShortcutRecordingTarget.primaryDictation(.replace(index))
        let capturing = self.isRecording(target)

        return HStack(spacing: 16) {
            if capturing {
                PrefShortcutPill(text: "Press shortcut…", isCapturing: true)
            } else {
                PrefShortcutPill(text: shortcut.displayString)
            }

            Text(self.primaryShortcutHelper(index: index, capturing: capturing))
                .basicsProse(13)
                .foregroundStyle(
                    capturing ? self.theme.palette.warning : self.theme.palette.secondaryText
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(capturing ? "Cancel" : "Change") {
                if capturing {
                    self.shortcutRecordingMessage = nil
                    self.activeShortcutRecordingTarget = nil
                } else {
                    DebugLogger.shared.debug(
                        "Starting to record replacement primary dictation shortcut",
                        source: "SettingsView"
                    )
                    self.shortcutRecordingMessage = nil
                    self.activeShortcutRecordingTarget = target
                }
            }
            .fluidButton(.secondary, size: .small)
            .frame(width: 82)
            .disabled(!capturing && self.isRecordingAnyShortcut)

            Button("Remove") {
                guard self.primaryDictationShortcuts.count > 1,
                      self.primaryDictationShortcuts.indices.contains(index)
                else { return }
                self.primaryDictationShortcuts.remove(at: index)
            }
            .fluidCompactButton(size: .small, foreground: self.theme.palette.secondaryText)
            .frame(width: 82)
            .disabled(self.primaryDictationShortcuts.count <= 1 || self.isRecordingAnyShortcut)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { PrefHairline() }
    }

    private func primaryShortcutHelper(index: Int, capturing: Bool) -> String {
        if capturing, let message = self.shortcutRecordingMessage, !message.isEmpty {
            return message
        }
        if capturing {
            return "Press your new hotkey combination now…"
        }
        return index == 0
            ? "Hold anywhere. This is the one you use all day."
            : "Extra binding for when the first one is taken by another app."
    }

    private var primaryDictationCaptureRow: some View {
        HStack(spacing: 16) {
            PrefShortcutPill(text: "Press shortcut…", isCapturing: true)

            Text(
                self.shortcutRecordingMessage.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Press your new hotkey combination now…"
            )
            .basicsProse(13)
            .foregroundStyle(self.theme.palette.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { PrefHairline() }
    }

    private var dictationPromptRow: some View {
        let profiles = self.settings.promptProfiles(for: .dictate)
        let privateAILocked = PrivateAIProviderPromptFormat.isAvailable(settings: self.settings)

        return HStack(spacing: 16) {
            Text("AI prompt applied to primary dictation")
                .basicsLabel(14)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            self.prefMenu(self.dictationPromptTitle(for: .primary, profiles: profiles), width: 190) {
                Picker("", selection: self.dictationPromptSelectionBinding(for: .primary)) {
                    Text("Off").tag("__OFF__")
                    Text("Default").tag("__DEFAULT__").disabled(privateAILocked)
                    if PrivateFeatures.privateAIProvider {
                        Text(PrivateAIProviderFeature.displayName)
                            .tag(PrivateAIProviderPromptFormat.promptSelectionID)
                            .disabled(!privateAILocked)
                    }
                    ForEach(profiles) { profile in
                        Text(profile.name.isEmpty ? "Untitled" : profile.name)
                            .tag(profile.id)
                            .disabled(privateAILocked)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { PrefHairline() }
    }

    private func dictationPromptTitle(
        for slot: SettingsStore.DictationShortcutSlot,
        profiles: [SettingsStore.DictationPromptProfile]
    ) -> String {
        switch self.settings.dictationPromptSelection(for: slot) {
        case .off:
            return "Off"
        case .default:
            return "Default"
        case .privateAI:
            return PrivateAIProviderFeature.displayName
        case let .profile(id):
            let profile = profiles.first { $0.id == id }
            let name = profile?.name ?? ""
            return name.isEmpty ? "Untitled" : name
        }
    }

    private var modeShortcutsSection: some View {
        PrefSection(title: "Mode shortcuts") {
            PrefRows {
                self.modeShortcutRow(
                    title: "Command mode",
                    helper: "Speak an instruction and the app runs it.",
                    shortcut: self.commandModeShortcut,
                    target: .command,
                    isEnabled: self.$commandModeShortcutEnabled,
                    requiresShortcutToEnable: true,
                    onRemove: {
                        if self.activeShortcutRecordingTarget == .command {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = nil
                        }
                        self.commandModeShortcut = nil
                        self.commandModeShortcutEnabled = false
                    }
                )

                self.modeShortcutRow(
                    title: "Send to Instinct",
                    helper: "Hold, speak, release — the transcript lands in your Instinct thread.",
                    shortcut: self.pokeShortcut,
                    target: .poke,
                    isEnabled: self.$pokeShortcutEnabled,
                    requiresShortcutToEnable: true,
                    onRemove: {
                        if self.activeShortcutRecordingTarget == .poke {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = nil
                        }
                        self.pokeShortcut = nil
                        self.pokeShortcutEnabled = false
                    }
                )

                self.modeShortcutRow(
                    title: "Task tracker",
                    helper: "Speak task commands for the notch HUD — start, done, add.",
                    shortcut: self.taskShortcut,
                    target: .task,
                    isEnabled: self.$taskShortcutEnabled,
                    requiresShortcutToEnable: true,
                    onRemove: {
                        if self.activeShortcutRecordingTarget == .task {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = nil
                        }
                        self.taskShortcut = nil
                        self.taskShortcutEnabled = false
                    }
                )

                self.modeShortcutRow(
                    title: "Rewrite mode",
                    helper: "Select text and speak how to edit it, or generate new content.",
                    shortcut: self.rewriteShortcut,
                    target: .edit,
                    isEnabled: self.$rewriteShortcutEnabled,
                    requiresShortcutToEnable: false,
                    onRemove: nil
                )

                self.modeShortcutRow(
                    title: "Cancel recording",
                    helper: "Cancels the current recording or dismisses the overlay.",
                    shortcut: self.cancelRecordingShortcut,
                    target: .cancel,
                    isEnabled: nil,
                    requiresShortcutToEnable: false,
                    onRemove: nil
                )

                self.modeShortcutRow(
                    title: "Paste last transcription",
                    helper: "Re-inserts your most recent transcription without touching the clipboard.",
                    shortcut: self.pasteLastTranscriptionShortcut,
                    target: .pasteLast,
                    isEnabled: self.$pasteLastTranscriptionShortcutEnabled,
                    requiresShortcutToEnable: true,
                    onRemove: {
                        if self.activeShortcutRecordingTarget == .pasteLast {
                            self.shortcutRecordingMessage = nil
                            self.activeShortcutRecordingTarget = nil
                        }
                        self.pasteLastTranscriptionShortcut = nil
                        self.pasteLastTranscriptionShortcutEnabled = false
                    }
                )

                PrefRow(
                    title: "Activation",
                    helper: self.hotkeyMode.description
                ) {
                    self.prefMenu(self.hotkeyMode.displayName, width: 170) {
                        Picker("", selection: self.hotkeyModeSelection) {
                            ForEach(HotkeyActivationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }

            if !self.hotkeyManagerInitialized {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .fixedSize()
                    Text("Hotkey manager is still initialising…")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func modeShortcutRow(
        title: String,
        helper: String,
        shortcut: HotkeyShortcut?,
        target: ShortcutRecordingTarget,
        isEnabled: Binding<Bool>?,
        requiresShortcutToEnable: Bool,
        onRemove: (() -> Void)?
    ) -> some View {
        let capturing = self.isRecording(target)
        let hasShortcut = shortcut != nil
        let enabledValue = isEnabled?.wrappedValue ?? true

        PrefRowShell(verticalPadding: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text(
                    capturing
                        ? (self.shortcutRecordingMessage.flatMap { $0.isEmpty ? nil : $0 }
                            ?? "Press your new hotkey combination now…")
                        : helper
                )
                .basicsProse(14)
                .foregroundStyle(capturing ? self.theme.palette.warning : self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        } control: {
            HStack(spacing: 10) {
                if capturing {
                    PrefShortcutPill(text: "Press shortcut…", isCapturing: true)
                } else {
                    PrefShortcutPill(text: shortcut?.displayString ?? "Not set", isMuted: !hasShortcut)
                }

                Button(capturing ? "Cancel" : "Change") {
                    if capturing {
                        self.shortcutRecordingMessage = nil
                        self.activeShortcutRecordingTarget = nil
                    } else {
                        DebugLogger.shared.debug(
                            "Starting to record new \(title) shortcut",
                            source: "SettingsView"
                        )
                        self.shortcutRecordingMessage = nil
                        self.activeShortcutRecordingTarget = target
                    }
                }
                .fluidButton(.secondary, size: .small)
                .frame(width: 82)
                .disabled(!capturing && (self.isRecordingAnyShortcut || (!enabledValue && hasShortcut)))

                if let onRemove {
                    Button("Remove") { onRemove() }
                        .fluidCompactButton(size: .small, foreground: self.theme.palette.secondaryText)
                        .frame(width: 82)
                        .disabled(!hasShortcut || self.isRecordingAnyShortcut)
                } else {
                    Color.clear.frame(width: 82, height: 1)
                }

                if let isEnabled {
                    PrefSwitch(isOn: isEnabled, label: "\(title) shortcut")
                        .disabled(self.isRecordingAnyShortcut || (requiresShortcutToEnable && !hasShortcut))
                } else {
                    Color.clear.frame(width: 44, height: 1)
                }
            }
        }
        .opacity(enabledValue ? 1 : 0.7)
    }

    // MARK: - Dictation output

    private var howTextLandsSection: some View {
        PrefSection(title: "How text lands") {
            PrefRows {
                PrefRow(
                    title: "Insertion method",
                    helper: SettingsStore.shared.textInsertionMode.description
                ) {
                    self.prefMenu(SettingsStore.shared.textInsertionMode.displayName, width: 190) {
                        Picker("", selection: Binding(
                            get: { SettingsStore.shared.textInsertionMode },
                            set: { SettingsStore.shared.textInsertionMode = $0 }
                        )) {
                            ForEach(SettingsStore.TextInsertionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                PrefRow(
                    title: "Copy to clipboard",
                    helper: "Keeps a copy of every transcription on the clipboard as a backup."
                ) {
                    PrefSwitch(isOn: self.copyToClipboardBinding, label: "Copy to clipboard")
                }

                PrefRow(
                    title: "Space between dictations",
                    helper: "Adds spacing so consecutive dictations chain without pressing the spacebar."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.continuousDictationSpacingEnabled },
                            set: { SettingsStore.shared.continuousDictationSpacingEnabled = $0 }
                        ),
                        label: "Space between dictations"
                    )
                }

                PrefRow(
                    title: "Smart capitalisation",
                    helper: "Reads the text before the cursor to decide whether to start capitalised."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.contextAwareCapitalizationEnabled },
                            set: { SettingsStore.shared.contextAwareCapitalizationEnabled = $0 }
                        ),
                        label: "Smart capitalisation"
                    )
                }

                PrefRow(
                    title: "Lowercase first letter",
                    helper: "Starts each transcription lowercase. Useful for search fields and casual text."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.gaavLowercaseFirstLetterEnabled },
                            set: { SettingsStore.shared.gaavLowercaseFirstLetterEnabled = $0 }
                        ),
                        label: "Lowercase first letter"
                    )
                }

                PrefRow(
                    title: "Remove trailing period",
                    helper: "Drops a final period from transcriptions."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.gaavRemoveTrailingPeriodEnabled },
                            set: { SettingsStore.shared.gaavRemoveTrailingPeriodEnabled = $0 }
                        ),
                        label: "Remove trailing period"
                    )
                }

                PrefRow(
                    title: "Slash commands and @ mentions",
                    helper: "“slash status” becomes /status; “tag Paul”, “mention Paul” and “at sign Paul” become @Paul. In chat apps “at Paul” also works."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.literalDictationFormattingEnabled },
                            set: { SettingsStore.shared.literalDictationFormattingEnabled = $0 }
                        ),
                        label: "Slash commands and @ mentions"
                    )
                }
            }
        }
    }

    private var whileYouDictateSection: some View {
        PrefSection(title: "While you dictate") {
            PrefRows {
                PrefRow(
                    title: "Skip silent recordings",
                    helper: "Drops recordings under four seconds that contain only silence. Off by default so quiet speech survives."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.skipSilentRecordingsEnabled },
                            set: { SettingsStore.shared.skipSilentRecordingsEnabled = $0 }
                        ),
                        label: "Skip silent recordings"
                    )
                }

                PrefRow(
                    title: "Pause media while transcribing",
                    helper: "Resumes only what \(self.appDisplayName) paused itself."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.pauseMediaDuringTranscription },
                            set: { SettingsStore.shared.pauseMediaDuringTranscription = $0 }
                        ),
                        label: "Pause media while transcribing"
                    )
                }

                PrefRow(
                    title: "Notify when AI enhancement fails",
                    helper: "A macOS notification when the raw transcription is typed instead."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.notifyAIProcessingFailures },
                            set: { SettingsStore.shared.notifyAIProcessingFailures = $0 }
                        ),
                        label: "Notify when AI enhancement fails"
                    )
                }

                PrefRow(
                    title: "Weekends don’t break the streak",
                    helper: "Saturday and Sunday are skipped when Stats counts your streak."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { SettingsStore.shared.weekendsDontBreakStreak },
                            set: { SettingsStore.shared.weekendsDontBreakStreak = $0 }
                        ),
                        label: "Weekends don’t break the streak"
                    )
                }
            }
        }
    }

    // MARK: - Audio devices

    private var audioDevicesSection: some View {
        PrefSection(
            title: "Audio devices",
            trailing: AnyView(
                Button("Refresh") {
                    self.refreshDevices()
                    // Update cached default device names on refresh
                    self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""
                    self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
                }
                .fluidButton(.secondary, size: .small)
            )
        ) {
            PrefRows {
                PrefRow(
                    title: "Use the macOS default microphone",
                    helper: self.microphoneSelectionMode == .system
                        ? "\(self.appDisplayName) follows the macOS default microphone. Turn this off to pin one and keep it selected while it is available."
                        : "\(self.appDisplayName) keeps your preferred microphone selected while it is available."
                ) {
                    PrefSwitch(
                        isOn: Binding(
                            get: { self.microphoneSelectionMode == .system },
                            set: { self.updateMicrophoneSelectionMode(useSystemDefault: $0) }
                        ),
                        label: "Use the macOS default microphone"
                    )
                    .disabled(self.asr.isRunning)
                }

                PrefRow(title: "Input", helper: nil, verticalPadding: 13) {
                    self.prefMenu(
                        self.inputDevices.isEmpty
                            ? "Loading…"
                            : (self.selectedInputDevice.map { self.inputDeviceTitle($0) } ?? "Loading…"),
                        width: 300,
                        isEnabled: !self.asr.isRunning
                    ) {
                        Picker("", selection: self.inputDeviceSelection) {
                            if self.inputDevices.isEmpty {
                                Text("Loading…").tag("")
                            } else {
                                ForEach(self.inputDevices, id: \.uid) { dev in
                                    Text(self.inputDeviceTitle(dev)).tag(dev.uid)
                                }
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                PrefRow(title: "Output", helper: nil, verticalPadding: 13) {
                    self.prefMenu(
                        self.outputDevices.isEmpty ? "Loading…" : self.selectedOutputTitle,
                        width: 300,
                        isEnabled: !self.asr.isRunning
                    ) {
                        Picker("", selection: self.outputDeviceSelection) {
                            if self.outputDevices.isEmpty {
                                Text("Loading…").tag("")
                            } else {
                                ForEach(self.outputDevices, id: \.uid) { dev in
                                    Text(self.outputDeviceTitle(dev)).tag(dev.uid)
                                }
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }

            self.microphoneQualityGuidance
        }
    }

    // MARK: - Filler words

    private var fillerWordsSection: some View {
        PrefSection(title: "Filler words") {
            PrefCard(padding: EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22), spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Removed from every transcription before it is typed. Lives with speech recognition, edited here.")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    FillerWordsEditor(showsCaption: false)
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        PrefSection(title: "Diagnostics & experiments") {
            PrefRows {
                PrefRowShell {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show debug logs in the app")
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("File logs are always collected. Crash diagnostics go to")
                                .basicsProse(14)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Library/Logs/Fluid/Fluid.log")
                                .basicsMono(12)
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                    }
                } control: {
                    HStack(spacing: 10) {
                        Button("Reveal log file") {
                            let url = FileLogger.shared.currentLogFileURL()
                            if FileManager.default.fileExists(atPath: url.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else {
                                DebugLogger.shared.info("Log file not found at \(url.path)", source: "SettingsView")
                            }
                        }
                        .fluidButton(.secondary, size: .medium)

                        PrefSwitch(
                            isOn: Binding(
                                get: { SettingsStore.shared.enableDebugLogs },
                                set: { SettingsStore.shared.enableDebugLogs = $0 }
                            ),
                            label: "Show debug logs in the app"
                        )
                    }
                }

                PrefRowShell {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            Text("Faster recording start")
                                .basicsLabel(15)
                                .foregroundStyle(self.theme.palette.primaryText)
                            PrefChip(text: "Experimental", tone: .muted)
                        }
                        Text("Starts listening sooner so your first word is less likely to be clipped. Turn it off if your microphone misbehaves.")
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } control: {
                    PrefSwitch(
                        isOn: Binding(
                            get: { self.settings.experimentalDirectAudioCaptureEnabled },
                            set: { enabled in
                                self.settings.experimentalDirectAudioCaptureEnabled = enabled
                                self.asr.refreshAudioCaptureBackendPreference()
                            }
                        ),
                        label: "Faster recording start"
                    )
                    .disabled(self.asr.isRunning)
                }
            }
        }
    }

    // MARK: - Menu helper

    @ViewBuilder
    private func prefMenu<Content: View>(
        _ title: String,
        width: CGFloat? = nil,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            PrefMenuChrome(title: title, width: width)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    // MARK: - Actions

    private func refreshRollbackState() {
        self.rollbackVersion = SimpleUpdater.shared.latestRollbackVersion() ?? ""
    }

    private func openIssueReportingPage() {
        guard let url = URL(string: "https://github.com/altic-dev/Fluid-oss/issues/new/choose") else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkForUpdates() {
        Task { @MainActor in
            do {
                let includePrerelease = SettingsStore.shared.betaReleasesEnabled
                try await SimpleUpdater.shared.checkAndUpdate(
                    owner: "altic-dev",
                    repo: "Fluid-oss",
                    includePrerelease: includePrerelease
                )
                self.presentInfoAlert(
                    title: "Update found",
                    message: "A new version is available and will be installed now."
                )
            } catch {
                if let pmkError = error as? PMKError, pmkError.isCancelled {
                    let isBeta = SettingsStore.shared.betaReleasesEnabled
                    self.presentInfoAlert(
                        title: isBeta ? "You’re up to date (beta)" : "You’re up to date",
                        message: isBeta
                            ? "You’re already running the latest build in the beta channel."
                            : "You’re already running the latest version of \(self.appDisplayName)."
                    )
                } else {
                    self.presentInfoAlert(
                        title: "Update check failed",
                        message: "Unable to check for updates. Please try again later.\n\n\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func performRollback() {
        guard !self.isRollingBack else { return }

        let targetVersion = self.rollbackVersion
        let infoText = targetVersion.isEmpty ? "your previously installed version" : targetVersion
        let confirm = NSAlert()
        confirm.messageText = "Rollback to \(infoText)?"
        confirm.informativeText = "This restores the previous app version and relaunches \(self.appDisplayName)."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Rollback")
        confirm.addButton(withTitle: "Cancel")

        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        self.isRollingBack = true
        Task {
            defer {
                Task { @MainActor in
                    self.isRollingBack = false
                }
            }

            do {
                try await SimpleUpdater.shared.rollbackToLatestBackup()
                await MainActor.run {
                    let success = NSAlert()
                    success.messageText = "Rollback successful"
                    success.informativeText = "Rolled back to \(targetVersion). \(self.appDisplayName) will relaunch shortly."
                    success.alertStyle = .informational
                    success.addButton(withTitle: "OK")
                    success.addButton(withTitle: "Report bug")
                    let response = success.runModal()
                    if response == .alertSecondButtonReturn {
                        self.openIssueReportingPage()
                    }
                }
            } catch {
                await MainActor.run {
                    let fail = NSAlert()
                    fail.messageText = "Rollback failed"
                    fail.informativeText = error.localizedDescription
                    fail.alertStyle = .critical
                    fail.addButton(withTitle: "OK")
                    fail.runModal()
                    self.refreshRollbackState()
                }
            }
        }
    }

    private func exportBackup() {
        Task { await self.performBackupExport() }
    }

    private func performBackupExport() async {
        do {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = BackupService.shared.suggestedFilename()

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let document = await BackupService.shared.makeBackupDocument()
            let data = try BackupService.shared.encode(document)
            try data.write(to: url, options: .atomic)

            self.presentInfoAlert(
                title: "Backup exported",
                message: "Saved your \(self.appDisplayName) backup to:\n\(url.path)"
            )
        } catch {
            self.presentErrorAlert(
                title: "Backup export failed",
                message: error.localizedDescription
            )
        }
    }

    private func importBackup() {
        Task { await self.performBackupImport() }
    }

    private func performBackupImport() async {
        do {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.json]

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let data = try Data(contentsOf: url)
            let document = try BackupService.shared.decode(data)

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            let confirm = NSAlert()
            confirm.messageText = "Import this backup?"
            confirm.informativeText = """
            This replaces your current settings, prompt profiles and stats history. API keys are not included and will not change.

            Exported \(formatter.string(from: document.exportedAt))
            """
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Import")
            confirm.addButton(withTitle: "Cancel")

            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            try await BackupService.shared.restore(document)
            self.syncLocalSettingsAfterBackupRestore()

            self.presentInfoAlert(
                title: "Backup imported",
                message: "Settings, prompt profiles and stats were restored successfully."
            )
        } catch {
            self.presentErrorAlert(
                title: "Backup import failed",
                message: error.localizedDescription
            )
        }
    }

    private func syncLocalSettingsAfterBackupRestore() {
        self.shareAnonymousAnalytics = SettingsStore.shared.shareAnonymousAnalytics
        self.pendingAnalyticsValue = nil
        self.showAreYouSureToStopAnalytics = false
        self.refreshAudioHistoryUsage()
    }

    private func refreshAudioHistoryUsage() {
        self.audioHistoryUsageBytes = DictationAudioHistoryStore.shared.audioUsageBytes()
        self.audioHistoryBudgetText = Self.audioBudgetText(for: SettingsStore.shared.audioHistoryBudgetGB)
    }

    private func applyAudioHistoryBudget() {
        let normalized = self.audioHistoryBudgetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            self.presentErrorAlert(
                title: "Invalid budget",
                message: "Enter a positive number of GB. Commas and dots both work."
            )
            self.refreshAudioHistoryUsage()
            return
        }

        let newBudget = max(0.1, value)
        let newBudgetBytes = DictationAudioHistoryStore.bytes(forGigabytes: newBudget)
        if self.audioHistoryUsageBytes > newBudgetBytes {
            let confirm = NSAlert()
            confirm.messageText = "Prune saved audio?"
            confirm.informativeText = """
            This budget is below current usage. The oldest saved audio is deleted first; every transcript stays.
            """
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Apply and prune")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else {
                self.refreshAudioHistoryUsage()
                return
            }
        }

        SettingsStore.shared.audioHistoryBudgetGB = newBudget
        let pruned = TranscriptionHistoryStore.shared.pruneAudioToBudget()
        self.refreshAudioHistoryUsage()
        if pruned > 0 {
            self.presentInfoAlert(
                title: "Audio pruned",
                message: "Removed audio from \(pruned) history entries."
            )
        }
    }

    private func deleteSavedAudio() {
        let confirm = NSAlert()
        confirm.messageText = "Delete saved audio?"
        confirm.informativeText = "This removes saved dictation audio only. Transcript history stays intact."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Delete audio")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let removed = TranscriptionHistoryStore.shared.deleteAllSavedAudio()
        self.refreshAudioHistoryUsage()
        self.presentInfoAlert(
            title: "Audio deleted",
            message: "Removed audio from \(removed) history entries."
        )
    }

    private func exportAudioZip() {
        do {
            guard TranscriptionHistoryStore.shared.entries.contains(where: {
                DictationAudioHistoryStore.shared.audioFileExists(for: $0)
            }) else {
                throw DictationAudioHistoryError.noAudioEntries
            }

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = DictationAudioHistoryStore.shared.suggestedAudioExportFilename()

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try DictationAudioHistoryStore.shared.exportAudioArchive(
                entries: TranscriptionHistoryStore.shared.entries,
                to: url
            )
            self.presentInfoAlert(
                title: "Audio export saved",
                message: "Saved your dictation audio export to:\n\(url.path)"
            )
        } catch {
            self.presentErrorAlert(title: "Audio export failed", message: error.localizedDescription)
        }
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

        let picker = NSAlert()
        picker.messageText = "Download a previous build"
        picker.informativeText = "No local rollback backup was found. Choose a recent release:"
        picker.alertStyle = .informational

        for option in options {
            picker.addButton(withTitle: option.version)
        }
        picker.addButton(withTitle: "All releases")
        picker.addButton(withTitle: "Cancel")

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

    private func applyAnalyticsConsentChange(_ enabled: Bool) {
        SettingsStore.shared.shareAnonymousAnalytics = enabled
        AnalyticsService.shared.setEnabled(enabled)
        AnalyticsService.shared.capture(.analyticsConsentChanged, properties: ["enabled": enabled])
    }

    private static func audioBudgetText(for value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private func audioHistoryUsageFraction() -> Double {
        let budget = SettingsStore.shared.audioHistoryBudgetBytes
        guard budget > 0 else { return 0 }
        return min(1, Double(self.audioHistoryUsageBytes) / Double(budget))
    }
}

// MARK: - Device helpers

private extension SettingsView {
    var selectedInputDevice: AudioDevice.Device? {
        self.inputDevices.first { $0.uid == self.selectedInputUID }
    }

    var selectedOutputTitle: String {
        guard let device = self.outputDevices.first(where: { $0.uid == self.selectedOutputUID }) else {
            return "Loading…"
        }
        return self.outputDeviceTitle(device)
    }

    func inputDeviceTitle(_ device: AudioDevice.Device) -> String {
        var annotations: [String] = []
        if self.cachedDefaultInputName.isEmpty == false,
           device.name == self.cachedDefaultInputName
        {
            annotations.append("System Default")
        }
        if device.isBuiltIn {
            annotations.append("Recommended")
        } else if device.isBluetooth {
            annotations.append("Reduces output quality")
        }

        guard annotations.isEmpty == false else { return device.name }
        return "\(device.name) (\(annotations.joined(separator: ", ")))"
    }

    func outputDeviceTitle(_ device: AudioDevice.Device) -> String {
        let isSystemDefault = !self.cachedDefaultOutputName.isEmpty && device.name == self.cachedDefaultOutputName
        return isSystemDefault ? "\(device.name) (System Default)" : device.name
    }

    @ViewBuilder
    var microphoneQualityGuidance: some View {
        if self.selectedInputDevice?.isBluetooth == true {
            PrefNote(
                text: "AirPods and other Bluetooth microphones reduce headphone audio quality. Use your Mac’s microphone or another non-Bluetooth mic.",
                tone: .warning
            )
        } else {
            PrefNote(
                text: "For the best audio quality, use your Mac’s microphone or another non-Bluetooth mic.",
                tone: .neutral
            )
        }
    }

    func updateMicrophoneSelectionMode(useSystemDefault: Bool) {
        let nextMode: SettingsStore.MicrophoneSelectionMode = useSystemDefault ? .system : .manual
        let currentSystemInputUID = AudioDevice.getDefaultInputDevice()?.uid
        let availableInputUIDs = Set(self.inputDevices.map(\.uid))
        let restoredSystemInputUID = SettingsStore.shared.setMicrophoneSelectionMode(
            nextMode,
            currentSystemInputUID: currentSystemInputUID,
            availableInputUIDs: availableInputUIDs
        )
        self.microphoneSelectionMode = nextMode

        if nextMode == .manual {
            if self.selectedInputUID.isEmpty,
               let defaultUID = currentSystemInputUID
            {
                self.selectedInputUID = defaultUID
                SettingsStore.shared.recordInputDeviceSelection(defaultUID)
            } else {
                SettingsStore.shared.recordInputDeviceSelection(self.selectedInputUID)
            }
        } else if let restoredSystemInputUID {
            self.selectedInputUID = restoredSystemInputUID
            _ = AudioDevice.setDefaultInputDevice(uid: restoredSystemInputUID)
        }
    }
}

// MARK: - Preferences primitives
//
// Boards 11 / 11b / 11c / 11d / 11e / 11f, measured rather than guessed:
// section eyebrow 11px +8% uppercase · row label Chillax 15 −5% · helper Karma 14
// at 160% · 1px hairline above every row and below the last · rows 12–14pt tall
// with a 2pt inset · a 24pt gutter between the label and the control lane.

/// The 1px separator that does all the dividing on this page.
private struct PrefHairline: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(self.theme.palette.separator)
            .frame(height: 1)
    }
}

/// Eyebrow + content. The eyebrow may carry one trailing control (Refresh).
private struct PrefSection<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let trailing: AnyView?
    private let content: Content

    init(title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text(self.title)
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                Spacer(minLength: 12)
                if let trailing = self.trailing {
                    trailing
                }
            }
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A hairline-separated run of rows. Each row draws its own top rule; the group
/// closes with one at the bottom.
private struct PrefRows<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            self.content
        }
        .overlay(alignment: .bottom) { PrefHairline() }
    }
}

/// Label lane (flex) + control lane (fixed), separated by 24pt.
private struct PrefRowShell<Label: View, Control: View>: View {
    private let verticalPadding: CGFloat
    private let label: Label
    private let control: Control

    init(
        verticalPadding: CGFloat = 14,
        @ViewBuilder label: () -> Label,
        @ViewBuilder control: () -> Control
    ) {
        self.verticalPadding = verticalPadding
        self.label = label()
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            self.label
                .frame(maxWidth: .infinity, alignment: .leading)
            self.control
                .layoutPriority(1)
        }
        .padding(.vertical, self.verticalPadding)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { PrefHairline() }
    }
}

private enum PrefTone {
    case neutral
    case brand
    case warning
    case muted
}

/// The standard row: title, optional helper sentence, optional footnote.
private struct PrefRow<Control: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let helper: String?
    private let footnote: String?
    private let footnoteTone: PrefTone
    private let verticalPadding: CGFloat
    private let control: Control

    init(
        title: String,
        helper: String? = nil,
        footnote: String? = nil,
        footnoteTone: PrefTone = .neutral,
        verticalPadding: CGFloat = 14,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.helper = helper
        self.footnote = footnote
        self.footnoteTone = footnoteTone
        self.verticalPadding = verticalPadding
        self.control = control()
    }

    var body: some View {
        PrefRowShell(verticalPadding: self.verticalPadding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)

                if let helper = self.helper {
                    Text(helper)
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let footnote = self.footnote {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if self.footnoteTone == .warning {
                            PrefStatusDot(tone: .warning)
                        }
                        Text(footnote)
                            .basicsProse(13)
                            .foregroundStyle(
                                self.footnoteTone == .warning
                                    ? self.theme.palette.warning
                                    : self.theme.palette.tertiaryText
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        } control: {
            self.control
        }
    }
}

/// Board § toggle. 44 × 26 pill, brand when on, borderStrong when off, flat
/// 20pt white knob. Label-less because it lives in the control lane.
private struct PrefSwitch: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            self.isOn.toggle()
        } label: {
            Capsule()
                .fill(
                    self.isOn
                        ? self.theme.palette.accent
                        : BasicsBorder.strong(self.theme, self.colorScheme)
                )
                .frame(width: 44, height: 26)
                .overlay(alignment: self.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(self.isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.18), value: self.isOn)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.isOn ? "On" : "Off")
        .accessibilityAddTraits(self.isOn ? [.isSelected] : [])
    }
}

/// The chrome behind every menu on this page: 32pt tall, radius 8, snow fill,
/// borderStrong hairline, 13pt Chillax label and a 12pt chevron.
private struct PrefMenuChrome: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var width: CGFloat?

    var body: some View {
        HStack(spacing: 9) {
            Text(self.title)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            if self.width != nil {
                Spacer(minLength: 4)
            }
            Image(systemName: "chevron.down")
                .font(BasicsTokens.display(10, .medium))
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(width: self.width, height: 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                )
        )
    }
}

/// − value + . Segmented 32pt control with hairlines between the three cells.
private struct PrefStepper: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let readout: String
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            self.stepButton("−", isEnabled: self.canDecrease, action: self.onDecrease)
            self.verticalRule
            Text(self.readout)
                .basicsMono(12)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(width: 84, height: 32)
            self.verticalRule
            self.stepButton("+", isEnabled: self.canIncrease, action: self.onIncrease)
        }
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.theme.palette.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(self.theme.palette.separator)
            .frame(width: 1, height: 32)
    }

    private func stepButton(_ glyph: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// A tinted slider with an optional monospaced readout in a fixed lane.
private struct PrefSlider: View {
    @Environment(\.theme) private var theme

    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var readout: String?
    var width: CGFloat = 140
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            Slider(
                value: self.$value,
                in: self.range,
                step: self.step,
                onEditingChanged: self.onEditingChanged
            )
            .controlSize(.small)
            .tint(self.theme.palette.accent)
            .frame(width: self.width)

            if let readout = self.readout {
                Text(readout)
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

/// The 6pt usage meter on the audio-storage card.
private struct PrefMeter: View {
    @Environment(\.theme) private var theme

    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(self.theme.palette.separator)
                Capsule()
                    .fill(self.theme.palette.accent)
                    .frame(width: max(0, min(1, self.fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// A grouped moment: snow fill, hairline border, radius 14.
private struct PrefCard<Content: View>: View {
    @Environment(\.theme) private var theme

    private let padding: EdgeInsets
    private let spacing: CGFloat
    private let content: Content

    init(
        padding: EdgeInsets = EdgeInsets(top: 17, leading: 24, bottom: 17, trailing: 24),
        spacing: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: self.spacing) {
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(self.padding)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }
}

/// 19pt uppercase chip — GRANTED / RECORDING… / EXPERIMENTAL, and the mono
/// version chip on the update hero.
private struct PrefChip: View {
    @Environment(\.theme) private var theme

    let text: String
    var tone: PrefTone = .muted
    var isMono: Bool = false
    var systemImage: String?

    private var ink: Color {
        switch self.tone {
        case .brand: return self.theme.palette.accent
        case .warning: return self.theme.palette.warning
        default: return self.theme.palette.secondaryText
        }
    }

    private var fill: Color {
        switch self.tone {
        case .brand: return self.theme.palette.accent.opacity(0.10)
        case .warning: return self.theme.palette.warning.opacity(0.12)
        default: return self.theme.palette.sidebarBackground
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(BasicsTokens.display(9, .medium))
            }
            if self.isMono {
                Text(self.text).basicsMono(11)
            } else {
                Text(self.text).basicsMicroLabel(10)
            }
        }
        .foregroundStyle(self.ink)
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Capsule().fill(self.fill))
    }
}

/// 8pt status dot.
private struct PrefStatusDot: View {
    @Environment(\.theme) private var theme

    var tone: PrefTone = .brand

    var body: some View {
        Circle()
            .fill(self.tone == .warning ? self.theme.palette.warning : self.theme.palette.accent)
            .frame(width: 8, height: 8)
    }
}

/// A quiet explanatory line under a section, with an icon.
private struct PrefNote: View {
    @Environment(\.theme) private var theme

    let text: String
    var tone: PrefTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: self.tone == .warning ? "exclamationmark.triangle" : "info.circle")
                .font(BasicsTokens.display(12, .medium))
                .foregroundStyle(
                    self.tone == .warning ? self.theme.palette.warning : self.theme.palette.tertiaryText
                )
            Text(self.text)
                .basicsProse(13)
                .foregroundStyle(
                    self.tone == .warning ? self.theme.palette.warning : self.theme.palette.secondaryText
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// The amber block that replaces a whole region when a permission is missing.
private struct PrefBanner: View {
    @Environment(\.theme) private var theme

    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(BasicsTokens.display(13, .medium))
                .foregroundStyle(self.theme.palette.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.warning)
                Text(self.message)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.warning.opacity(0.10))
        )
    }
}

/// The numbered "how to grant this" box.
private struct PrefInstructions: View {
    @Environment(\.theme) private var theme

    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.title)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .frame(width: 16, alignment: .trailing)
                        Text(step)
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.windowBackground)
        )
    }
}

/// The mono key pill on a shortcut row, and its amber capture state.
private struct PrefShortcutPill: View {
    @Environment(\.theme) private var theme

    let text: String
    var isCapturing: Bool = false
    var isMuted: Bool = false

    var body: some View {
        Text(self.text)
            .basicsMono(12)
            .foregroundStyle(self.ink)
            .lineLimit(1)
            .frame(width: 110, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(self.isCapturing ? self.theme.palette.warning.opacity(0.12) : self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                self.isCapturing ? self.theme.palette.warning.opacity(0.55) : self.theme.palette.cardBorder,
                                lineWidth: 1
                            )
                    )
            )
    }

    private var ink: Color {
        if self.isCapturing { return self.theme.palette.warning }
        return self.isMuted ? self.theme.palette.tertiaryText : self.theme.palette.primaryText
    }
}

/// A bordered field shell — the budget input.
private struct PrefFieldChrome<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private let width: CGFloat
    private let content: Content

    init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        self.content
            .padding(.horizontal, 12)
            .frame(width: self.width, height: 32)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                    )
            )
    }
}

/// The accent-colour swatch: 22pt dot in a 34pt tap target, brand ring when picked.
private struct AccentSwatch: View {
    @Environment(\.theme) private var theme

    let option: SettingsStore.AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Circle()
                .fill(Color(hex: self.option.hex) ?? self.theme.palette.accent)
                .frame(width: 22, height: 22)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .stroke(
                            self.isSelected ? self.theme.palette.accent : Color.clear,
                            lineWidth: 2
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(self.option.rawValue)
        .accessibilityAddTraits(self.isSelected ? [.isSelected] : [])
        .help(self.option.rawValue)
    }
}

/// System / Light / Dark. A muted track with a card-filled selected pill.
private struct PrefSegmentedControl<Value: Hashable>: View {
    @Environment(\.theme) private var theme

    struct Option: Identifiable {
        let id: String
        let title: String
        let value: Value
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(self.options) { option in
                let isSelected = self.selection == option.value
                Button {
                    self.selection = option.value
                } label: {
                    Text(option.title)
                        .basicsButtonLabel(13)
                        .foregroundStyle(
                            isSelected ? self.theme.palette.primaryText : self.theme.palette.secondaryText
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(
                            Capsule()
                                .fill(isSelected ? self.theme.palette.cardBackground : Color.clear)
                                .overlay(
                                    Capsule().stroke(
                                        isSelected ? self.theme.palette.cardBorder : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(Capsule().fill(self.theme.palette.sidebarBackground))
    }
}

// MARK: - Scroll host

private final class SettingsPersistentScroller: NSScroller {
    override static var isCompatibleWithOverlayScrollers: Bool {
        false
    }
}

/// The page is hand-hosted so the scroller never auto-hides. Only the ground it
/// paints changed for the redesign: the detail pane is the card surface, and the
/// elastic overscroll area has to match it or the page flashes the window grey.
private struct SettingsPersistentScrollView<Content: View>: NSViewRepresentable {
    private let theme: AppTheme
    private let colorScheme: ColorScheme
    private let content: Content

    init(theme: AppTheme, colorScheme: ColorScheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.colorScheme = colorScheme
        self.content = content()
    }

    private var hostedContent: AnyView {
        AnyView(
            self.content
                .appTheme(self.theme)
                .environment(\.colorScheme, self.colorScheme)
        )
    }

    private var groundColor: NSColor {
        NSColor(self.theme.palette.contentBackground)
    }

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = self.groundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScroller = SettingsPersistentScroller()
        scrollView.verticalScroller?.isHidden = false
        scrollView.verticalScroller?.alphaValue = 1
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let hostingView = NSHostingView(rootView: self.hostedContent)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.required, for: .vertical)

        scrollView.documentView = hostingView
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        (scrollView.documentView as? NSHostingView<AnyView>)?.rootView = self.hostedContent
        scrollView.drawsBackground = true
        scrollView.backgroundColor = self.groundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        if !(scrollView.verticalScroller is SettingsPersistentScroller) {
            scrollView.verticalScroller = SettingsPersistentScroller()
        }
        scrollView.verticalScroller?.isHidden = false
        scrollView.verticalScroller?.alphaValue = 1
    }
}

// MARK: - Filler Words Editor

struct FillerWordsEditor: View {
    @State private var fillerWords: [String]
    @State private var newWord: String = ""
    @Environment(\.theme) private var theme

    private let showsCaption: Bool

    init(showsCaption: Bool = true) {
        self.showsCaption = showsCaption
        _fillerWords = State(initialValue: SettingsStore.shared.fillerWords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.showsCaption {
                Text("Removed from every transcription before it is typed.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            FlowLayout(spacing: 6) {
                ForEach(self.fillerWords, id: \.self) { word in
                    HStack(spacing: 5) {
                        Text(word)
                            .basicsLabel(12)
                        Button {
                            self.removeWord(word)
                        } label: {
                            Image(systemName: "xmark")
                                .font(BasicsTokens.display(9, .medium))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .accessibilityLabel("Remove \(word)")
                    }
                    .foregroundStyle(self.theme.palette.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(self.theme.palette.accent.opacity(0.10)))
                }
            }

            PrefHairline()

            HStack(spacing: 10) {
                PrefFieldChrome(width: 210) {
                    TextField("Add word", text: self.$newWord)
                        .textFieldStyle(.plain)
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .onSubmit { self.addWord() }
                }

                Button("Add") { self.addWord() }
                    .fluidButton(.secondary, size: .medium)
                    .disabled(self.newWord.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer(minLength: 12)

                Button("Reset to defaults") {
                    self.fillerWords = SettingsStore.defaultFillerWords
                    SettingsStore.shared.fillerWords = self.fillerWords
                }
                .fluidButton(.secondary, size: .medium)
            }
        }
    }

    private func addWord() {
        let word = self.newWord.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty, !self.fillerWords.contains(word) else { return }
        self.fillerWords.append(word)
        SettingsStore.shared.fillerWords = self.fillerWords
        self.newWord = ""
    }

    private func removeWord(_ word: String) {
        self.fillerWords.removeAll { $0 == word }
        SettingsStore.shared.fillerWords = self.fillerWords
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    struct Cache {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var containerSize: CGSize = .zero
        var lastWidth: CGFloat = 0
    }

    var spacing: CGFloat = 8

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: Array(repeating: .zero, count: subviews.count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.containerSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let proposedWidth = proposal.width ?? 0
        let maxWidth = proposedWidth > 0 ? proposedWidth : 260
        let needsLayout = cache.positions.count != subviews.count || cache.lastWidth != maxWidth

        if needsLayout {
            cache.positions = []
            cache.positions.reserveCapacity(subviews.count)
            cache.sizes = Array(repeating: .zero, count: subviews.count)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size: CGSize
            if needsLayout {
                size = subviews[index].sizeThatFits(.unspecified)
                cache.sizes[index] = size
            } else {
                size = cache.sizes[index]
            }

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + self.spacing
                rowHeight = 0
            }
            if needsLayout {
                cache.positions.append(CGPoint(x: x, y: y))
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + self.spacing
        }

        cache.containerSize = CGSize(width: maxWidth, height: y + rowHeight)
        cache.lastWidth = maxWidth
    }
}

// MARK: - Analytics modal confirmation

struct AnalyticsConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.theme) private var theme

    private var contactInfoText: AttributedString {
        var text = AttributedString(
            "If you have concerns we would like to hear them: alticdev@gmail.com or file an issue on GitHub."
        )

        if let emailRange = text.range(of: "alticdev@gmail.com") {
            text[emailRange].link = URL(string: "mailto:alticdev@gmail.com")
            text[emailRange].foregroundColor = self.theme.palette.accent
        }

        if let githubRange = text.range(of: "GitHub") {
            text[githubRange].link = URL(string: "https://github.com/altic-dev/FluidVoice")
            text[githubRange].foregroundColor = self.theme.palette.accent
        }

        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stop sharing anonymous analytics?")
                .basicsLabel(18)
                .foregroundStyle(self.theme.palette.primaryText)

            Text("Anonymous usage data is how we work out which features matter. We never collect personal information — no audio, no transcription text — ever.")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(self.contactInfoText)
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()

                Button("Keep sharing") {
                    self.onCancel()
                }
                .fluidButton(.secondary, size: .medium)

                Button("Yes, stop") {
                    self.onConfirm()
                }
                .fluidButton(.destructive, size: .medium)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 440)
        .background(self.theme.palette.cardBackground)
    }
}
