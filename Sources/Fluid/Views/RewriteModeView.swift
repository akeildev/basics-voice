import SwiftUI

/// Board "06 — Rewrite mode" (`YI-0`), plus `DV2-0` (empty + how-to expanded)
/// and `EU7-0` (states).
///
/// The Swift type keeps its name and every persisted key stays `edit`-flavoured;
/// only the words a person reads say "Rewrite mode".
///
/// Layout: a fixed header + how-to band, a scrolling work area (original ↔
/// rewritten panes, the assistant error, live reasoning, and the custom-prompt
/// list), then a pinned composer.
struct RewriteModeView: View {
    @ObservedObject var service: RewriteModeService
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject var settings = SettingsStore.shared
    @EnvironmentObject var menuBarManager: MenuBarManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var onClose: (() -> Void)?

    @State private var inputText: String = ""
    @State private var showOriginal: Bool = true
    @State private var showHowTo: Bool = false
    @State private var isHoveringHowTo: Bool = false
    @State private var isThinkingExpanded: Bool = false

    /// The prompt that was selected at the moment the current rewrite was asked
    /// for. Read off the store at submit time — not a second source of truth.
    @State private var appliedPromptName: String?

    /// Derived from the shared AI Settings model pool, never invented.
    @State private var availableModels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.pageHeader
                .padding(.bottom, 18)

            self.howToSection

            self.workArea

