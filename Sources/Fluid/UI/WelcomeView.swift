//
//  WelcomeView.swift
//  fluid
//
//  Welcome and setup guide view
//

import AppKit
import AVFoundation
import SwiftUI

/// **Superseded — pending removal.**
///
/// This is the pre-redesign "Getting Started" page. Board `16 — Onboarding ·
/// Getting started` is implemented by `HomeView`, and the shell now routes the
/// `.welcome` sidebar item there, so nothing presents this view. It is left
/// compiling only so the sidebar/route cluster can delete the enum case and this
/// struct in one change; do not restyle it and do not add to it.
struct WelcomeView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService {
        self.appServices.asr
    }

    @ObservedObject private var settings = SettingsStore.shared
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var playgroundUsed: Bool
    var isTranscriptionFocused: FocusState<Bool>.Binding
    @State private var isHowToUseExpanded = false
    @State private var isCommandModeGuideExpanded = false
    @State private var isEditModeGuideExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    let accessibilityEnabled: Bool
    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void

    private var commandModeShortcutDisplay: String {
        self.settings.commandModeHotkeyShortcut?.displayString ?? "Not set"
    }

    private var writeModeShortcutDisplay: String {
        self.settings.rewriteModeHotkeyShortcut.displayString
    }

    private let playgroundSectionID = "welcome-playground-section"

    private var commandModeColor: Color {
        self.theme.palette.warning
    }

    private var editModeColor: Color {
        self.theme.palette.accent
    }

    private var isAIEnhancementReady: Bool {
        DictationAIPostProcessingGate.isProviderConfigured()
    }

    private var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill")
                            .font(self.theme.typography.titleIcon)
                            .foregroundStyle(self.theme.palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Getting Started" : "Welcome to FluidVoice")
                                .font(self.theme.typography.title)
                            Text("Talk anywhere. FluidVoice types for you.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    // Quick Setup Checklist
                    ThemedCard(style: .prominent) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Label("Quick Setup", systemImage: "checkmark.circle.fill")
                                    .font(self.theme.typography.sectionTitle)
                                    .foregroundStyle(self.theme.palette.accent)

                                Spacer()

                                Button {
                                    self.settings.resetOnboardingProgress()
                                    self.playgroundUsed = false
                                } label: {
                                    Label("Run Onboarding Again", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                SetupStepView(
                                    step: 1,
                                    // Consider model step complete if ready OR downloaded (even if not loaded)
                                    title: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Voice Model Ready" : "Download Voice Model",
                                    description: self.asr.isAsrReady
                                        ? "Speech recognition model is loaded and ready"
                                        : (
                                            self.asr.modelsExistOnDisk
                                                ? "Model downloaded, will load when needed"
                                                : "Download the AI model for offline voice transcription (~500MB)"
                                        ),
                                    status: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? .completed : .pending,
                                    action: {
                                        self.selectedSidebarItem = .voiceEngine
                                    },
                                    actionButtonTitle: "Go to Voice Engine",
                                    showActionButton: !(self.asr.isAsrReady || self.asr.modelsExistOnDisk)
                                )

                                SetupStepView(
                                    step: 2,
                                    title: self.asr.micStatus == .authorized ? "Microphone Permission Granted" : "Grant Microphone Permission",
                                    description: self.asr.micStatus == .authorized
                                        ? "FluidVoice has access to your microphone"
                                        : "Allow FluidVoice to access your microphone for voice input",
                                    status: self.asr.micStatus == .authorized ? .completed : .pending,
                                    action: {
                                        if self.asr.micStatus == .notDetermined {
                                            self.asr.requestMicAccess()
                                        } else if self.asr.micStatus == .denied {
                                            self.asr.openSystemSettingsForMic()
                                        }
                                    },
                                    actionButtonTitle: self.asr.micStatus == .notDetermined ? "Grant Access" : "Open Settings",
                                    showActionButton: self.asr.micStatus != .authorized
                                )

                                SetupStepView(
                                    step: 3,
                                    title: self.accessibilityEnabled ? "Accessibility Access Enabled" : "Enable Accessibility Access",
                                    description: self.accessibilityEnabled
                                        ? "Accessibility permission granted for typing into apps"
                                        : "Drag \(self.appDisplayName) into the Accessibility apps list as shown",
                                    status: self.accessibilityEnabled ? .completed : .pending,
                                    action: {
                                        self.openAccessibilitySettings()
                                    },
                                    actionButtonTitle: "Open Settings",
                                    showActionButton: !self.accessibilityEnabled
                                )

                                SetupStepView(
                                    step: 4,
                                    title: self.isAIEnhancementReady ? "AI Enhancement Configured" : "Set Up AI Enhancement (Optional)",
                                    description: self.isAIEnhancementReady
                                        ? "AI-powered text enhancement is ready to use"
                                        : "Configure API keys for AI-powered text enhancement",
                                    status: self.isAIEnhancementReady ? .completed : .pending,
                                    action: {
                                        self.selectedSidebarItem = .aiEnhancements
                                    },
                                    actionButtonTitle: "Configure AI"
                                )

                                SetupStepView(
                                    step: 5,
                                    title: self.playgroundUsed ? "Setup Tested Successfully" : "Test Your Setup",
                                    description: self.playgroundUsed
                                        ? "You've successfully tested voice transcription"
                                        : "Try the playground below to test your complete setup",
                                    status: self.playgroundUsed ? .completed : .pending,
                                    action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            proxy.scrollTo(self.playgroundSectionID, anchor: .top)
                                        }
                                        self.isTranscriptionFocused.wrappedValue = true
                                    },
                                    actionButtonTitle: "Go to Playground",
                                    showActionButton: !self.playgroundUsed
                                )
                                .id("playground-step-\(self.playgroundUsed)")
                            }
                        }
                        .padding(14)
                    }

                    // Test Playground
                    ThemedCard(hoverEffect: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Test Playground")
                                            .font(self.theme.typography.sectionTitle)
                                        Text("Click record, speak, and see your transcription")
                                            .font(self.theme.typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "text.bubble")
                                        .font(self.theme.typography.titleIcon)
                                }

                                Spacer()

                                if self.asr.isRunning {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 6, height: 6)
                                        Text("Recording...")
                                            .font(self.theme.typography.captionStrong)
                                            .foregroundStyle(.red)
                                    }
                                } else if !self.asr.finalText.isEmpty {
                                    Text("\(self.asr.finalText.count) characters")
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if self.settings.selectedSpeechModel == .parakeetTDT || self.settings.selectedSpeechModel == .parakeetTDTv2 {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(self.theme.palette.accent)
                                    Text(self.asr.wordBoostStatusText)
                                        .font(self.theme.typography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(self.theme.palette.contentBackground.opacity(0.6))
                                )
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                // Recording Control — centered button
                                HStack {
                                    Spacer()
                                    Button {
                                        if self.asr.isRunning {
                                            Task {
                                                await self.stopAndProcessTranscription()
                                            }
                                        } else {
                                            self.startRecording()
                                            self.playgroundUsed = true
                                            SettingsStore.shared.playgroundUsed = true
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: self.asr.isRunning ? "stop.fill" : "mic.fill")
                                            Text(self.asr.isRunning ? "Stop Recording" : "Start Recording")
                                        }
                                        .frame(maxWidth: 220)
                                    }
                                    .fluidButton(.primary, size: .large, isRecording: self.asr.isRunning)
                                    .buttonHoverEffect()
                                    .scaleEffect(!self.reduceMotion && self.asr.isRunning ? 1.02 : 1.0)
                                    .animation(self.reduceMotion ? nil : .spring(response: 0.3), value: self.asr.isRunning)
                                    .disabled(!self.asr.isAsrReady && !self.asr.isRunning)
                                    Spacer()
                                }

                                // Text Area
                                VStack(alignment: .leading, spacing: 8) {
                                    TextEditor(text: Binding(
                                        get: { self.asr.finalText },
                                        set: { self.asr.finalText = $0 }
                                    ))
                                    .font(self.theme.typography.body)
                                    .focused(self.isTranscriptionFocused)
                                    .frame(height: 120)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                self.asr.isRunning ? self.theme.palette.accent.opacity(0.06) : self.theme.palette.cardBackground
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(
                                                        self.asr.isRunning ? self.theme.palette.accent.opacity(0.4) : self.theme.palette.cardBorder.opacity(0.6),
                                                        lineWidth: self.asr.isRunning ? 2 : 1
                                                    )
                                            )
                                    )
                                    .scrollContentBackground(.hidden)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            if self.asr.isRunning {
                                                Image(systemName: "waveform")
                                                    .font(self.theme.typography.titleIcon)
                                                    .foregroundStyle(self.theme.palette.accent)
                                                Text("Listening... Speak now!")
                                                    .font(self.theme.typography.bodySmallStrong)
                                                    .foregroundStyle(self.theme.palette.accent)
                                                Text("Transcription will appear when you stop recording")
                                                    .font(self.theme.typography.caption)
                                                    .foregroundStyle(self.theme.palette.accent.opacity(0.7))
                                            } else if self.asr.finalText.isEmpty {
                                                Image(systemName: "text.bubble")
                                                    .font(self.theme.typography.titleIcon)
                                                    .foregroundStyle(.secondary.opacity(0.5))
                                                Text("Press record or your hotkey to begin")
                                                    .font(self.theme.typography.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .allowsHitTesting(false)
                                    )

                                    if !self.asr.finalText.isEmpty {
                                        HStack(spacing: 8) {
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                                            } label: {
                                                Label("Copy Text", systemImage: "doc.on.doc")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(self.theme.palette.accent)
                                            .controlSize(.small)

                                            Button("Clear & Test Again") {
                                                self.asr.finalText = ""
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .id(self.playgroundSectionID)

                    // Secondary guidance
                    ThemedCard(style: .subtle) {
                        VStack(alignment: .leading, spacing: 12) {
                            self.guideDisclosureRow(
                                title: "How to Use",
                                systemImage: "play.fill",
                                color: self.theme.palette.accent,
                                isExpanded: self.$isHowToUseExpanded
                            ) {
                                EmptyView()
                            } content: {
                                VStack(alignment: .leading, spacing: 10) {
                                    self.howToStep(number: 1, title: "Start Recording", description: "Press your hotkey (default: Right Option/Alt) or click the button")
                                    self.howToStep(number: 2, title: "Speak Clearly", description: "Speak naturally - works best in quiet environments")
                                    self.howToStep(number: 3, title: "Auto-Type Result", description: "Transcription is automatically typed into your focused app")
                                }
                            }

                            Divider().opacity(0.2)

                            self.guideDisclosureRow(
                                title: "Command Mode",
                                systemImage: "terminal.fill",
                                color: self.commandModeColor,
                                isExpanded: self.$isCommandModeGuideExpanded
                            ) {
                                self.featureBadge("New", color: self.commandModeColor)
                                self.featureBadge("Alpha", color: self.commandModeColor.opacity(0.75))
                            } content: {
                                self.commandModeGuide
                            }

                            Divider().opacity(0.2)

                            self.guideDisclosureRow(
                                title: "Edit Mode",
                                systemImage: "pencil.and.outline",
                                color: self.editModeColor,
                                isExpanded: self.$isEditModeGuideExpanded
                            ) {
                                self.featureBadge("New", color: self.editModeColor)
                            } content: {
                                self.editModeGuide
                            }
                        }
                        .padding(12)
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            // CRITICAL FIX: Refresh microphone and model status immediately on appear
            // This prevents the Quick Setup from showing stale status before ASRService.initialize() runs
            Task { @MainActor in
                // Check microphone status without triggering the full initialize() delay
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

                // Check if models exist on disk (async for accurate detection with AppleSpeechAnalyzerProvider)
                await self.asr.checkIfModelsExistAsync()
            }
        }
    }

    // MARK: - Helper Views

    private func guideDisclosureRow<Accessories: View, Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder accessories: () -> Accessories,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .frame(width: 16)

                    Label(title, systemImage: systemImage)
                        .font(self.theme.typography.sectionTitle)
                        .foregroundStyle(color)

                    accessories()

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isExpanded.wrappedValue ? "Expanded" : "Collapsed"))
            .accessibilityHint(Text("Activates to expand or collapse"))

            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 8)
                    .padding(.leading, 26)
            }
        }
    }

    private var commandModeGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Control your Mac with voice commands. Execute terminal commands, open apps, and more.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Open") {
                    self.selectedSidebarItem = .commandMode
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Getting Started")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.commandModeColor)

                HStack(spacing: 4) {
                    Text("Press")
                    self.keyboardBadge(self.commandModeShortcutDisplay)
                    Text("to open, speak your command, then press again to send.")
                }
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Examples")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.commandModeColor)
                self.commandModeExample(icon: "folder", text: "\"List files in my Downloads folder\"")
                self.commandModeExample(icon: "plus.rectangle.on.folder", text: "\"Create a folder called Projects on Desktop\"")
                self.commandModeExample(icon: "network", text: "\"What's my IP address?\"")
                self.commandModeExample(icon: "safari", text: "\"Open Safari\"")
            }

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(self.theme.typography.captionSmall)
                    .foregroundStyle(self.commandModeColor)
                Text("AI can make mistakes. Avoid destructive commands.")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editModeGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI-powered editing assistant. Write fresh content or edit selected text with voice.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Open AI Settings") {
                    self.selectedSidebarItem = .aiEnhancements
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Label("Configure an AI model provider in AI Settings before using Edit Mode.", systemImage: "info.circle")
                .font(self.theme.typography.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Create New Text")
                        .font(self.theme.typography.bodySmallStrong)
                        .foregroundStyle(self.editModeColor)

                    HStack(spacing: 4) {
                        Text("Press")
                        self.keyboardBadge(self.writeModeShortcutDisplay)
                        Text("and speak what you want to write.")
                    }
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.primary.opacity(0.8))

                    self.writeModeExample(text: "\"Write an email asking for time off\"")
                    self.writeModeExample(text: "\"Draft a thank you note\"")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Selected Text")
                        .font(self.theme.typography.bodySmallStrong)
                        .foregroundStyle(self.editModeColor)

                    HStack(spacing: 4) {
                        Text("Select text first, then press")
                        self.keyboardBadge(self.writeModeShortcutDisplay)
                        Text("and speak your instruction.")
                    }
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.primary.opacity(0.8))

                    self.writeModeExample(text: "\"Make this more formal\"")
                    self.writeModeExample(text: "\"Fix grammar and spelling\"")
                    self.writeModeExample(text: "\"Summarize this\"")
                }
            }
        }
    }

    private func howToStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(self.theme.typography.bodyStrong)
                Text(description)
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func featureBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(self.theme.typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func keyboardBadge(_ text: String) -> some View {
        Text(text)
            .font(self.theme.typography.captionStrong)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(self.theme.palette.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func commandModeExample(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(self.theme.typography.captionSmall)
                .foregroundStyle(self.commandModeColor.opacity(0.8))
                .frame(width: 14)
            Text(text)
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }

    private func writeModeExample(text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.editModeColor.opacity(0.6))
                .frame(width: 4, height: 4)
            Text(text)
                .font(self.theme.typography.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

// MARK: - Onboarding flow

/// Board "16 — Onboarding". Six steps on the Basics snow ground, all sharing
/// one shell: the step rail at the top, a centred content column, and the
/// hairline footer bar. The landing screen is the exception — no rail, no
/// footer, and the only screen that draws the brand wash and voice rings.
struct OnboardingFlowView: View {
    @EnvironmentObject var appServices: AppServices
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var asr: ASRService {
        self.appServices.asr
    }

    @ObservedObject private var settings = SettingsStore.shared

    @Binding var currentStep: Int
    let accessibilityEnabled: Bool
    let accessibilitySetupInProgress: Bool
    let markAISkipped: () -> Void
    let finishOnboarding: () -> Void
    let finishOnboardingAtGettingStarted: () -> Void
    let openAIEnhancementSettingsFromOnboarding: () -> Void
    let openAccessibilitySettings: () -> Void
    /// Part of the call site's contract in `ContentView`; nothing on board 16
    /// offers a restart, so no step reads it.
    let restartApp: () -> Void
    /// Same — held for the call site, unused by any board-16 control.
    let menuBarManager: MenuBarManager
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?
    /// Onboarding is a fixed light surface (board 16 has no dark variant), so
    /// it reads `BasicsTokens` directly rather than the adaptive palette.
    let theme: AppTheme

    @State private var selectedLanguageID = SettingsStore.shared.onboardingSelectedLanguageID
    @State private var selectedModelRouteID: String?
    @State private var isShowingAllLanguages = false
    @State private var isShowingOtherModelRoutes = false
    @State private var preparingModelRouteID: String?
    @State private var uninstallingModelRouteID: String?
    @State private var modelPreparationTask: Task<Void, Never>?
    @State private var languageSearchText = ""
    @FocusState private var isLanguageSearchFocused: Bool
    @State private var hasPlayedLandingWelcomeSound = false

    private enum Step: Int, CaseIterable {
        case landing = 0
        case language = 1
        case voiceModel = 2
        case permissions = 3
        case playground = 4
        case aiEnhancement = 5

        /// The rail's name. Landing has no rail, matching the board.
        var railName: String {
            switch self {
            case .landing:
                return ""
            case .language:
                return "Language"
            case .voiceModel:
                return "Voice engine"
            case .permissions:
                return "Access"
            case .playground:
                return "Try it"
            case .aiEnhancement:
                return "AI enhancement"
            }
        }
    }

    private var step: Step {
        Step(rawValue: self.currentStep) ?? .voiceModel
    }

    private var railStep: Int {
        self.step.rawValue + 1
    }

    private var stepCount: Int {
        Step.allCases.count
    }

    // MARK: - Derived state

    private var popularOnboardingLanguages: [VoiceEngineLanguage] {
        VoiceEngineLanguageCatalog.popularLanguages()
    }

    private var selectedOnboardingLanguage: VoiceEngineLanguage {
        VoiceEngineLanguageCatalog.language(id: self.selectedLanguageID)
            ?? VoiceEngineLanguageCatalog.language(id: "en")
            ?? VoiceEngineLanguage(id: "en", displayName: "English", aliases: [], isPopular: true)
    }

    private var searchedOnboardingLanguages: [VoiceEngineLanguage] {
        VoiceEngineLanguageCatalog.searchableLanguages(query: self.languageSearchText)
    }

    private var selectedLanguageRoutes: [VoiceEngineLanguageRoute] {
        VoiceEngineLanguageCatalog.routes(for: self.selectedOnboardingLanguage)
    }

    private var selectedOnboardingRoute: VoiceEngineLanguageRoute? {
        if let selectedModelRouteID,
           let selectedRoute = self.selectedLanguageRoutes.first(where: { $0.id == selectedModelRouteID })
        {
            return selectedRoute
        }

        if let selectedRoute = self.selectedLanguageRoutes.first(where: { self.isRouteSelectedInSettings($0) }) {
            return selectedRoute
        }

        return self.selectedLanguageRoutes.first
    }

    private var primaryDisplayedModelRoute: VoiceEngineLanguageRoute? {
        self.selectedLanguageRoutes.first
    }

    private var defaultDisplayedModelRoutes: [VoiceEngineLanguageRoute] {
        var routes: [VoiceEngineLanguageRoute] = []
        if let primaryDisplayedModelRoute {
            routes.append(primaryDisplayedModelRoute)
        }
        if let builtInRoute = self.defaultBuiltInModelRoute,
           !routes.contains(where: { $0.id == builtInRoute.id })
        {
            routes.append(builtInRoute)
        }
        return routes
    }

    private var defaultBuiltInModelRoute: VoiceEngineLanguageRoute? {
        guard self.selectedOnboardingLanguage.id == "en" else {
            return nil
        }

        return self.selectedLanguageRoutes.first { route in
            switch route.model {
            case .appleSpeech, .appleSpeechAnalyzer:
                return true
            default:
                return false
            }
        }
    }

    private var otherModelRoutes: [VoiceEngineLanguageRoute] {
        let defaultRouteIDs = Set(self.defaultDisplayedModelRoutes.map(\.id))
        return self.selectedLanguageRoutes.filter { !defaultRouteIDs.contains($0.id) }
    }

    private var recommendedModelReasonText: String {
        "Recommended for \(self.selectedOnboardingLanguage.displayName). You can see more options if needed."
    }

    private var otherModelsReasonText: String {
        guard let recommended = self.primaryDisplayedModelRoute else {
            return "Every model here runs on this Mac."
        }
        return "Every model here runs on this Mac. \(recommended.model.humanReadableName) stays the recommendation."
    }

    private var isVoiceModelReady: Bool {
        guard let route = self.selectedOnboardingRoute else {
            return false
        }
        return self.isOnboardingRouteReady(route)
    }

    private var isModelPreparationInProgress: Bool {
        guard self.step == .voiceModel else {
            return false
        }
        return self.preparingModelRouteID != nil
            || self.asr.hasActiveModelPreparation
            || self.asr.isCancellingModelPreparation
            || self.asr.isDownloadingModel
            || (self.asr.isLoadingModel && !self.asr.isAsrReady)
    }

    private var isMicrophoneReady: Bool {
        self.asr.micStatus == .authorized
    }

    private var isAccessibilityReady: Bool {
        self.accessibilityEnabled
    }

    private var isPermissionsReady: Bool {
        self.isMicrophoneReady && self.isAccessibilityReady
    }

    private var isAIReady: Bool {
        self.settings.onboardingAISkipped || DictationAIPostProcessingGate.isProviderConfigured()
    }

    private var isPlaygroundReady: Bool {
        self.settings.onboardingPlaygroundValidated || self.settings.onboardingPlaygroundSkipped
    }

    private var onboardingShortcutDisplay: String {
        let display = self.settings.primaryDictationShortcutDisplayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "your shortcut" : display
    }

    private var isRecordingAnyShortcut: Bool {
        self.activeShortcutRecordingTarget != nil
    }

    private var isRecordingPrimaryShortcut: Bool {
        self.activeShortcutRecordingTarget?.isPrimaryDictation == true
    }

    private var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    private var canNavigateBack: Bool {
        !self.isModelPreparationInProgress && !self.asr.isRunning && !self.isRecordingAnyShortcut
    }

    private var canContinue: Bool {
        guard !self.isModelPreparationInProgress else {
            return false
        }

        switch self.step {
        case .landing:
            return true
        case .language:
            return !self.selectedLanguageRoutes.isEmpty
        case .voiceModel:
            return self.isVoiceModelReady
        case .permissions:
            return self.isPermissionsReady
        case .aiEnhancement:
            return self.isAIReady
        case .playground:
            return self.isPlaygroundReady && !self.asr.isRunning && !self.isRecordingAnyShortcut
        }
    }

    // MARK: - Body

    var body: some View {
        self.stepContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BasicsTokens.Surface.bg.ignoresSafeArea())
            .onAppear {
                self.syncOnboardingSelectionFromSettings()
                self.playLandingWelcomeSoundIfNeeded()
                Task { @MainActor in
                    self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    await self.asr.checkIfModelsExistAsync()
                }
            }
            .onChange(of: self.currentStep) { _, _ in
                if self.step != .voiceModel {
                    self.cancelOnboardingModelPreparation()
                }
                self.playLandingWelcomeSoundIfNeeded()
            }
            .onDisappear {
                self.cancelOnboardingModelPreparation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                self.syncOnboardingSelectionFromSettings()
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch self.step {
        case .landing:
            self.landingStep
        case .language:
            self.languageStep
        case .voiceModel:
            self.voiceModelStep
        case .permissions:
            self.permissionsStep
        case .aiEnhancement:
            self.aiEnhancementStep
        case .playground:
            self.playgroundStep
        }
    }

    // MARK: - Shared chrome

    private func continueButton(title: String = "Continue") -> some View {
        OnboardingActionButton(
            title: title,
            systemImage: "arrow.right",
            tone: .primary,
            horizontalPadding: 30,
            action: self.handlePrimaryAction
        )
        .disabled(!self.canContinue)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Step 1 · Landing

    private var landingStep: some View {
        ZStack {
            FluidOnboardingLandingBackdrop()

            FluidOnboardingLandingHero(
                title: "Just speak.",
                accentTitle: "We'll handle the rest.",
                firstDetail: "Accurate. Fast. Private. Free.",
                secondDetail: "Built for creators, thinkers, and builders."
            ) {
                FluidOnboardingLandingPrimaryButton(title: "Next") {
                    self.goNext()
                }
                .frame(
                    width: FluidOnboardingLandingPrimaryButton.size.width,
                    height: FluidOnboardingLandingPrimaryButton.size.height
                )
            }
        }
    }

    private func playLandingWelcomeSoundIfNeeded() {
        guard self.step == .landing, !self.hasPlayedLandingWelcomeSound else { return }
        self.hasPlayedLandingWelcomeSound = true
        OnboardingSoundPlayer.shared.playWelcomeSound()
    }

    // MARK: - Step 2 · Language

    private var languageStep: some View {
        OnboardingStepShell(
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.step.railName
        ) {
            VStack(spacing: 0) {
                Text("What language will\nyou speak most?")
                    .basicsLabel(42)
                    .foregroundStyle(BasicsTokens.Ink.foreground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("We'll show the best voice engines for it.")
                    .basicsProse(16)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .padding(.top, 14)

                self.languageGrid
                    .padding(.top, 46)

                if self.isShowingAllLanguages {
                    self.allLanguagesPicker
                        .padding(.top, 12)
                }

                Text("You can change this later in Voice engine settings.")
                    .basicsProse(14)
                    .foregroundStyle(BasicsTokens.Ink.faint)
                    .padding(.top, 26)
            }
            .frame(width: 700)
        } footer: {
            OnboardingFooterBar(canGoBack: self.canNavigateBack, onBack: self.goBack) {
                self.continueButton()
            }
        }
    }

    private var languageGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(166), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(self.popularOnboardingLanguages) { language in
                    OnboardingLanguageTile(
                        title: language.popularDisplayName,
                        isSelected: self.selectedLanguageID == language.id
                    ) {
                        self.selectOnboardingLanguage(language)
                    }
                }
            }
            .frame(width: 700)

            self.otherLanguageCard
        }
    }

    private var otherLanguageCard: some View {
        let isSelected = !self.selectedOnboardingLanguage.isPopular

        return OnboardingOtherLanguageCard(
            title: isSelected ? self.selectedOnboardingLanguage.displayName : "Other",
            isSelected: isSelected,
            isExpanded: self.isShowingAllLanguages
        ) {
            self.toggleAllLanguagesPicker()
        }
    }

    private var allLanguagesPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BasicsTokens.Ink.faint)

                TextField(
                    "",
                    text: self.$languageSearchText,
                    prompt: Text("Search supported languages")
                        .foregroundStyle(BasicsTokens.Ink.faint)
                )
                .textFieldStyle(.plain)
                .basicsProse(14)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .focused(self.$isLanguageSearchFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)
                    .fill(BasicsTokens.Surface.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)
                    .stroke(
                        self.isLanguageSearchFocused
                            ? BasicsTokens.Semantic.brand
                            : BasicsTokens.Surface.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                self.isLanguageSearchFocused = true
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(self.searchedOnboardingLanguages) { language in
                        OnboardingLanguageSearchRow(
                            title: language.displayName,
                            isSelected: self.selectedLanguageID == language.id
                        ) {
                            self.selectOnboardingLanguage(language)
                        }
                    }
                }
            }
            .frame(height: 132)
        }
        .padding(12)
        .frame(width: 700)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(BasicsTokens.Surface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .stroke(BasicsTokens.Surface.border, lineWidth: 1)
        )
    }

    private func toggleAllLanguagesPicker() {
        if self.isShowingAllLanguages {
            self.isShowingAllLanguages = false
            self.isLanguageSearchFocused = false
            self.languageSearchText = ""
        } else {
            self.isShowingAllLanguages = true
            self.isLanguageSearchFocused = true
        }
    }

    private func selectOnboardingLanguage(_ language: VoiceEngineLanguage) {
        guard self.selectedLanguageID != language.id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.selectedLanguageID = language.id
            self.settings.onboardingSelectedLanguageID = language.id
            self.selectedModelRouteID = VoiceEngineLanguageCatalog.routes(for: language).first?.id
            self.isShowingOtherModelRoutes = false
            self.isLanguageSearchFocused = false
            if language.isPopular {
                self.isShowingAllLanguages = false
                self.languageSearchText = ""
            }
            self.resetTryoutValidationForSetupChange()
        }
    }

    private func syncOnboardingSelectionFromSettings() {
        let allRoutes = VoiceEngineLanguageCatalog.allLanguages()
            .flatMap { VoiceEngineLanguageCatalog.routes(for: $0) }

        let storedLanguageID = self.settings.onboardingSelectedLanguageID
        let storedLanguageRoutes = VoiceEngineLanguageCatalog.routes(forLanguageID: storedLanguageID)
        let route = storedLanguageRoutes.first { route in
            self.isRouteModelAndLanguageSettingsSelected(route)
        } ?? storedLanguageRoutes.first ?? allRoutes.first { route in
            self.isRouteModelAndLanguageSettingsSelected(route)
        }

        guard let route else {
            if self.selectedModelRouteID == nil {
                self.selectedModelRouteID = self.selectedLanguageRoutes.first?.id
            }
            return
        }

        guard self.selectedLanguageID != route.language.id || self.selectedModelRouteID != route.id else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.selectedLanguageID = route.language.id
            self.selectedModelRouteID = route.id
            self.isShowingOtherModelRoutes = false
            self.languageSearchText = ""
            self.isLanguageSearchFocused = false
        }
    }

    // MARK: - Step 3 · Voice engine

    private var voiceModelStep: some View {
        OnboardingStepShell(
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.step.railName,
            showsScrollIndicators: self.isShowingOtherModelRoutes
        ) {
            if self.isShowingOtherModelRoutes {
                self.otherModelRoutesSection
            } else {
                self.recommendedModelRoutesSection
            }
        } footer: {
            OnboardingFooterBar(canGoBack: self.canNavigateBack, onBack: self.goBack) {
                self.continueButton()
            }
        }
    }

    private var recommendedModelRoutesSection: some View {
        VStack(spacing: 0) {
            Text("Choose your\nvoice engine")
                .basicsLabel(42)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(self.recommendedModelReasonText)
                .basicsProse(16)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            OnboardingChip(text: self.selectedOnboardingLanguage.displayName)
                .padding(.top, 16)

            HStack(alignment: .top, spacing: 20) {
                ForEach(self.defaultDisplayedModelRoutes) { route in
                    self.onboardingRouteCard(for: route)
                }
            }
            .padding(.top, 30)

            if self.isModelPreparationInProgress {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BasicsTokens.Ink.faint)

                    Text("Initial preparation can take a while to get your Mac ready for near-instant transcription.")
                        .basicsProse(13)
                        .foregroundStyle(BasicsTokens.Ink.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(BasicsTokens.Surface.muted))
                .padding(.top, 20)
            }

            if !self.otherModelRoutes.isEmpty {
                OnboardingActionButton(
                    title: "Show other models",
                    systemImage: "chevron.down",
                    tone: .quiet,
                    height: 34,
                    horizontalPadding: 14,
                    labelSize: 13,
                    iconSize: 10,
                    labelColor: BasicsTokens.Ink.muted
                ) {
                    self.toggleOtherModelRoutes()
                }
                .disabled(self.isModelPreparationInProgress)
                .padding(.top, self.isModelPreparationInProgress ? 12 : 22)
            }

            Text("You can switch models later in Voice engine settings.")
                .basicsProse(14)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .padding(.top, 14)
        }
        .frame(width: 700)
    }

    private var otherModelRoutesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Text("Other models for \(self.selectedOnboardingLanguage.displayName)")
                    .basicsLabel(28)
                    .foregroundStyle(BasicsTokens.Ink.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 12)

                OnboardingActionButton(
                    title: "Hide other models",
                    systemImage: "chevron.up",
                    tone: .quiet,
                    height: 34,
                    horizontalPadding: 14,
                    labelSize: 13,
                    iconSize: 10,
                    labelColor: BasicsTokens.Ink.muted
                ) {
                    self.toggleOtherModelRoutes()
                }
                .disabled(self.isModelPreparationInProgress)
            }

            Text(self.otherModelsReasonText)
                .basicsProse(14)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .padding(.top, 8)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(292), spacing: 20, alignment: .top), count: 2),
                spacing: 20
            ) {
                ForEach(self.otherModelRoutes) { route in
                    self.onboardingRouteCard(for: route)
                }
            }
            .padding(.top, 22)
        }
        .frame(width: 604, alignment: .leading)
    }

    private func toggleOtherModelRoutes() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            self.isShowingOtherModelRoutes.toggle()
        }
    }

    // MARK: Engine card

    private func onboardingRouteCard(for route: VoiceEngineLanguageRoute) -> some View {
        let model = route.model
        let isSelected = self.isOnboardingRouteSelected(route)
        let isRecommended = route.id == self.primaryDisplayedModelRoute?.id
        let isRouteActiveInSettings = self.isRouteSelectedInSettings(route)
        let isDownloaded = self.isOnboardingModelBundledOrInstalled(model)
            || (isRouteActiveInSettings && (self.asr.isAsrReady || self.asr.modelsExistOnDisk))
        let isPreparing = self.preparingModelRouteID == route.id
            || (isRouteActiveInSettings && (self.asr.isDownloadingModel || (self.asr.isLoadingModel && !self.asr.isAsrReady)))
        let isReady = self.isOnboardingRouteReady(route)
        let isUninstalling = self.uninstallingModelRouteID == route.id
        let areModelActionsBlocked = self.asr.isRunning
            || self.uninstallingModelRouteID != nil
            || self.preparingModelRouteID != nil
            || isPreparing
            || self.isModelPreparationInProgress
        let isBuiltInAppleModel = model == .appleSpeech || model == .appleSpeechAnalyzer

        return OnboardingCard(isSelected: isSelected, padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isRecommended {
                        OnboardingBadge(text: "Recommended", tone: .brand, systemImage: "checkmark.seal.fill")
                    }
                }
                .frame(height: 20, alignment: .leading)

                HStack(alignment: .top, spacing: 8) {
                    Text(model.humanReadableName)
                        .basicsLabel(20)
                        .foregroundStyle(BasicsTokens.Ink.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(BasicsTokens.Ink.faint)
                        .frame(width: 16, height: 16)
                        .help(self.onboardingModelTooltip(for: route))
                        .accessibilityLabel(self.onboardingModelTooltip(for: route))
                }
                .padding(.top, 12)

                Text(self.onboardingModelTagline(for: model))
                    .basicsProse(13)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                VStack(spacing: 12) {
                    OnboardingMeterRow(
                        systemImage: "bolt.fill",
                        label: "Speed",
                        value: model.speedPercent,
                        isActive: isSelected
                    )

                    OnboardingMeterRow(
                        systemImage: "target",
                        label: "Accuracy",
                        value: model.accuracyPercent,
                        isActive: isSelected
                    )
                }
                .padding(.top, 18)

                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BasicsTokens.Ink.faint)
                        .frame(width: 14)

                    Text("Download size")
                        .basicsLabel(12)
                        .foregroundStyle(BasicsTokens.Ink.muted)

                    Spacer(minLength: 8)

                    Text(model.downloadSize)
                        .basicsMono(11, weight: .medium)
                        .foregroundStyle(BasicsTokens.Ink.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 14)

                Spacer(minLength: 12)

                self.routeActionSlot(
                    route: route,
                    isRecommended: isRecommended,
                    isDownloaded: isDownloaded,
                    isPreparing: isPreparing,
                    isReady: isReady,
                    isUninstalling: isUninstalling,
                    isBuiltInAppleModel: isBuiltInAppleModel,
                    areModelActionsBlocked: areModelActionsBlocked
                )
            }
            .frame(width: 252, height: 252, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous))
        .onTapGesture {
            guard !areModelActionsBlocked else { return }
            self.selectOnboardingRoute(route)
        }
    }

    @ViewBuilder
    private func routeActionSlot(
        route: VoiceEngineLanguageRoute,
        isRecommended: Bool,
        isDownloaded: Bool,
        isPreparing: Bool,
        isReady: Bool,
        isUninstalling: Bool,
        isBuiltInAppleModel: Bool,
        areModelActionsBlocked: Bool
    ) -> some View {
        if isPreparing || isUninstalling {
            VStack(alignment: .leading, spacing: 10) {
                OnboardingProgressTrack(fraction: self.modelPreparationFraction(isUninstalling: isUninstalling))

                HStack(spacing: 8) {
                    Text(isUninstalling ? "Deleting..." : self.asr.modelPreparationStatusText)
                        .basicsMono(11)
                        .foregroundStyle(BasicsTokens.Ink.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    if isPreparing {
                        OnboardingActionButton(
                            title: self.asr.isCancellingModelPreparation ? "Cancelling…" : "Cancel",
                            systemImage: self.asr.isCancellingModelPreparation ? nil : "xmark",
                            tone: .secondary,
                            height: 32,
                            horizontalPadding: 12,
                            labelSize: 12,
                            iconSize: 10,
                            width: 100
                        ) {
                            self.cancelOnboardingModelPreparation()
                        }
                        .disabled(self.asr.isCancellingModelPreparation)
                    }
                }
            }
        } else if isReady {
            HStack(spacing: 8) {
                OnboardingActionButton(
                    title: "Active now",
                    systemImage: "checkmark",
                    tone: .soft,
                    height: 40,
                    horizontalPadding: 12,
                    labelSize: 14,
                    expands: true,
                    cornerRadius: BasicsTokens.Radius.md
                ) {}
                    .disabled(true)

                if !isBuiltInAppleModel {
                    self.routeDeleteButton(route: route, isDisabled: areModelActionsBlocked)
                }
            }
        } else if isDownloaded {
            HStack(spacing: 8) {
                OnboardingActionButton(
                    title: "Activate",
                    systemImage: "bolt.fill",
                    tone: .secondary,
                    height: 40,
                    horizontalPadding: 12,
                    labelSize: 14,
                    expands: true,
                    cornerRadius: BasicsTokens.Radius.md
                ) {
                    self.prepareOnboardingRoute(route)
                }
                .disabled(areModelActionsBlocked)

                if !isBuiltInAppleModel {
                    self.routeDeleteButton(route: route, isDisabled: areModelActionsBlocked)
                }
            }
        } else {
            OnboardingActionButton(
                title: "Download & activate",
                systemImage: "arrow.down.circle.fill",
                tone: isRecommended ? .primary : .secondary,
                height: 40,
                horizontalPadding: 12,
                labelSize: 14,
                expands: true,
                cornerRadius: BasicsTokens.Radius.md
            ) {
                self.prepareOnboardingRoute(route)
            }
            .disabled(areModelActionsBlocked)
        }
    }

    private func routeDeleteButton(route: VoiceEngineLanguageRoute, isDisabled: Bool) -> some View {
        OnboardingActionButton(
            title: "Delete",
            systemImage: "trash",
            tone: .destructive,
            height: 40,
            horizontalPadding: 12,
            labelSize: 14,
            expands: true,
            cornerRadius: BasicsTokens.Radius.md
        ) {
            self.uninstallOnboardingRoute(route)
        }
        .disabled(isDisabled)
    }

    /// `nil` renders the indeterminate bar — the phases that report no byte
    /// count (optimizing, loading, cancelling, deleting).
    private func modelPreparationFraction(isUninstalling: Bool) -> Double? {
        guard !isUninstalling, !self.asr.isCancellingModelPreparation else {
            return nil
        }
        guard self.asr.isDownloadingModel,
              self.asr.modelPreparationPhase == .downloading,
              let progress = self.asr.downloadProgress
        else {
            return nil
        }
        return progress
    }

    private func onboardingModelTooltip(for route: VoiceEngineLanguageRoute) -> String {
        let model = route.model
        var lines = ["\(self.onboardingModelSubtitle(for: model)) — \(model.downloadSize)"]
        if let badgeText = route.badgeText {
            lines.append(badgeText)
        }
        lines.append(model.cardDescription)
        return lines.joined(separator: "\n")
    }

    private func onboardingModelSubtitle(for model: SettingsStore.SpeechModel) -> String {
        switch model {
        case .parakeetTDT:
            return "Parakeet v3"
        case .parakeetTDTv2:
            return "Parakeet v2"
        case .parakeetRealtime:
            return "Parakeet Flash"
        case .cohereTranscribeSixBit:
            return "Cohere"
        case .nemotronStreaming:
            return "Nemotron Streaming"
        case .nemotronOffline:
            return "Nemotron Offline"
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLarge:
            return "Whisper"
        default:
            return model.displayName
        }
    }

    /// The one-line card subtitle from board 16 — the engine's name plus what
    /// choosing it actually costs the user.
    private func onboardingModelTagline(for model: SettingsStore.SpeechModel) -> String {
        switch model {
        case .parakeetTDT:
            return "Parakeet v3 · fastest, nothing leaves the Mac."
        case .parakeetTDTv2:
            return "Parakeet v2 · tuned for English accuracy."
        case .parakeetRealtime:
            return "Parakeet Flash · smallest download, quickest start."
        case .cohereTranscribeSixBit:
            return "Cohere · multilingual, larger download."
        case .nemotronStreaming:
            return "Nemotron Streaming · low-latency partial text."
        case .nemotronOffline:
            return "Nemotron Offline · highest accuracy, slower to run."
        case .appleSpeech, .appleSpeechAnalyzer:
            return "Built into macOS · nothing to download."
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLarge:
            return "Whisper · better with accents and background noise."
        default:
            return model.cardDescription
        }
    }

    // MARK: Engine state helpers

    private func isOnboardingRouteReady(_ route: VoiceEngineLanguageRoute) -> Bool {
        self.isRouteSelectedInSettings(route) && self.asr.isAsrReady
    }

    private func isOnboardingModelBundledOrInstalled(_ model: SettingsStore.SpeechModel) -> Bool {
        model.isInstalled
    }

    private func isOnboardingRouteSelected(_ route: VoiceEngineLanguageRoute) -> Bool {
        self.selectedOnboardingRoute?.id == route.id || self.isRouteSelectedInSettings(route)
    }

    private func isRouteSelectedInSettings(_ route: VoiceEngineLanguageRoute) -> Bool {
        guard route.model == self.settings.selectedSpeechModel else {
            return false
        }

        switch route.binding {
        case .automatic, .whisper:
            return self.settings.onboardingSelectedLanguageID == route.language.id
        case let .appleSpeech(localeIdentifier):
            return self.settings.selectedAppleSpeechLocaleIdentifier == localeIdentifier
        case let .cohere(language):
            return self.settings.selectedCohereLanguage == language
        case let .nemotron(language):
            return self.settings.selectedNemotronLanguage == language
        }
    }

    private func isRouteModelAndLanguageSettingsSelected(_ route: VoiceEngineLanguageRoute) -> Bool {
        guard route.model == self.settings.selectedSpeechModel else {
            return false
        }

        switch route.binding {
        case .automatic, .whisper:
            return true
        case let .appleSpeech(localeIdentifier):
            return self.settings.selectedAppleSpeechLocaleIdentifier == localeIdentifier
        case let .cohere(language):
            return self.settings.selectedCohereLanguage == language
        case let .nemotron(language):
            return self.settings.selectedNemotronLanguage == language
        }
    }

    private func selectOnboardingRoute(_ route: VoiceEngineLanguageRoute) {
        let oldModel = self.settings.selectedSpeechModel
        let oldAppleSpeechLocaleIdentifier = self.settings.selectedAppleSpeechLocaleIdentifier
        let oldCohereLanguage = self.settings.selectedCohereLanguage
        let oldNemotronLanguage = self.settings.selectedNemotronLanguage

        self.selectedModelRouteID = route.id
        VoiceEngineLanguageCatalog.apply(route, to: self.settings)

        let languageChanged: Bool
        switch route.binding {
        case .automatic, .whisper:
            languageChanged = false
        case .appleSpeech:
            languageChanged = oldAppleSpeechLocaleIdentifier != self.settings.selectedAppleSpeechLocaleIdentifier
        case .cohere:
            languageChanged = oldCohereLanguage != self.settings.selectedCohereLanguage
        case .nemotron:
            languageChanged = oldNemotronLanguage != self.settings.selectedNemotronLanguage
        }

        if oldModel != self.settings.selectedSpeechModel || languageChanged {
            self.resetTryoutValidationForSetupChange()
            self.asr.resetTranscriptionProvider()
        }
    }

    private func prepareOnboardingRoute(_ route: VoiceEngineLanguageRoute) {
        guard !self.asr.isRunning, !self.isModelPreparationInProgress, self.uninstallingModelRouteID == nil else { return }

        self.modelPreparationTask?.cancel()
        self.preparingModelRouteID = route.id
        self.selectOnboardingRoute(route)

        self.modelPreparationTask = Task { @MainActor in
            defer {
                self.preparingModelRouteID = nil
                self.modelPreparationTask = nil
            }

            do {
                try await self.asr.ensureAsrReady()
            } catch is CancellationError {
                DebugLogger.shared.info("Cancelled onboarding voice model setup for \(route.model.displayName)", source: "OnboardingFlowView")
            } catch {
                DebugLogger.shared.error("Failed to prepare onboarding voice model \(route.model.displayName): \(error)", source: "OnboardingFlowView")
                // Surface the failure in the UI instead of only logging it, so the user
                // isn't stuck at a disabled button. The shared ContentView alert (bound to
                // asr.showError) presents this during onboarding. See #355.
                self.asr.errorTitle = "Voice model setup failed"
                self.asr.errorMessage = error.localizedDescription
                self.asr.showError = true
            }
            guard !Task.isCancelled else { return }
            await self.asr.checkIfModelsExistAsync()
        }
    }

    private func cancelOnboardingModelPreparation() {
        self.modelPreparationTask?.cancel()
        self.asr.cancelModelPreparation()
    }

    private func uninstallOnboardingRoute(_ route: VoiceEngineLanguageRoute) {
        guard !self.asr.isRunning, !self.isModelPreparationInProgress, self.uninstallingModelRouteID == nil else { return }

        self.uninstallingModelRouteID = route.id

        Task { @MainActor in
            defer {
                self.uninstallingModelRouteID = nil
            }

            do {
                try await self.asr.clearModelCache(for: route.model)
                await self.asr.checkIfModelsExistAsync()
            } catch {
                DebugLogger.shared.error("Failed to delete onboarding voice model \(route.model.displayName): \(error)", source: "OnboardingFlowView")
                self.asr.errorTitle = "Model delete failed"
                self.asr.errorMessage = error.localizedDescription
                self.asr.showError = true
            }
        }
    }

    // MARK: - Step 4 · Access

    private var permissionsStep: some View {
        OnboardingStepShell(
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.step.railName
        ) {
            VStack(spacing: 0) {
                Text("Let \(self.appDisplayName)\nlisten and type")
                    .basicsLabel(42)
                    .foregroundStyle(BasicsTokens.Ink.foreground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Two quick permissions make dictation work anywhere.")
                    .basicsProse(16)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .padding(.top, 14)

                OnboardingCard(
                    padding: 0,
                    shadow: BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 14, y: 8)
                ) {
                    VStack(spacing: 0) {
                        self.microphonePermissionRow

                        Rectangle()
                            .fill(BasicsTokens.Surface.border)
                            .frame(height: 1)

                        self.accessibilityPermissionRow
                    }
                }
                .frame(width: 700)
                .padding(.top, 38)

                if !self.isAccessibilityReady {
                    Text("Already enabled it? \(self.appDisplayName) will update when macOS confirms access.")
                        .basicsProse(14)
                        .foregroundStyle(BasicsTokens.Ink.faint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                }
            }
            .frame(width: 700)
        } footer: {
            OnboardingFooterBar(canGoBack: self.canNavigateBack, onBack: self.goBack) {
                self.continueButton()
            }
        }
    }

    private var microphonePermissionRow: some View {
        self.permissionRow(
            title: self.isMicrophoneReady ? "Microphone is ready" : "Allow microphone",
            subtitle: self.isMicrophoneReady
                ? "\(self.appDisplayName) can hear your dictation."
                : "macOS will ask once. Click Allow to start dictating.",
            systemImage: "mic",
            isReady: self.isMicrophoneReady,
            statusTitle: self.isMicrophoneReady ? "Ready" : "Needed",
            actionTitle: self.microphoneActionButtonTitle,
            actionIsPrimary: self.asr.micStatus == .notDetermined,
            action: self.handleMicrophoneAction
        )
    }

    private var accessibilityPermissionRow: some View {
        self.permissionRow(
            title: self.accessibilityPermissionTitle,
            subtitle: self.accessibilityPermissionSubtitle,
            systemImage: "keyboard",
            isReady: self.isAccessibilityReady,
            statusTitle: self.accessibilityPermissionStatusTitle,
            actionTitle: self.accessibilityPermissionActionTitle,
            actionIsPrimary: false,
            action: self.openAccessibilitySettings
        )
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isReady: Bool,
        statusTitle: String,
        actionTitle: String,
        actionIsPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(isReady ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.foreground)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isReady ? BasicsTokens.Semantic.brandSoft : BasicsTokens.Surface.muted)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .basicsLabel(16)
                    .foregroundStyle(BasicsTokens.Ink.foreground)

                Text(subtitle)
                    .basicsProse(14)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingStatusPill(text: statusTitle, isReady: isReady)

            ZStack {
                if isReady {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(BasicsTokens.Semantic.brand))
                        .accessibilityHidden(true)
                } else {
                    OnboardingActionButton(
                        title: actionTitle,
                        systemImage: actionIsPrimary ? "hand.tap.fill" : "arrow.up.right",
                        tone: actionIsPrimary ? .primary : .secondary,
                        height: 36,
                        horizontalPadding: 12,
                        labelSize: 14,
                        iconSize: 11,
                        width: 150,
                        action: action
                    )
                }
            }
            .frame(width: 150, height: 36)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var microphoneActionButtonTitle: String {
        switch self.asr.micStatus {
        case .notDetermined:
            return "Allow"
        case .denied, .restricted:
            return "Open settings"
        default:
            return "Allow"
        }
    }

    private var accessibilityPermissionTitle: String {
        if self.isAccessibilityReady {
            return "Typing access is ready"
        }
        return self.accessibilitySetupInProgress ? "Finish accessibility access" : "Enable accessibility access"
    }

    private var accessibilityPermissionSubtitle: String {
        if self.isAccessibilityReady {
            return "\(self.appDisplayName) can place text into the app you're using."
        }
        if self.accessibilitySetupInProgress {
            return "Use the floating guide to drag \(self.appDisplayName) into the Accessibility apps list."
        }
        return "Open Settings, then use the floating guide to add \(self.appDisplayName)."
    }

    private var accessibilityPermissionStatusTitle: String {
        if self.isAccessibilityReady {
            return "Ready"
        }
        return self.accessibilitySetupInProgress ? "In settings" : "Needed"
    }

    private var accessibilityPermissionActionTitle: String {
        self.accessibilitySetupInProgress ? "Show guide" : "Open settings"
    }

    private func handleMicrophoneAction() {
        if self.asr.micStatus == .notDetermined {
            self.asr.requestMicAccess()
        } else {
            self.asr.openSystemSettingsForMic()
        }
    }

    // MARK: - Step 5 · Try it

    private var playgroundStep: some View {
        OnboardingStepShell(
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.step.railName
        ) {
            VStack(spacing: 0) {
                Text("\(self.appDisplayName) is ready.")
                    .basicsLabel(42)
                    .foregroundStyle(BasicsTokens.Ink.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Now let's try it out.")
                    .basicsLabel(42)
                    .foregroundStyle(BasicsTokens.Semantic.brand)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)

                OnboardingTryoutStepView(
                    finalText: Binding(
                        get: { self.asr.finalText },
                        set: { self.asr.finalText = $0 }
                    ),
                    language: self.selectedOnboardingLanguage,
                    shortcutDisplay: self.onboardingShortcutDisplay,
                    isReady: self.isPlaygroundReady,
                    isRunning: self.asr.isRunning,
                    isRecordingShortcut: self.isRecordingPrimaryShortcut,
                    shortcutRecordingMessage: self.isRecordingPrimaryShortcut ? self.shortcutRecordingMessage : nil,
                    onToggleShortcut: self.togglePrimaryShortcutRecording
                )
                .padding(.top, 34)
            }
            .frame(width: 700)
        } footer: {
            OnboardingFooterBar(canGoBack: self.canNavigateBack, onBack: self.goBack) {
                HStack(spacing: 12) {
                    OnboardingActionButton(
                        title: "Skip",
                        tone: .secondary,
                        labelColor: BasicsTokens.Ink.muted
                    ) {
                        self.settings.onboardingPlaygroundSkipped = true
                        self.goNext()
                    }
                    .disabled(self.asr.isRunning || self.isRecordingAnyShortcut)

                    self.continueButton()
                }
            }
        }
    }

    private func togglePrimaryShortcutRecording() {
        guard !self.asr.isRunning else { return }
        if self.isRecordingPrimaryShortcut {
            self.activeShortcutRecordingTarget = nil
            self.shortcutRecordingMessage = nil
        } else {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = .primaryDictation(.replace(0))
        }
    }

    private func resetTryoutValidationForSetupChange() {
        self.settings.onboardingPlaygroundValidated = false
        self.settings.onboardingPlaygroundSkipped = false
        self.settings.playgroundUsed = false
        self.asr.finalText = ""
    }

    // MARK: - Step 6 · AI enhancement

    private var aiEnhancementStep: some View {
        OnboardingAIEnhancementStepView(
            finalText: Binding(
                get: { self.asr.finalText },
                set: { self.asr.finalText = $0 }
            ),
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.step.railName,
            language: self.selectedOnboardingLanguage,
            shortcutDisplay: self.onboardingShortcutDisplay,
            isTestReady: self.isPlaygroundReady,
            isRunning: self.asr.isRunning,
            isRecordingShortcut: self.isRecordingPrimaryShortcut,
            shortcutRecordingMessage: self.isRecordingPrimaryShortcut ? self.shortcutRecordingMessage : nil,
            onBack: self.goBack,
            onSkip: {
                self.markAISkipped()
                self.finishOnboardingAtGettingStarted()
            },
            onUseAIProvider: self.openAIEnhancementSettingsFromOnboarding,
            onFinishSetup: self.finishOnboardingAtGettingStarted
        )
    }

    // MARK: - Navigation

    private func goBack() {
        self.activeShortcutRecordingTarget = nil
        self.shortcutRecordingMessage = nil
        self.currentStep = max(0, self.currentStep - 1)
    }

    private func goNext() {
        self.activeShortcutRecordingTarget = nil
        self.shortcutRecordingMessage = nil
        self.currentStep = min(Step.allCases.count - 1, self.currentStep + 1)
    }

    private func handlePrimaryAction() {
        guard !self.isModelPreparationInProgress else {
            return
        }

        if self.step == .language, let route = self.selectedOnboardingRoute {
            self.selectOnboardingRoute(route)
        }

        if self.step == .aiEnhancement {
            guard self.isAIReady else { return }
            self.finishOnboarding()
            return
        }
        self.goNext()
    }
}

