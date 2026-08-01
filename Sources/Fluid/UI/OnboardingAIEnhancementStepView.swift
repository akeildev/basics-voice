import Foundation
import SwiftUI

/// Board `16 — Onboarding · 6 AI enhancement` (+ `· downloading`,
/// `· generic provider`, `· card states`, `· polish try-out`).
///
/// Two faces on one step: the before/after table with the provider card, and —
/// once the local model is loaded — the polish try-out that replaces the table
/// in place.
struct OnboardingAIEnhancementStepView: View {
    @Binding var finalText: String

    let railStep: Int
    let stepCount: Int
    let railName: String
    let language: VoiceEngineLanguage
    let shortcutDisplay: String
    let isTestReady: Bool
    let isRunning: Bool
    let isRecordingShortcut: Bool
    let shortcutRecordingMessage: String?
    let onBack: () -> Void
    let onSkip: () -> Void
    let onUseAIProvider: () -> Void
    let onFinishSetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = SettingsStore.shared

    @State private var isDownloadingPrivateAI = false
    @State private var isLoadingPrivateAI = false
    @State private var isDeletingPrivateAI = false
    @State private var privateAISetupProgress: PrivateAIModelDownloadProgress?
    @State private var privateAISetupErrorMessage: String?
    @State private var privateAIActionTask: Task<Void, Never>?
    @State private var privateAIActionID = UUID()
    @State private var shouldShowTryout = false
    @State private var selectedExampleID = Self.examples[0].id
    @State private var activeRecordingExampleID: String?
    @State private var playgroundOutputs: [String: String] = [:]

    private struct EnhancementExample: Identifiable {
        let id: String
        let raw: String
        let polished: String
    }

    /// Board 16 — the column grid the before/after table and the try-out share.
    private enum ExampleGrid {
        static let width: CGFloat = 760
        static let columnWidth: CGFloat = 334
        static let arrowWidth: CGFloat = 32
        static let columnSpacing: CGFloat = 20
    }

    private static let examples = [
        EnhancementExample(
            id: "message-format",
            raw: "Hey John, Newline, how are you doing today?",
            polished: "Hey John,\nHow are you doing today?"
        ),
        EnhancementExample(
            id: "correction",
            raw: "Hey, can we meet at five thirty tomorrow morning? Sorry, can you make it three thirty p.m. today?",
            polished: "Hey, can we meet at 3:30 PM today?"
        ),
        EnhancementExample(
            id: "list",
            raw: "Make a grocery list. First one is banana, second one is apple, third one is orange.",
            polished: "Grocery list:\n- banana\n- apple\n- orange"
        ),
    ]

    // MARK: - Derived state

    private var privateAIModel: PrivateAIRegisteredModel {
        PrivateAIModelRegistry.defaultModel
    }

    private var hasPrivateAIProvider: Bool {
        PrivateFeatures.privateAIProvider
    }

    private var privateAIProviderName: String {
        let displayName = PrivateAIProviderFeature.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty || displayName == "Private AI Provider" {
            return "Built-in AI"
        }
        return displayName
    }

    private var privateAIModelDisplayName: String {
        let displayName = self.privateAIModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? "AI model" : displayName
    }

    private var privateAIModelSizeText: String {
        guard let byteCount = self.privateAIModel.artifact.byteCount, byteCount > 0 else {
            return "Size shown before download"
        }
        return "~\(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))"
    }

    private var isPrivateAIInstalled: Bool {
        PrivateAIIntegrationService.isModelInstalled(self.privateAIModel)
    }

    private var isPrivateAIAvailable: Bool {
        PrivateAIProviderPromptFormat.isAvailable(settings: self.settings)
    }

    private var isPrivateAIBusy: Bool {
        self.isDownloadingPrivateAI || self.isLoadingPrivateAI || self.isDeletingPrivateAI
    }

    private var canNavigateOrMutate: Bool {
        !self.isPrivateAIBusy && !self.isRunning && !self.isRecordingShortcut
    }

    private var canDeletePrivateAIModel: Bool {
        self.isPrivateAIInstalled && PrivateAIIntegrationService.canRemoveInstalledModel(self.privateAIModel)
    }

