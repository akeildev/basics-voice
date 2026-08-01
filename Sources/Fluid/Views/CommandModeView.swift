import AppKit
import SwiftUI

/// Board "05 — Command mode" (`U9-0`), plus `4KZ-0` (running + confirm),
/// `619-0` (empty + how-to + not ready) and `7OR-0` (menus, dialogs, message
/// states).
///
/// The page is a three-band layout that never scrolls as a whole: a fixed
/// header + how-to band, a flexible transcript that scrolls on its own, and a
/// footer band that carries the confirm card, the readiness banner and the
/// composer. Nothing here is decorative — every control below reads or writes
/// `CommandModeService`, `SettingsStore` or `ASRService`.
struct CommandModeView: View {
    @ObservedObject var service: CommandModeService
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject var settings = SettingsStore.shared
    @EnvironmentObject var menuBarManager: MenuBarManager
    var onClose: (() -> Void)?

    @State private var inputText: String = ""

    /// Derived from the shared AI Settings model pool, never invented.
    @State private var availableModels: [String] = []

    @State private var showingClearConfirmation = false
    @State private var showHowTo = false
    @State private var isHoveringHowTo = false
    @State private var isShowingRecentChats = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.pageHeader
                .padding(.bottom, 18)

            self.howToSection

            self.conversationBand
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            self.footerBand
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
        .onAppear {
            self.updateAvailableModels()
            // The in-app page owns the conversation while it is visible, so the
            // notch must not mirror it.
            self.service.enableNotchOutput = false
        }
        .onDisappear {
            self.service.enableNotchOutput = true
        }
        .onChange(of: self.asr.finalText) { _, newText in
            if !newText.isEmpty {
                self.inputText = newText
            }
        }
        .onChange(of: self.settings.commandModeSelectedProviderID) { _, _ in
            self.updateAvailableModels()
        }
        .onChange(of: self.settings.commandModeLinkedToGlobal) { _, _ in
            self.updateAvailableModels()
        }
        .onChange(of: self.settings.selectedProviderID) { _, _ in
            self.updateAvailableModels()
        }
        .onChange(of: self.settings.selectedModelByProvider) { _, _ in
            self.updateAvailableModels()
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: self.$showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                self.service.deleteCurrentChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The conversation and everything it ran are removed. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Modes")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.accent)

                HStack(spacing: 10) {
                    Text("Command mode")
                        .basicsLabel(28)
                        .foregroundStyle(self.theme.palette.primaryText)

                    Text("Alpha")
                        .basicsLabel(11)
                        .foregroundStyle(BasicsTokens.Semantic.danger)
                        .padding(.horizontal, 8)
                        .frame(height: 19)
                        .background(
                            Capsule().fill(BasicsTokens.Semantic.danger.opacity(0.12))
                        )
                }

                Text("Say what you want done instead of what you want written. It proposes a shell command and waits for you to confirm.")
                    .basicsProse(15)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.headerActions
                .padding(.top, 22)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            self.confirmBeforeRunningPill

            CommandIconButton(systemImage: "plus", tone: .neutral) {
                self.service.createNewChat()
            }
            .disabled(self.service.isProcessing)
            .help("New chat")

            CommandIconButton(systemImage: "clock.arrow.circlepath", tone: .neutral) {
                self.isShowingRecentChats.toggle()
            }
            .help("Recent chats")
            .popover(isPresented: self.$isShowingRecentChats) {
                self.recentChatsMenu
            }

            CommandIconButton(systemImage: "trash", tone: .muted) {
                self.showingClearConfirmation = true
            }
            .disabled(self.service.isProcessing)
            .help("Delete chat")
        }
        .fixedSize()
    }

    /// Board § Confirm before running · on / off. Off means commands run the
    /// moment the agent proposes them — the confirm card never appears.
    private var confirmBeforeRunningPill: some View {
        let isOn = self.settings.commandModeConfirmBeforeExecute

        return Button {
            self.settings.commandModeConfirmBeforeExecute.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.shield" : "shield")
                    .font(.system(size: 13, weight: .medium))
                Text("Confirm before running")
                    .basicsButtonLabel(13)
            }
            .foregroundStyle(isOn ? self.theme.palette.accent : self.theme.palette.secondaryText)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: 32)
            .background(
                Capsule().fill(
                    isOn
                        ? self.theme.palette.accent.opacity(0.10)
                        : self.theme.palette.sidebarBackground
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Ask for confirmation before running commands")
    }

    // MARK: - Recent chats

    private var recentChatsMenu: some View {
        let recentChats = self.service.getRecentChats()

        return VStack(alignment: .leading, spacing: 0) {
            if recentChats.isEmpty {
                Text("No recent chats")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 34, alignment: .leading)
            } else {
                ForEach(recentChats) { chat in
                    RecentChatRow(
                        title: chat.title,
                        relativeTime: chat.relativeTimeString,
                        isCurrent: chat.id == self.service.currentChatID,
                        isDisabled: self.service.isProcessing
                    ) {
                        if chat.id != self.service.currentChatID {
                            _ = self.service.switchToChat(id: chat.id)
                        }
                        self.isShowingRecentChats = false
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 308)
    }

    // MARK: - How to use

    private var shortcutDisplay: String {
        self.settings.commandModeHotkeyShortcut?.displayString ?? "Not set"
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Getting started")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.secondaryText)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Press")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)

                    CommandKeyCap(text: self.shortcutDisplay)

                    Text("to open Command mode, speak your command, then press again to send.")
                        .basicsProse(14)
                        .lineSpacing(5)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(self.theme.palette.warning)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Caution")
                            .basicsLabel(12)
                            .foregroundStyle(self.theme.palette.primaryText)

                        Text("AI can make mistakes. Avoid dangerous commands like deleting important files. Destructive actions will ask for confirmation.")
                            .basicsProse(13)
                            .lineSpacing(5)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
            .frame(width: 440, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("Examples")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.secondaryText)

                VStack(alignment: .leading, spacing: 5) {
                    self.howToExample("“List files in my Downloads folder”")
                    self.howToExample("“Create a folder called Projects on Desktop”")
                    self.howToExample("“What's my IP address?”")
                    self.howToExample("“Open Safari”")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 24)
        .padding(.trailing, 2)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }

    private func howToExample(_ text: String) -> some View {
        Text(text)
            .basicsProse(14)
            .lineSpacing(5)
            .foregroundStyle(self.theme.palette.primaryText)
    }

    // MARK: - Conversation

    @ViewBuilder
    private var conversationBand: some View {
        if self.service.conversationHistory.isEmpty, !self.service.isProcessing {
            self.emptyState
        } else {
            self.transcript
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.10))
                    .frame(width: 52, height: 52)
                Image(systemName: "terminal")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(self.theme.palette.accent)
            }

            Text("No commands yet")
                .basicsLabel(18)
                .foregroundStyle(self.theme.palette.primaryText)

            Text("Say or type what you want done. Every command is shown to you before it runs.")
                .basicsProse(14)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(self.service.conversationHistory) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if self.service.isProcessing {
                        self.processingIndicator
                            .id("processing")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .padding(.bottom, 4)
            }
            .onChange(of: self.service.conversationHistory.count) { _, _ in
                self.scrollToBottom(proxy)
            }
            .onChange(of: self.service.isProcessing) { _, isProcessing in
                // Scroll when processing starts, not on every streaming update.
                if isProcessing { self.scrollToBottom(proxy) }
            }
            .onChange(of: self.service.currentStep) { _, _ in
                self.scrollToBottom(proxy)
            }
        }
    }

    private var processingIndicator: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(self.theme.palette.accent)

                CommandShimmerText(text: "Thinking")
            }
            .frame(height: 72)

            if self.settings.showThinkingTokens, !self.service.streamingThinkingText.isEmpty {
                ThinkingTranscript(text: self.service.streamingThinkingText, maxHeight: 140)
                    .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Footer band

    private var footerBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pending = service.pendingCommand {
                self.pendingCommandCard(pending)
            }

            if let issue = self.settings.commandModeReadinessIssue {
                self.readinessBanner(issue)
            }

            self.composer
        }
        .padding(.top, 18)
    }

    // MARK: - Confirm execution

    private func pendingCommandCard(_ pending: CommandModeService.PendingCommand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(self.theme.palette.warning)

                Text("Confirm execution")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
            }

            if let purpose = pending.purpose, !purpose.isEmpty {
                Text(purpose)
                    .basicsProse(14)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.theme.palette.warning)
                    Text("Command")
                        .basicsMicroLabel()
                        .foregroundStyle(self.theme.palette.secondaryText)
                }

                Text(pending.command)
                    .basicsMono(12.5)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .fill(self.theme.palette.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                    .stroke(self.theme.palette.warning.opacity(0.5), lineWidth: 1)
                            )
                    )
            }

            HStack(spacing: 10) {
                Button {
                    Task { await self.service.confirmAndExecute() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Run command")
                            .basicsButtonLabel(13)
                        Text("return")
                            .basicsMono(10)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.theme.palette.warning.commandModeDarkened(0.42))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])

                Button {
                    self.service.cancelPendingCommand()
                } label: {
                    HStack(spacing: 8) {
                        Text("Cancel")
                            .basicsButtonLabel(13)
                            .foregroundStyle(self.theme.palette.primaryText)
                        Text("esc")
                            .basicsMono(10)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.theme.palette.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.warning.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                        .stroke(self.theme.palette.warning.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: - Readiness banner

    private func readinessBanner(_ issue: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(self.theme.palette.warning)

            Text(issue)
                .basicsProse(14)
                .lineSpacing(4)
                .lineLimit(2)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("AI settings") {
                AppNavigationRouter.shared.request(.aiEnhancements)
            }
            .buttonStyle(.plain)
            .basicsButtonLabel(13)
            .foregroundStyle(self.theme.palette.primaryText)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                    )
            )
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .stroke(self.theme.palette.warning.opacity(0.40), lineWidth: 1)
                )
        )
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if self.inputText.isEmpty {
                        Text("Type a command or ask a question…")
                            .basicsProse(15)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: self.$inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .basicsProse(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1 ... 4)
                        .onSubmit { self.submitCommand() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: self.toggleRecording) {
                    Image(systemName: self.asr.isRunning ? "stop.fill" : "mic")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            self.asr.isRunning
                                ? Color.white
                                : self.theme.palette.primaryText
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
                .disabled(self.service.isProcessing)
                .help(self.asr.isRunning ? "Stop voice command" : "Start voice command")

                Button(action: self.submitCommand) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                self.canSubmitCommand
                                    ? self.theme.palette.accent
                                    : self.theme.palette.accent.opacity(0.35)
                            )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!self.canSubmitCommand)
                .help("Run command")
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
            Button {
                self.settings.commandModeLinkedToGlobal.toggle()
            } label: {
                HStack(spacing: 9) {
                    CommandCheckbox(isOn: self.settings.commandModeLinkedToGlobal)
                    Text("Sync with AI enhancements")
                        .basicsLabel(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Use the same provider and model selected in AI Enhancement.")

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                SearchableProviderPicker(
                    builtInProviders: self.verifiedBuiltInProvidersList,
                    savedProviders: self.verifiedSavedProviders,
                    selectedProviderID: Binding(
                        get: { self.settings.effectiveCommandModeProviderID },
                        set: { newValue in
                            guard !self.settings.commandModeLinkedToGlobal else { return }
                            guard !self.isPrivateAIProviderID(newValue) else { return }
                            self.settings.commandModeSelectedProviderID = newValue
                            self.updateAvailableModels()
                        }
                    ),
                    controlWidth: 140,
                    controlHeight: 30
                )
                .disabled(self.settings.commandModeLinkedToGlobal)
                .opacity(self.settings.commandModeLinkedToGlobal ? 0.55 : 1)

                SearchableModelPicker(
                    models: self.availableModels,
                    selectedModel: Binding(
                        get: { self.settings.effectiveCommandModeSelectedModel },
                        set: { newValue in
                            guard !self.settings.commandModeLinkedToGlobal else { return }
                            self.settings.commandModeSelectedModel = newValue
                        }
                    ),
                    onRefresh: nil,
                    isRefreshing: false,
                    selectionEnabled: !self.settings.commandModeLinkedToGlobal && !self.availableModels.isEmpty,
                    controlWidth: 180,
                    controlHeight: 30
                )
                .disabled(self.settings.commandModeLinkedToGlobal)
                .opacity(self.settings.commandModeLinkedToGlobal ? 0.55 : 1)
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

    private var canSubmitCommand: Bool {
        !self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.service.isProcessing &&
            self.settings.commandModeReadinessIssue == nil
    }

    private func toggleRecording() {
        if self.asr.isRunning {
            Task {
                let command = await self.asr.stop().trimmingCharacters(in: .whitespacesAndNewlines)
                _ = self.asr.consumeLastCompletedAudioSnapshot()
                guard !command.isEmpty else { return }
                await MainActor.run {
                    self.inputText = command
                }
                guard self.settings.commandModeReadinessIssue == nil else { return }
                await self.service.processUserCommand(command)
                await MainActor.run {
                    self.inputText = ""
                }
            }
        } else {
            Task { await self.asr.start() }
        }
    }

    private func submitCommand() {
        let text = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard self.settings.commandModeReadinessIssue == nil else { return }
        self.inputText = ""
        Task {
            await self.service.processUserCommand(text)
        }
    }

    private func updateAvailableModels() {
        let currentProviderID = self.settings.effectiveCommandModeProviderID
        let currentModel = self.settings.commandModeSelectedModel ?? ""
        guard !currentProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.availableModels = []
            return
        }
        self.availableModels = self.settings.commandModeModels(for: currentProviderID)

        // If current model not in list, select first available
        if !self.settings.commandModeLinkedToGlobal, !self.availableModels.contains(currentModel) {
            self.settings.commandModeSelectedModel = self.availableModels.first
        }
    }

    private var builtInProvidersList: [(id: String, name: String)] {
        ModelRepository.shared.builtInProvidersList().filter { !self.isPrivateAIProviderID($0.id) }
    }

    private var verifiedBuiltInProvidersList: [(id: String, name: String)] {
        self.builtInProvidersList.filter { self.settings.isCommandModeProviderVerified($0.id) }
    }

    private var verifiedSavedProviders: [SettingsStore.SavedProvider] {
        self.settings.savedProviders.filter { self.settings.isCommandModeProviderVerified($0.id) }
    }

    private func isPrivateAIProviderID(_ providerID: String) -> Bool {
        PrivateFeatures.privateAIProvider &&
            providerID.trimmingCharacters(in: .whitespacesAndNewlines) == PrivateAIProviderFeature.shared.providerID
    }
}

// MARK: - Header icon button

/// Board § Header actions. 32 × 32, card ground, 1px hairline, radius 8.
private struct CommandIconButton: View {
    enum Tone {
        case neutral
        case muted
    }

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let systemImage: String
    let tone: Tone
    let action: () -> Void

    private var foreground: Color {
        if !self.isEnabled { return self.theme.palette.tertiaryText }
        return self.tone == .neutral ? self.theme.palette.primaryText : self.theme.palette.secondaryText
    }

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(self.foreground)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            self.isHovered && self.isEnabled
                                ? self.theme.palette.sidebarBackground
                                : self.theme.palette.cardBackground
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                        )
                )
                .opacity(self.isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
    }
}