            self.composer
                .padding(.top, 18)
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
        .onChange(of: self.asr.finalText) { _, newText in
            if !newText.isEmpty {
                self.inputText = newText
            }
        }
        .onChange(of: self.service.originalText) { _, _ in
            self.showOriginal = true
        }
        .onExitCommand {
            self.onClose?()
        }
        .onAppear {
            // Overlay mode is set centrally by ContentView.handleModeTransition().
            self.updateAvailableModels()
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Modes")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.accent)

                Text("Rewrite mode")
                    .basicsLabel(28)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text("Select text anywhere, hold the key, and say how it should change. Nothing selected means it writes something new instead.")
                    .basicsProse(15)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 700, alignment: .leading)

                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    Text("Rewrite mode is powered by your custom prompts.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RewriteIconButton(systemImage: "xmark") {
                self.onClose?()
            }
            .help("Close Rewrite mode")
        }
    }

    // MARK: - How to use

    private var shortcutDisplay: String {
        self.settings.rewriteModeHotkeyShortcut.displayString
    }

    private var howToSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.showHowTo.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(
                            self.showHowTo || self.isHoveringHowTo
                                ? self.theme.palette.primaryText
                                : self.theme.palette.accent
                        )

                    Text("How to use")
                        .basicsLabel(13)
                        .foregroundStyle(
                            self.isHoveringHowTo || self.showHowTo
                                ? self.theme.palette.primaryText
                                : self.theme.palette.secondaryText
                        )

                    Spacer(minLength: 0)

                    Image(systemName: self.showHowTo ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .padding(.horizontal, self.isHoveringHowTo ? 10 : 2)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.isHoveringHowTo ? self.theme.palette.sidebarBackground : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { self.isHoveringHowTo = hovering }
            }

            if self.showHowTo {
                self.howToPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .top) { self.hairline }
        .overlay(alignment: .bottom) { self.hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(self.theme.palette.cardBorder)
            .frame(height: 1)
    }

    private var howToPanel: some View {
        HStack(alignment: .top, spacing: 56) {
            self.howToColumn(
                title: "Create new text",
                lead: "Press",
                trail: "and say what you want written.",
                examples: [
                    "“Write an email asking for time off”",
                    "“Draft a thank you note”",
                ]
            )

            self.howToColumn(
                title: "Edit selected text",
                lead: "Select text, then press",
                trail: "and say your instruction.",
                examples: [
                    "“Make this more formal”",
                    "“Fix grammar and spelling”",
                    "“Summarize this”",
                ]
            )
        }
        .padding(.leading, 24)
        .padding(.trailing, 2)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }

    private func howToColumn(
        title: String,
        lead: String,
        trail: String,
        examples: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lead)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)

                RewriteKeyCap(text: self.shortcutDisplay)

                Text(trail)
                    .basicsProse(14)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(examples, id: \.self) { example in
                    Text(example)
                        .basicsProse(14)
                        .lineSpacing(5)
                        .foregroundStyle(self.theme.palette.primaryText)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Work area

    private var workArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if self.hasWork {
                    self.panes

                    if !self.service.rewrittenText.isEmpty {
                        self.rewriteActions
                    }
                } else {
                    self.emptyState
                }

                if let error = self.assistantError {
                    self.errorCard(error)
                }

                if self.service.isProcessing,
                   self.settings.showThinkingTokens,
                   !self.service.streamingThinkingText.isEmpty
                {
                    self.thinkingView
                }

                self.customPromptsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hasWork: Bool {
        !self.service.originalText.isEmpty || !self.service.rewrittenText.isEmpty
    }

    /// The last assistant turn only counts as an error when no rewrite came
    /// back — otherwise the same message IS the rewrite.
    private var assistantError: String? {
        guard self.service.rewrittenText.isEmpty,
              let last = self.service.conversationHistory.last,
              last.role == .assistant,
              !last.content.isEmpty
        else { return nil }
        return last.content
    }

    // MARK: - Panes

    private var panes: some View {
        HStack(alignment: .top, spacing: 20) {
            if !self.service.originalText.isEmpty {
                self.originalPane
                    .frame(
                        maxWidth: self.service.rewrittenText.isEmpty ? .infinity : 488,
                        alignment: .leading
                    )
            }

            if !self.service.rewrittenText.isEmpty {
                self.rewrittenPane
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Original text")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.secondaryText)

                Spacer(minLength: 0)

                if !self.service.rewrittenText.isEmpty {
                    Button(self.showOriginal ? "Hide" : "Show") {
                        withAnimation(.easeInOut(duration: 0.18)) { self.showOriginal.toggle() }
                    }
                    .buttonStyle(.plain)
                    .basicsButtonLabel(12)
                    .foregroundStyle(self.theme.palette.accent)
                }
            }

            Group {
                if self.showOriginal {
                    Text(self.service.originalText)
                        .basicsProse(14)
                        .lineSpacing(6)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        Text("Hidden — \(self.service.originalText.count) characters")
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(self.theme.palette.sidebarBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                            .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                    )
            )
        }
    }

    private var rewrittenPane: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Rewritten text")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.accent)

                if let applied = self.appliedPromptName {
                    Text(applied)
                        .basicsLabel(11)
                        .foregroundStyle(self.theme.palette.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 19)
                        .background(Capsule().fill(self.theme.palette.accent.opacity(0.10)))
                }

                Spacer(minLength: 0)
            }

            Text(self.service.rewrittenText)
                .basicsProse(14)
                .lineSpacing(6)
                .foregroundStyle(self.theme.palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .fill(self.theme.palette.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                                .stroke(self.theme.palette.accent.opacity(0.30), lineWidth: 1)
                        )
                )
        }
    }

    private var rewriteActions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button("Try again") {
                self.service.rewrittenText = ""
                self.appliedPromptName = nil
            }
            .fluidButton(.secondary, size: .medium)

            Button {
                self.service.acceptRewrite()
                self.onClose?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Replace original")
                }
            }
            .fluidButton(.accent, size: .medium)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.10))
                    .frame(width: 52, height: 52)
                Image(systemName: "text.bubble")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(self.theme.palette.accent)
            }

            Text("Nothing selected yet")
                .basicsLabel(18)
                .foregroundStyle(self.theme.palette.primaryText)

            Text("Ask for anything and it gets written — emails, replies, summaries, answers. Select text first and it rewrites that instead.")
                .basicsProse(14)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Error

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BasicsTokens.Semantic.danger)

            VStack(alignment: .leading, spacing: 4) {
                Text("The rewrite did not come back")
                    .basicsLabel(13)
                    .foregroundStyle(BasicsTokens.Semantic.danger)

                Text(message)
                    .basicsProse(13)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(BasicsTokens.Semantic.danger.opacity(0.07))
        )
    }

    // MARK: - Thinking

    private var thinkingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.isThinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(self.theme.palette.accent)

                    CommandShimmerText(text: "Thinking")

                    Spacer(minLength: 0)

                    Image(systemName: self.isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.isThinkingExpanded {
                ThinkingTranscript(text: self.service.streamingThinkingText, maxHeight: 150)
                    .frame(maxWidth: 700, alignment: .leading)
            } else {
                Text(self.thinkingPreview)
                    .basicsProse(12)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(maxWidth: 700, alignment: .leading)
            }
        }
    }

    private var thinkingPreview: String {
        let text = self.service.streamingThinkingText
        guard text.count > 100 else { return text }
        return String(text.prefix(100)) + "…"
    }

    // MARK: - Custom prompts

    /// The same store the AI enhancements → Prompts page edits. A prompt deleted
    /// there disappears here.
    private var editPrompts: [SettingsStore.DictationPromptProfile] {
        self.settings.dictationPromptProfiles.filter { $0.mode.normalized == .edit }
    }

    private var selectedEditPromptID: String? {
        self.settings.isEditPromptOff ? nil : self.settings.selectedEditPromptID
    }

    private var customPromptsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Custom prompts")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.tertiaryText)

                Spacer(minLength: 0)

                Button("Add prompt") {
                    AppNavigationRouter.shared.request(.aiEnhancements)
                }
                .buttonStyle(.plain)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.accent)
                .help("Opens AI enhancements → Prompts, where this list is edited.")
            }

            if self.editPrompts.isEmpty {
                self.emptyPromptList
            } else {
                VStack(spacing: 0) {
                    ForEach(self.editPrompts) { profile in
                        RewritePromptRow(
                            name: profile.name,
                            summary: Self.promptSummary(profile.prompt),
                            isSelected: self.selectedEditPromptID == profile.id
                        ) {
                            self.selectPrompt(profile)
                        }
                    }
                }
                .overlay(alignment: .bottom) { self.hairline }
            }
        }
    }

    private var emptyPromptList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No custom prompts yet")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            Text("Rewrite mode still works — just say the change in your own words.")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)

            Text("Saved prompts give you a one-tap version of the edits you ask for over and over.")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// One readable line of the prompt body — the profile text is whatever the
    /// user typed on the Prompts page, newlines and all.
    private static func promptSummary(_ prompt: String) -> String {
        prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Selecting a prompt is a real write: it is the profile Rewrite mode's
    /// system prompt resolves to on the next request. Tapping the selected row
    /// again turns custom edit prompts off and falls back to the default.
    private func selectPrompt(_ profile: SettingsStore.DictationPromptProfile) {
        if self.selectedEditPromptID == profile.id {
            self.settings.isEditPromptOff = true
        } else {
            self.settings.selectedEditPromptID = profile.id
            self.settings.isEditPromptOff = false
        }
    }

    // MARK: - Composer

    private var composerPlaceholder: String {
        self.service.originalText.isEmpty ? "Ask me to write or edit…" : "How should I edit this?"
    }

    private var composerHint: String {
        if self.service.isProcessing {
            return self.service.originalText.isEmpty
                ? "Writing…"
                : "Rewriting \(self.service.originalText.count) characters…"
        }
        if self.service.originalText.isEmpty {
            return "Nothing is selected, so this writes something new."
        }
        return "Pick a custom prompt or say the change in your own words."
    }

    private var canSubmit: Bool {
        !self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.service.isProcessing
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if self.inputText.isEmpty {
                        Text(self.composerPlaceholder)
                            .basicsProse(15)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: self.$inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .basicsProse(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1 ... 4)
                        .onSubmit(self.submitRequest)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if self.service.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .fixedSize()
                }

                Button(action: self.toggleRecording) {
                    Image(systemName: self.asr.isRunning ? "stop.fill" : "mic")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            self.asr.isRunning ? Color.white : self.theme.palette.primaryText
                        )
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(
                                    self.asr.isRunning
                                        ? BasicsTokens.Semantic.danger
                                        : self.theme.palette.cardBackground
                                )
                                .overlay(
                                    Circle().stroke(
                                        self.asr.isRunning ? Color.clear : self.theme.palette.cardBorder,
                                        lineWidth: 1
                                    )
                                )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(self.asr.isRunning ? "Stop dictating the instruction" : "Dictate the instruction")

                Button(action: self.submitRequest) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                self.canSubmit
                                    ? self.theme.palette.accent
                                    : self.theme.palette.accent.opacity(0.35)
                            )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!self.canSubmit)
                .help("Send")
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)

            self.composerFooter
        }
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .stroke(self.theme.palette.cardBorder, lineWidth: 1)
        )
        .basicsShadows([
            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.04), radius: 1, y: 1),
            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 12, y: 8),
        ])
    }

    private var composerFooter: some View {
        HStack(spacing: 16) {
            Text(self.composerHint)
                .basicsProse(12)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .lineLimit(2)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                SearchableProviderPicker(
                    builtInProviders: self.builtInProvidersList,
                    savedProviders: self.settings.savedProviders.filter { !self.isPrivateAIProviderID($0.id) },
                    selectedProviderID: Binding(
                        get: { self.settings.rewriteModeSelectedProviderID },
                        set: { newValue in
                            guard !self.isPrivateAIProviderID(newValue) else { return }
                            self.settings.rewriteModeSelectedProviderID = newValue
                            self.updateAvailableModels()
                        }
                    ),
                    controlWidth: 140,
                    controlHeight: 30
                )

                SearchableModelPicker(
                    models: self.availableModels,
                    selectedModel: Binding(
                        get: { self.settings.rewriteModeSelectedModel ?? self.availableModels.first ?? "" },
                        set: { self.settings.rewriteModeSelectedModel = $0 }
                    ),
                    onRefresh: nil,
                    isRefreshing: false,
                    selectionEnabled: !self.availableModels.isEmpty,
                    controlWidth: 180,
                    controlHeight: 30
                )
            }
            .fixedSize()
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.theme.palette.sidebarBackground)
        .overlay(alignment: .top) { self.hairline }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if self.asr.isRunning {
            Task {
                _ = await self.asr.stop()
                _ = self.asr.consumeLastCompletedAudioSnapshot()
            }
        } else {
            Task { await self.asr.start() }
        }
    }

    private func submitRequest() {
        let prompt = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        self.inputText = ""
        // Record which saved prompt is in force for the request being sent, so
        // the result can say what produced it.
        self.appliedPromptName = self.settings.isEditPromptOff
            ? nil
            : self.settings.selectedPromptProfile(for: .edit)?.name
        Task {
            await self.service.processRewriteRequest(prompt)
        }
    }

    // MARK: - Model management (pulls from the shared AI Settings pool)

    private func updateAvailableModels() {
        let currentProviderID = self.settings.rewriteModeSelectedProviderID
        let currentModel = self.settings.rewriteModeSelectedModel ?? ""
        if self.isPrivateAIProviderID(currentProviderID) {
            self.settings.rewriteModeSelectedProviderID = ""
            self.settings.rewriteModeSelectedModel = nil
            self.availableModels = []
            return
        }
        guard !currentProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.availableModels = []
            return
        }

        // Pull models from the shared pool configured in AI Settings
        let possibleKeys = self.providerKeys(for: currentProviderID)
        let storedList = possibleKeys.lazy
            .compactMap { SettingsStore.shared.availableModelsByProvider[$0] }
            .first { !$0.isEmpty }

        if let stored = storedList {
            self.availableModels = stored
        } else {
            self.availableModels = ModelRepository.shared.defaultModels(for: currentProviderID)
        }

        // If current model not in list, select first available
        if !self.availableModels.contains(currentModel) {
            self.settings.rewriteModeSelectedModel = self.availableModels.first
        }
    }

    private func providerKeys(for providerID: String) -> [String] {
        ModelRepository.shared.providerKeys(for: providerID)
    }

    private var builtInProvidersList: [(id: String, name: String)] {
        ModelRepository.shared.builtInProvidersList().filter { !self.isPrivateAIProviderID($0.id) }
    }

    private func isPrivateAIProviderID(_ providerID: String) -> Bool {
        PrivateFeatures.privateAIProvider &&
            providerID.trimmingCharacters(in: .whitespacesAndNewlines) == PrivateAIProviderFeature.shared.providerID
    }
}

// MARK: - Prompt row

/// Board § Prompt row · rest / hover / applied. Rows sit directly on the
/// surface with a hairline between them — no card.
private struct RewritePromptRow: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let name: String
    let summary: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 8) {
                    if self.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(self.theme.palette.accent)
                    }

                    Text(self.name)
                        .basicsLabel(15)
                        .foregroundStyle(
                            self.isSelected ? self.theme.palette.accent : self.theme.palette.primaryText
                        )
                        .lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)

                Text(self.summary)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(self.isHovered ? self.theme.palette.sidebarBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(self.theme.palette.cardBorder)
                .frame(height: 1)
        }
        .onHover { self.isHovered = $0 }
        .help(self.summary)
    }
}

// MARK: - Header icon button

/// 32 × 32, card ground, 1px hairline, radius 8 — same square as Command mode's
/// header actions.
private struct RewriteIconButton: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            self.isHovered
                                ? self.theme.palette.sidebarBackground
                                : self.theme.palette.cardBackground
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
    }
}

// MARK: - Key cap

private struct RewriteKeyCap: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        Text(self.text)
            .basicsMono(12, weight: .medium)
            .foregroundStyle(self.theme.palette.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(self.theme.palette.sidebarBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                    )
            )
    }
}