// MARK: - Language pickers

/// Board `16 — Onboarding · 2 Language`. A 166×58 tile; selected is a brandSoft
/// fill with a doubled brand outline, which is the board's border + 1px ring.
private struct OnboardingLanguageTile: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        return Button(action: self.action) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(
                        self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.faint
                    )
                    .frame(width: 18)

                Text(self.title)
                    .basicsLabel(14)
                    .foregroundStyle(BasicsTokens.Ink.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                ZStack {
                    if self.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(BasicsTokens.Semantic.brand))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 12)
            .frame(width: 166, height: 58)
            .background(
                shape.fill(
                    self.isSelected
                        ? BasicsTokens.Semantic.brandSoft
                        : (self.isHovered ? BasicsTokens.Surface.muted : BasicsTokens.Surface.card)
                )
            )
            .overlay(
                shape.stroke(
                    self.isSelected
                        ? BasicsTokens.Semantic.brand
                        : (self.isHovered ? BasicsTokens.Surface.borderStrong : BasicsTokens.Surface.border),
                    lineWidth: self.isSelected ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.14), value: self.isHovered)
        .onHover { self.isHovered = $0 }
        .accessibilityLabel(self.title)
        .accessibilityValue(self.isSelected ? "Selected" : "")
    }
}

/// The full-width "Other" row that opens the searchable list of every supported
/// language. It carries the chosen language's name once one is picked.
private struct OnboardingOtherLanguageCard: View {
    let title: String
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        return Button(action: self.action) {
            HStack(spacing: 8) {
                Text(self.title)
                    .basicsLabel(14)
                    .foregroundStyle(
                        self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.muted
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.muted
                    )
            }
            .frame(width: 700, height: 48)
            .background(
                shape.fill(
                    self.isSelected
                        ? BasicsTokens.Semantic.brandSoft
                        : (self.isHovered ? BasicsTokens.Surface.muted : Color.clear)
                )
            )
            .overlay(
                shape.stroke(
                    self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Surface.border,
                    lineWidth: self.isSelected ? 2 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.14), value: self.isHovered)
        .onHover { self.isHovered = $0 }
        .accessibilityLabel("Other languages")
        .accessibilityValue(self.isExpanded ? "Expanded" : "Collapsed")
    }
}

/// One row of the all-languages list.
private struct OnboardingLanguageSearchRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)

        return Button(action: self.action) {
            HStack(spacing: 10) {
                Text(self.title)
                    .basicsLabel(13)
                    .foregroundStyle(
                        self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.foreground
                    )

                Spacer(minLength: 8)

                if self.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(BasicsTokens.Semantic.brand))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(
                shape.fill(
                    self.isSelected
                        ? BasicsTokens.Semantic.brandSoft
                        : (self.isHovered ? BasicsTokens.Surface.muted : Color.clear)
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { self.isHovered = $0 }
        .accessibilityLabel(self.title)
        .accessibilityValue(self.isSelected ? "Selected" : "")
    }
}