    private var canFinishSetup: Bool {
        self.shouldShowTryout &&
            self.isTestReady &&
            !self.isRunning &&
            !self.isRecordingShortcut &&
            !self.isPrivateAIBusy
    }

    private var privateAISetupStatusText: String? {
        guard self.isDownloadingPrivateAI else { return nil }
        return PrivateAIModelDownloadProgressText.statusText(for: self.privateAISetupProgress)
    }

    private var privateAIDownloadByteText: String? {
        PrivateAIModelDownloadProgressText.byteText(for: self.privateAISetupProgress)
    }

    private var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    private var setupSubtitleText: String {
        if self.hasPrivateAIProvider {
            return "\(self.appDisplayName) can polish raw dictation locally with an optional built-in AI engine."
        }
        return "Optional: connect your own AI provider to polish dictation."
    }

    private var setupQuestionText: String {
        self.hasPrivateAIProvider
            ? "Want \(self.appDisplayName) to polish your dictation?"
            : "Want AI polishing?"
    }

    private var sectionTransition: AnyTransition {
        if self.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.006, anchor: .center))
        )
    }

    // MARK: - Body

    var body: some View {
        OnboardingStepShell(
            railStep: self.railStep,
            stepCount: self.stepCount,
            railName: self.railName,
            showsScrollIndicators: true
        ) {
            Group {
                if self.shouldShowTryout {
                    self.playgroundSection
                        .transition(self.sectionTransition)
                } else {
                    self.setupSection
                        .transition(self.sectionTransition)
                }
            }
            .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.28), value: self.shouldShowTryout)
        } footer: {
            self.footer
        }
        .onDisappear {
            self.cancelPrivateAIAction()
        }
        .onChange(of: self.finalText) { _, newValue in
            self.captureCurrentExampleOutput(newValue)
        }
        .onChange(of: self.isRunning) { _, isRunning in
            if isRunning {
                self.activeRecordingExampleID = self.selectedExampleID
            }
        }
    }

    // MARK: - Setup face

    private var setupSection: some View {
        VStack(spacing: 0) {
            Text("One more thing...")
                .basicsLabel(38)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(self.setupSubtitleText)
                .basicsProse(16)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            self.examplesTable
                .padding(.top, 20)

            Text(self.setupQuestionText)
                .basicsLabel(20)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .padding(.top, 20)
                .padding(.bottom, 10)

            self.setupChoiceCard

            Text("You can change this later in AI enhancements settings.")
                .basicsProse(14)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .padding(.top, 12)
        }
        .frame(width: ExampleGrid.width)
    }

    private var examplesTable: some View {
        VStack(spacing: 0) {
            self.exampleGridHeader(leftTitle: "Raw dictation (before)", rightTitle: "Polished (after)")
                .padding(.bottom, 10)

            ForEach(Self.examples) { example in
                HStack(alignment: .center, spacing: ExampleGrid.columnSpacing) {
                    Text(example.raw)
                        .basicsProse(13)
                        .foregroundStyle(BasicsTokens.Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: ExampleGrid.columnWidth, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(BasicsTokens.Ink.faint)
                        .frame(width: ExampleGrid.arrowWidth)

                    Text(example.polished)
                        .basicsProse(13)
                        .foregroundStyle(BasicsTokens.Ink.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: ExampleGrid.columnWidth, alignment: .leading)
                }
                .padding(.vertical, 9)
                .frame(width: ExampleGrid.width)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(BasicsTokens.Surface.border)
                        .frame(height: 1)
                }
            }
        }
        .frame(width: ExampleGrid.width)
    }

    private func exampleGridHeader(leftTitle: String, rightTitle: String) -> some View {
        HStack(spacing: ExampleGrid.columnSpacing) {
            Text(leftTitle)
                .basicsMicroLabel()
                .foregroundStyle(BasicsTokens.Ink.faint)
                .frame(width: ExampleGrid.columnWidth, alignment: .leading)

            Color.clear
                .frame(width: ExampleGrid.arrowWidth, height: 1)

            Text(rightTitle)
                .basicsMicroLabel()
                .foregroundStyle(BasicsTokens.Semantic.brand)
                .frame(width: ExampleGrid.columnWidth, alignment: .leading)
        }
        .frame(width: ExampleGrid.width)
    }

    @ViewBuilder
    private var setupChoiceCard: some View {
        if self.hasPrivateAIProvider {
            self.privateAIProviderCard
        } else {
            self.genericAIProviderCard
        }
    }

    // MARK: Generic provider card

    private var genericAIProviderCard: some View {
        OnboardingCard(
            padding: 0,
            shadow: BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 16, y: 10)
        ) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI provider")
                        .basicsLabel(19)
                        .foregroundStyle(BasicsTokens.Ink.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("Connect your own provider to polish dictation.")
                        .basicsProse(14)
                        .foregroundStyle(BasicsTokens.Ink.muted)

                    HStack(spacing: 16) {
                        self.modelFact("key", "Uses your API key")
                        self.modelFact("slider.horizontal.3", "Configurable later")
                        self.modelFact("network", "Cloud or local")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                OnboardingActionButton(
                    title: "Set up provider",
                    systemImage: "arrow.up.right",
                    tone: .primary,
                    height: 40,
                    horizontalPadding: 14,
                    labelSize: 14,
                    iconSize: 11,
                    width: 168,
                    cornerRadius: BasicsTokens.Radius.md
                ) {
                    self.cancelPrivateAIAction()
                    self.onUseAIProvider()
                }
                .disabled(!self.canNavigateOrMutate)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(width: ExampleGrid.width)
    }

    // MARK: Private AI card

    private var privateAIProviderCard: some View {
        OnboardingCard(
            padding: 0,
            shadow: BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 16, y: 10)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(self.privateAIProviderName)
                                .basicsLabel(19)
                                .foregroundStyle(BasicsTokens.Ink.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            OnboardingBadge(text: "Experimental", tone: .warning)

                            Text("Powered by \(self.privateAIModelDisplayName)")
                                .basicsMono(11)
                                .foregroundStyle(BasicsTokens.Ink.faint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        Text("Trained on 100K+ dictation data points to polish your words.")
                            .basicsProse(14)
                            .foregroundStyle(BasicsTokens.Ink.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(spacing: 16) {
                            self.modelFact("lock", "Runs locally. No API key.")
                            self.modelFact("internaldrive", "Download size \(self.privateAIModelSizeText)")
                            self.modelFact("timer", "May be slower on older Macs.")
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !self.showsProgressBelowFacts {
                        self.privateAIActionRow
                    }
                }

                if self.showsProgressBelowFacts {
                    self.privateAIActionRow
                        .padding(.top, 14)
                }

                self.privateAIStatusStrip
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(width: ExampleGrid.width)
    }

    /// While the model is downloading the board moves the action row under the
    /// facts so the progress bar can run the full width of the card.
    private var showsProgressBelowFacts: Bool {
        self.isDownloadingPrivateAI
    }

    private var privateAIActionRow: some View {
        HStack(spacing: 10) {
            self.primaryPrivateAIButton

            if self.isPrivateAIInstalled, self.isPrivateAIAvailable, !self.isPrivateAIBusy {
                OnboardingActionButton(
                    title: "Test \(self.appDisplayName)",
                    systemImage: "sparkles",
                    tone: .secondary,
                    height: 40,
                    horizontalPadding: 14,
                    labelSize: 14,
                    iconSize: 12,
                    cornerRadius: BasicsTokens.Radius.md,
                    action: self.activatePrivateAI
                )
                .disabled(!self.canNavigateOrMutate)
                .keyboardShortcut(.defaultAction)
            }

            if self.canDeletePrivateAIModel {
                OnboardingActionButton(
                    title: "Delete",
                    systemImage: "trash",
                    tone: .destructive,
                    height: 40,
                    horizontalPadding: 14,
                    labelSize: 14,
                    iconSize: 12,
                    width: 112,
                    cornerRadius: BasicsTokens.Radius.md,
                    action: self.deletePrivateAIModel
                )
                .disabled(!self.canNavigateOrMutate)
            }
        }
    }

    private var primaryPrivateAIButton: some View {
        let isActive = self.isPrivateAIInstalled && self.isPrivateAIAvailable

        return OnboardingActionButton(
            title: self.primaryPrivateAIButtonTitle,
            systemImage: self.primaryPrivateAIButtonIcon,
            tone: isActive && !self.isPrivateAIBusy ? .soft : .primary,
            height: 40,
            horizontalPadding: 14,
            labelSize: 14,
            iconSize: 12,
            width: 150,
            cornerRadius: BasicsTokens.Radius.md
        ) {
            self.handlePrivateAIPrimaryAction()
        }
        .disabled(!self.isPrimaryPrivateAIButtonEnabled)
        .keyboardShortcut(isActive ? nil : KeyboardShortcut.defaultAction)
    }

    private var primaryPrivateAIButtonTitle: String {
        if self.isDownloadingPrivateAI {
            return PrivateAIModelDownloadProgressText.buttonTitle(for: self.privateAISetupProgress)
        }
        if self.isLoadingPrivateAI {
            return "Loading..."
        }
        if self.isDeletingPrivateAI {
            return "Deleting..."
        }
        if !self.isPrivateAIInstalled {
            return "Download"
        }
        return self.isPrivateAIAvailable ? "Using" : "Use"
    }

    private var primaryPrivateAIButtonIcon: String? {
        if self.isPrivateAIBusy {
            return nil
        }
        if !self.isPrivateAIInstalled {
            return "arrow.down.circle.fill"
        }
        return self.isPrivateAIAvailable ? "checkmark.circle.fill" : "bolt.fill"
    }

    private var isPrimaryPrivateAIButtonEnabled: Bool {
        self.canNavigateOrMutate && !(self.isPrivateAIInstalled && self.isPrivateAIAvailable)
    }

    /// The helper line under the action row. Every string here is read off live
    /// service state — board `· card states` documents the full set.
    @ViewBuilder
    private var privateAIStatusStrip: some View {
        if self.isDownloadingPrivateAI {
            VStack(alignment: .leading, spacing: 7) {
                OnboardingProgressTrack(fraction: self.privateAISetupProgress?.fractionCompleted)

                Text(self.privateAISetupStatusText ?? "Downloading. This can take a few minutes.")
                    .basicsProse(13)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let byteText = self.privateAIDownloadByteText {
                    Text(byteText)
                        .basicsMono(11)
                        .foregroundStyle(BasicsTokens.Ink.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .padding(.top, 12)
            .transition(self.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        } else if let message = self.privateAISetupErrorMessage {
            Text(message)
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Semantic.danger)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        } else if self.isLoadingPrivateAI {
            Text(self.privateAIDownloadByteText ?? "Loading \(self.privateAIModelDisplayName)…")
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .padding(.top, 10)
        } else if !self.isPrivateAIInstalled {
            Text(self.privateAIModelSizeText)
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .padding(.top, 10)
        } else if self.isPrivateAIAvailable {
            Text("The polish try-out replaces the examples table once this is active.")
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .padding(.top, 10)
        } else {
            Text("Loaded on this Mac. Activate it to polish dictation.")
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .padding(.top, 10)
        }
    }

    private func modelFact(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(BasicsTokens.Ink.faint)

            Text(text)
                .basicsLabel(12)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    // MARK: - Try-out face

    private var playgroundSection: some View {
        VStack(spacing: 0) {
            Text("Let's polish your text.")
                .basicsLabel(38)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text("Choose an example, press \(self.shortcutDisplay), then dictate it naturally.")
                .basicsProse(16)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, 12)

            if let message = self.trimmedRecordingMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BasicsTokens.Semantic.warning)

                    Text(message)
                        .basicsProse(14)
                        .foregroundStyle(BasicsTokens.Ink.muted)
                        .lineLimit(1)
                }
                .padding(.top, 10)
            }

            VStack(spacing: 0) {
                self.exampleGridHeader(leftTitle: "Try saying this", rightTitle: "Polished output")
                    .padding(.bottom, 10)

                ForEach(Self.examples) { example in
                    self.playgroundExampleRow(example)
                }
            }
            .padding(.top, 20)

            Text(self.isTestReady
                ? "Looks good. Finish setup when you're ready."
                : "The polished result will appear on the selected row.")
                .basicsProse(14)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.top, 22)
        }
        .frame(width: ExampleGrid.width)
    }

    private var trimmedRecordingMessage: String? {
        guard self.isRecordingShortcut,
              let message = self.shortcutRecordingMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return nil
        }
        return message
    }

    private func playgroundExampleRow(_ example: EnhancementExample) -> some View {
        let isSelected = example.id == self.selectedExampleID
        let outputText = self.playgroundOutputs[example.id] ?? ""
        let hasOutput = !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isListening = self.activeRecordingExampleID == example.id && self.isRunning
        let shape = RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)

        return HStack(alignment: .center, spacing: ExampleGrid.columnSpacing) {
            Text(example.raw)
                .basicsProse(13)
                .foregroundStyle(
                    isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.muted
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: ExampleGrid.columnWidth, alignment: .leading)

            Image(systemName: isListening ? "waveform" : "arrow.right")
                .font(.system(size: 12, weight: isListening ? .semibold : .regular))
                .foregroundStyle(
                    isListening ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.faint
                )
                .frame(width: ExampleGrid.arrowWidth)

            HStack(alignment: .top, spacing: 8) {
                Group {
                    if hasOutput {
                        Text(outputText)
                            .basicsProse(13)
                            .foregroundStyle(BasicsTokens.Ink.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isListening {
                        Text("Listening...")
                            .basicsProse(13)
                            .foregroundStyle(BasicsTokens.Semantic.brand)
                    } else {
                        Text("Press \(self.shortcutDisplay) and speak this example.")
                            .basicsProse(13)
                            .foregroundStyle(BasicsTokens.Ink.faint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasOutput {
                    Button {
                        self.clearExampleOutput(example)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BasicsTokens.Ink.faint)
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityLabel("Clear polished output")
                }
            }
            .frame(width: ExampleGrid.columnWidth, alignment: .leading)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(width: ExampleGrid.width + 16)
        .background(shape.fill(isSelected ? BasicsTokens.Semantic.brandSoft : Color.clear))
        .overlay(alignment: .top) {
            if !isSelected {
                Rectangle()
                    .fill(BasicsTokens.Surface.border)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            self.selectExample(example)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try example. \(example.raw)")
    }

    // MARK: - Footer

    private var footer: some View {
        OnboardingFooterBar(canGoBack: self.canNavigateOrMutate, onBack: {
            self.cancelPrivateAIAction()
            self.onBack()
        }) {
            HStack(spacing: 12) {
                if self.shouldShowTryout {
                    OnboardingActionButton(
                        title: "Skip",
                        tone: .secondary,
                        labelColor: BasicsTokens.Ink.muted
                    ) {
                        self.cancelPrivateAIAction()
                        self.onFinishSetup()
                    }
                    .disabled(!self.canNavigateOrMutate)

                    OnboardingActionButton(
                        title: "Finish setup",
                        systemImage: "checkmark",
                        tone: .primary,
                        height: 48,
                        horizontalPadding: 28
                    ) {
                        self.cancelPrivateAIAction()
                        self.onFinishSetup()
                    }
                    .disabled(!self.canFinishSetup)
                    .keyboardShortcut(.defaultAction)
                } else {
                    OnboardingActionButton(
                        title: self.hasPrivateAIProvider ? "Use my own AI provider" : "Set up AI provider",
                        systemImage: "arrow.up.right",
                        tone: .secondary,
                        height: 48,
                        horizontalPadding: 28,
                        iconSize: 12
                    ) {
                        self.cancelPrivateAIAction()
                        self.onUseAIProvider()
                    }
                    .disabled(!self.canNavigateOrMutate)

                    OnboardingActionButton(
                        title: "Skip for now",
                        tone: .secondary,
                        height: 48,
                        horizontalPadding: 28,
                        labelColor: BasicsTokens.Ink.muted
                    ) {
                        self.cancelPrivateAIAction()
                        self.onSkip()
                    }
                    .disabled(!self.canNavigateOrMutate)
                }
            }
        }
    }

    // MARK: - Try-out state

    private func selectExample(_ example: EnhancementExample) {
        guard !self.isRunning else { return }
        guard self.selectedExampleID != example.id else { return }
        self.selectedExampleID = example.id
    }

    private func captureCurrentExampleOutput(_ text: String) {
        guard self.shouldShowTryout else { return }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let targetExampleID = self.activeRecordingExampleID ?? self.selectedExampleID
        self.playgroundOutputs[targetExampleID] = text
        self.selectedExampleID = targetExampleID
        self.activeRecordingExampleID = nil
    }

    private func clearExampleOutput(_ example: EnhancementExample) {
        self.playgroundOutputs.removeValue(forKey: example.id)

        if self.selectedExampleID == example.id {
            self.finalText = ""
        }
    }

    // MARK: - Private AI actions

    private func handlePrivateAIPrimaryAction() {
        guard self.canNavigateOrMutate else { return }

        guard PrivateFeatures.privateAIProvider,
              !self.privateAIModel.id.isEmpty
        else {
            self.onUseAIProvider()
            return
        }

        if self.isPrivateAIInstalled {
            self.activatePrivateAI()
        } else {
            self.downloadPrivateAIModel()
        }
    }

    private func downloadPrivateAIModel() {
        guard self.canNavigateOrMutate else { return }
        guard self.privateAIModel.canDownload else {
            self.privateAISetupErrorMessage = "Download is not available for this build."
            return
        }

        let model = self.privateAIModel
        let actionID = self.beginPrivateAIAction()
        self.privateAISetupErrorMessage = nil
        self.privateAISetupProgress = PrivateAIModelDownloadProgress(initialExpectedBytes: model.artifact.byteCount)
        self.isDownloadingPrivateAI = true

        self.privateAIActionTask = Task { @MainActor in
            do {
                _ = try await PrivateAIIntegrationService.prepareModel(model) { progress in
                    await MainActor.run {
                        guard self.privateAIActionID == actionID else { return }
                        self.privateAISetupProgress = progress.withFallbackExpectedBytes(model.artifact.byteCount)
                    }
                }
                guard self.privateAIActionID == actionID, !Task.isCancelled else { return }

                self.privateAISetupProgress = nil
                self.isDownloadingPrivateAI = false
            } catch is CancellationError {
                guard self.privateAIActionID == actionID else { return }
                self.privateAISetupProgress = nil
                self.isDownloadingPrivateAI = false
            } catch {
                guard self.privateAIActionID == actionID else { return }
                self.privateAISetupErrorMessage = Self.errorMessage(for: error)
                self.privateAISetupProgress = nil
                self.isDownloadingPrivateAI = false
            }
            if self.privateAIActionID == actionID {
                self.privateAIActionTask = nil
            }
        }
    }

    private func activatePrivateAI() {
        guard self.canNavigateOrMutate else { return }

        let model = self.privateAIModel
        let actionID = self.beginPrivateAIAction()
        self.privateAISetupErrorMessage = nil
        self.privateAISetupProgress = nil
        self.resetAITryoutDraft()
        self.isLoadingPrivateAI = true

        self.privateAIActionTask = Task { @MainActor in
            do {
                let status = try await PrivateAIIntegrationService.shared.loadModel(model)
                guard self.privateAIActionID == actionID, !Task.isCancelled else { return }

                guard status.state == .ready else {
                    throw PrivateAISetupError(message: status.message ?? "\(self.privateAIModelDisplayName) did not report ready.")
                }

                self.persistPrivateAIVerification(model)
                self.shouldShowTryout = true
                self.isLoadingPrivateAI = false
            } catch is CancellationError {
                guard self.privateAIActionID == actionID else { return }
                self.isLoadingPrivateAI = false
            } catch {
                guard self.privateAIActionID == actionID else { return }
                self.privateAISetupErrorMessage = Self.errorMessage(for: error)
                self.isLoadingPrivateAI = false
            }
            if self.privateAIActionID == actionID {
                self.privateAIActionTask = nil
            }
        }
    }

    private func deletePrivateAIModel() {
        guard self.canNavigateOrMutate, self.canDeletePrivateAIModel else { return }

        let model = self.privateAIModel
        let actionID = self.beginPrivateAIAction()
        self.privateAISetupErrorMessage = nil
        self.privateAISetupProgress = nil
        self.isDeletingPrivateAI = true

        self.privateAIActionTask = Task { @MainActor in
            do {
                try await PrivateAIIntegrationService.shared.unloadAndRemoveInstalledModel(model, reason: "onboarding-delete")
                guard self.privateAIActionID == actionID, !Task.isCancelled else { return }

                self.clearPrivateAIVerification()
                self.resetAITryoutDraft()
                self.shouldShowTryout = false
                self.isDeletingPrivateAI = false
            } catch is CancellationError {
                guard self.privateAIActionID == actionID else { return }
                self.isDeletingPrivateAI = false
            } catch {
                guard self.privateAIActionID == actionID else { return }
                self.privateAISetupErrorMessage = Self.errorMessage(for: error)
                self.isDeletingPrivateAI = false
            }
            if self.privateAIActionID == actionID {
                self.privateAIActionTask = nil
            }
        }
    }

    private func persistPrivateAIVerification(_ model: PrivateAIRegisteredModel) {
        let providerID = PrivateAIProviderFeature.shared.providerID
        let providerKey = DictationAIPostProcessingGate.providerKey(for: providerID)
        let modelIDs = PrivateAIModelRegistry.modelIDs()

        var availableModelsByProvider = self.settings.availableModelsByProvider
        availableModelsByProvider[providerKey] = modelIDs
        self.settings.availableModelsByProvider = availableModelsByProvider

        var selectedModelByProvider = self.settings.selectedModelByProvider
        selectedModelByProvider[providerKey] = model.id
        self.settings.selectedModelByProvider = selectedModelByProvider

        var fingerprints = self.settings.verifiedProviderFingerprints
        fingerprints[providerKey] = PrivateAIProviderFeature.verificationFingerprint(for: model.id)
        self.settings.verifiedProviderFingerprints = fingerprints

        self.settings.selectedProviderID = providerID
        self.settings.setDictationPromptSelection(.privateAI)
        self.settings.onboardingAISkipped = false
        UserDefaults.standard.set(model.id, forKey: PrivateAIIntegrationService.selectedModelDefaultsKey)
    }

    private func clearPrivateAIVerification() {
        let providerID = PrivateAIProviderFeature.shared.providerID
        let providerKey = DictationAIPostProcessingGate.providerKey(for: providerID)

        var fingerprints = self.settings.verifiedProviderFingerprints
        fingerprints.removeValue(forKey: providerKey)
        self.settings.verifiedProviderFingerprints = fingerprints

        if self.settings.selectedProviderID == providerID {
            self.settings.selectedProviderID = ""
        }

        if self.settings.dictationPromptSelection == .privateAI {
            self.settings.setDictationPromptSelection(.default)
        }

        var availableModelsByProvider = self.settings.availableModelsByProvider
        availableModelsByProvider.removeValue(forKey: providerKey)
        self.settings.availableModelsByProvider = availableModelsByProvider

        var selectedModelByProvider = self.settings.selectedModelByProvider
        selectedModelByProvider.removeValue(forKey: providerKey)
        self.settings.selectedModelByProvider = selectedModelByProvider

        self.settings.onboardingAISkipped = false
        UserDefaults.standard.removeObject(forKey: PrivateAIIntegrationService.selectedModelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: PrivateAIIntegrationService.localModelPathDefaultsKey)
    }

    private func resetAITryoutDraft() {
        self.finalText = ""
        self.activeRecordingExampleID = nil
        self.playgroundOutputs.removeAll()
    }

    private func beginPrivateAIAction() -> UUID {
        self.privateAIActionTask?.cancel()
        let actionID = UUID()
        self.privateAIActionID = actionID
        return actionID
    }

    private func cancelPrivateAIAction() {
        self.privateAIActionTask?.cancel()
        self.privateAIActionTask = nil
        self.privateAIActionID = UUID()
        self.isDownloadingPrivateAI = false
        self.isLoadingPrivateAI = false
        self.isDeletingPrivateAI = false
        self.privateAISetupProgress = nil
    }

    private struct PrivateAISetupError: LocalizedError {
        let message: String

        var errorDescription: String? {
            self.message
        }
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription
        {
            return description
        }
        return String(describing: error)
    }
}