// MARK: - Recent chat row

private struct RecentChatRow: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let title: String
    let relativeTime: String
    let isCurrent: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var fill: Color {
        if self.isCurrent { return self.theme.palette.accent.opacity(0.10) }
        if self.isHovered, !self.isDisabled { return self.theme.palette.sidebarBackground }
        return .clear
    }

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                Group {
                    if self.isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(self.theme.palette.accent)
                    }
                }
                .frame(width: 14)

                Text(self.title)
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(self.relativeTime)
                    .basicsMono(10)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(self.fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.isDisabled)
        .opacity(self.isDisabled ? 0.4 : 1)
        .onHover { self.isHovered = $0 }
    }
}

// MARK: - Key cap

/// Board § How to use. The hotkey chip: muted well, one-step-stronger outline,
/// JetBrains Mono — a key is a technical value, never a label.
private struct CommandKeyCap: View {
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

// MARK: - Checkbox

private struct CommandCheckbox: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(self.isOn ? self.theme.palette.accent : self.theme.palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        self.isOn ? Color.clear : BasicsBorder.strong(self.theme, self.colorScheme),
                        lineWidth: 1
                    )
            )
            .overlay {
                if self.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 15, height: 15)
    }
}

// MARK: - Thinking transcript

/// Board § Thinking. A 2px brand-soft rail instead of a box — reasoning is an
/// aside, not a card.
struct ThinkingTranscript: View {
    @Environment(\.theme) private var theme
    let text: String
    let maxHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(self.theme.palette.accent.opacity(0.10))
                .frame(width: 2)

            ScrollView(.vertical, showsIndicators: true) {
                Text(self.text)
                    .basicsProse(12)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: self.maxHeight)
    }
}

// MARK: - Shimmer

/// The one animated element on the page. Base is faint ink; a single brand-lit
/// band sweeps it so "working" reads without a spinner.
struct CommandShimmerText: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let duration = 1.15
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            let center = CGFloat(progress)
            let leadingEdge = max(0, center - 0.18)
            let trailingEdge = min(1, center + 0.18)

            Text(self.text)
                .basicsLabel(15)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: BasicsTokens.Ink.faint, location: 0),
                            .init(color: BasicsTokens.Ink.faint, location: leadingEdge),
                            .init(color: self.theme.palette.primaryText, location: center),
                            .init(color: BasicsTokens.Ink.faint, location: trailingEdge),
                            .init(color: BasicsTokens.Ink.faint, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .accessibilityLabel(Text(self.text))
    }
}

// MARK: - Message bubble

/// Board § Transcript. One turn: the user's prompt, the agent's reasoning, the
/// command it called, or the tool output that came back.
struct MessageBubble: View {
    let message: CommandModeService.Message
    @Environment(\.theme) private var theme
    @State private var isThinkingExpanded: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if self.message.role == .user {
                Spacer(minLength: 0)
                self.userMessageView
            } else {
                self.agentMessageView
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - User

    private var userMessageView: some View {
        Text(self.message.content)
            .basicsProse(14)
            .lineSpacing(4)
            .foregroundStyle(self.theme.palette.primaryText)
            .textSelection(.enabled)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(maxWidth: 380, alignment: .leading)
            .background(self.theme.palette.accent.opacity(0.10))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 14,
                        bottomLeading: 14,
                        bottomTrailing: 4,
                        topTrailing: 14
                    ),
                    style: .continuous
                )
            )
    }

    // MARK: - Agent

    private var agentMessageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tc = message.toolCall, let purpose = tc.purpose, !purpose.isEmpty {
                Text(purpose)
                    .basicsProse(12)
                    .lineSpacing(3)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            if let thinking = message.thinking, !thinking.isEmpty, SettingsStore.shared.showThinkingTokens {
                self.thinkingSection(thinking)
            }

            if self.message.role == .tool {
                self.toolOutputView
            } else if let tc = message.toolCall {
                self.commandCallView(tc)
            } else if !self.message.content.isEmpty {
                self.textContentView
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: - Thinking

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.isThinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Thinking")
                        .basicsMicroLabel()
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    Image(systemName: self.isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    if self.isThinkingExpanded {
                        Text("\(thinking.count) chars")
                            .basicsMono(10)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.isThinkingExpanded {
                ThinkingTranscript(text: thinking, maxHeight: 150)
            }
        }
    }

    // MARK: - Command call

    private func commandCallView(_ tc: CommandModeService.Message.ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The agent's own narration, unless it is just restating the call.
            if !self.message.content.isEmpty,
               !self.message.content.lowercased().starts(with: "checking"),
               !self.message.content.lowercased().starts(with: "executing"),
               !self.message.content.lowercased().starts(with: "i'll")
            {
                Text(self.message.content)
                    .basicsProse(12)
                    .lineSpacing(3)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            HStack(alignment: .top, spacing: 10) {
                Text("$")
                    .basicsMono(12, weight: .medium)
                    .foregroundStyle(self.theme.palette.tertiaryText)

                Text(tc.command)
                    .basicsMono(12)
                    .lineSpacing(5)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(self.theme.palette.sidebarBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Tool output

    private var toolOutputView: some View {
        let parsed = self.parseToolOutput(self.message.content)
        let tone = parsed.success ? self.theme.palette.accent : BasicsTokens.Semantic.danger

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: parsed.success ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone)

                Text(parsed.success ? "Success" : "Error")
                    .basicsLabel(12)
                    .foregroundStyle(tone)

                if parsed.executionTime > 0 {
                    Text("\(parsed.executionTime)ms")
                        .basicsMono(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }

            if !parsed.output.isEmpty || (parsed.error?.isEmpty == false) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !parsed.output.isEmpty {
                            Text(self.markdownAttributedString(from: parsed.output))
                                .basicsMono(11)
                                .lineSpacing(5)
                                .foregroundStyle(
                                    parsed.success
                                        ? self.theme.palette.secondaryText
                                        : self.theme.palette.primaryText
                                )
                                .textSelection(.enabled)
                        }

                        if let error = parsed.error, !error.isEmpty {
                            Text(error)
                                .basicsMono(11)
                                .lineSpacing(5)
                                .foregroundStyle(self.theme.palette.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(
                            parsed.success
                                ? self.theme.palette.sidebarBackground
                                : BasicsTokens.Semantic.danger.opacity(0.07)
                        )
                )
            }
        }
    }

    private var textContentView: some View {
        Text(self.markdownAttributedString(from: self.message.content))
            .basicsProse(14)
            .lineSpacing(5)
            .foregroundStyle(self.theme.palette.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Markdown

    private func markdownAttributedString(from text: String) -> AttributedString {
        do {
            let attributed = try AttributedString(
                markdown: text,
                options: AttributedString
                    .MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            return attributed
        } catch {
            return AttributedString(text)
        }
    }

    // MARK: - Helpers

    private struct ParsedOutput {
        let success: Bool
        let output: String
        let error: String?
        let exitCode: Int
        let executionTime: Int
    }

    private func parseToolOutput(_ json: String) -> ParsedOutput {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ParsedOutput(success: false, output: json, error: nil, exitCode: -1, executionTime: 0)
        }

        return ParsedOutput(
            success: parsed["success"] as? Bool ?? false,
            output: parsed["output"] as? String ?? "",
            error: parsed["error"] as? String,
            exitCode: parsed["exitCode"] as? Int ?? 0,
            executionTime: parsed["executionTimeMs"] as? Int ?? 0
        )
    }
}

// MARK: - Colour helper

private extension Color {
    /// The confirm card's Run button is a deliberately darkened warning so white
    /// text clears contrast on it. Derived from the token, never a second hex.
    func commandModeDarkened(_ amount: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return Color(
            red: Double(base.redComponent) * (1 - amount),
            green: Double(base.greenComponent) * (1 - amount),
            blue: Double(base.blueComponent) * (1 - amount),
            opacity: Double(base.alphaComponent)
        )
    }
}
