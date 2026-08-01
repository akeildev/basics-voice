//
//  AISettingsView+SpeechRecognition.swift
//  fluid
//
//  The Voice engine screen. Rebuilt against Basics boards 02b (model states) and
//  02c (no active model + language popover): one card holding hairline-separated
//  model rows in fixed lanes (indicator · content · size · action · delete), a
//  stats panel with thin brand meters, and the custom-vocabulary strip.
//
//  Every value on screen comes from `SettingsStore.SpeechModel` or `ASRService`.
//

import SwiftUI

extension VoiceEngineSettingsView {
    // MARK: - Screen

    var speechRecognitionCard: some View {
        let activeModel = self.settings.selectedSpeechModel.isInstalled ? self.settings.selectedSpeechModel : nil
        let listedModels = self.viewModel.filteredSpeechModels
        let otherModels = listedModels.filter { $0 != activeModel }

        return VStack(alignment: .leading, spacing: 28) {
            if let activeModel {
                VStack(alignment: .leading, spacing: 14) {
                    self.modelSectionHeader(title: "Speech model")
                    self.modelListCard(models: [activeModel] + otherModels)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active model")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                    self.noActiveModelCard
                }

                VStack(alignment: .leading, spacing: 14) {
                    self.modelSectionHeader(title: "Available models")
                    self.modelListCard(models: otherModels)
                }
            }

            self.modelStatsPanel

            self.fillerWordsSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: self.viewModel.asr.showError) { _, isShowing in
            guard isShowing else { return }
            VoiceEngineActionLog.shared.noteErrorRaised(
                title: self.viewModel.asr.errorTitle,
                message: self.viewModel.asr.errorMessage
            )
        }
        .onChange(of: self.viewModel.asr.isAsrReady) { _, isReady in
            if isReady { VoiceEngineActionLog.shared.noteSettled() }
        }
        .onChange(of: self.viewModel.asr.downloadingModelId) { _, downloadingID in
            // Download finished (or was cancelled) without raising — stop
            // attributing any later error to it.
            if downloadingID == nil, self.viewModel.asr.showError == false {
                VoiceEngineActionLog.shared.noteSettled()
            }
        }
    }

    // MARK: - Section header (label · busy note · filter · sort)

    private func modelSectionHeader(title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if self.viewModel.areSpeechModelActionsBlocked {
                Text("Actions pause while a transcription is running")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            Menu {
                Picker("Provider", selection: self.$viewModel.providerFilter) {
                    ForEach(SpeechProviderFilter.allCases) { option in
                        Text(option == .all ? "All providers" : option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)

                Divider().hidden()

                Toggle("English only", isOn: self.$viewModel.englishOnlyFilter)
                Toggle("Downloaded only", isOn: self.$viewModel.installedOnlyFilter)
            } label: {
                VoiceEngineMenuTriggerLabel(title: self.providerFilterTitle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Picker("Sort by", selection: self.$viewModel.modelSortOption) {
                    ForEach(ModelSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                VoiceEngineMenuTriggerLabel(
                    title: "Sort by \(self.viewModel.modelSortOption.rawValue.lowercased())"
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var providerFilterTitle: String {
        var title = self.viewModel.providerFilter == .all
            ? "All providers"
            : self.viewModel.providerFilter.rawValue
        var extras: [String] = []
        if self.viewModel.englishOnlyFilter { extras.append("English") }
        if self.viewModel.installedOnlyFilter { extras.append("downloaded") }
        if extras.isEmpty == false {
            title += " · \(extras.joined(separator: " + "))"
        }
        return title
    }

    // MARK: - Model list

    private func modelListCard(models: [SettingsStore.SpeechModel]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Rectangle()
                        .fill(self.theme.palette.separator)
                        .frame(height: 1)
                }
                self.speechModelCard(for: model)
            }
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
    }

    private var noActiveModelCard: some View {
        HStack(spacing: 14) {
            VoiceEngineRadio(isDashed: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("No active model yet")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("Download one below and press Activate. Dictation stays off until then.")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    BasicsTokens.Surface.borderStrong,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }

    func speechModelCard(for model: SettingsStore.SpeechModel) -> some View {
        VoiceEngineModelRow(
            viewModel: self.viewModel,
            settings: self.settings,
            actionLog: VoiceEngineActionLog.shared,
            model: model
        )
    }

    // MARK: - Stats panel

    /// Describes whichever model the list is previewing, with the Speed/Accuracy
    /// meters and the custom-vocabulary strip.
    var modelStatsPanel: some View {
        let model = self.viewModel.previewSpeechModel

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        Text(model.humanReadableName)
                            .basicsLabel(16)
                            .foregroundStyle(self.theme.palette.primaryText)

                        if let badge = VoiceEngineModelCopy.badgeLabel(for: model) {
                            VoiceEngineStatusChip(
                                text: badge,
                                style: VoiceEngineModelCopy.badgeIsBrand(badge) ? .brandSoft : .muted
                            )
                        }

                        Spacer(minLength: 0)
                    }

                    Text(model.cardDescription)
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if let size = VoiceEngineModelCopy.sizeChipText(for: model) {
                            VoiceEngineValueChip(text: size, style: .muted, mono: true, systemImage: "internaldrive")
                        }

                        if model.requiresAppleSilicon {
                            VoiceEngineValueChip(text: "Apple Silicon", style: .brandSoft)
                        }

                        VoiceEngineValueChip(text: model.languageSupport, style: .muted)

                        Spacer(minLength: 0)
                    }

                    if let codes = model.supportedLanguageCodes {
                        Text(codes)
                            .basicsMono(11)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let warning = VoiceEngineModelCopy.memoryWarning(for: model) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(BasicsTokens.display(13, .medium))
                                .foregroundStyle(self.theme.palette.warning)
                            Text(warning)
                                .basicsProse(13)
                                .foregroundStyle(self.theme.palette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .fill(self.theme.palette.warning.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                        .stroke(self.theme.palette.warning.opacity(0.32), lineWidth: 1)
                                )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 14) {
                    VoiceEngineMeter(label: "Speed", value: model.speedPercent, animationKey: model.id)
                    VoiceEngineMeter(label: "Accuracy", value: model.accuracyPercent, animationKey: model.id)
                }
                .frame(width: 236)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            if model.supportsCustomVocabulary {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(BasicsTokens.display(15, .medium))
                        .foregroundStyle(self.theme.palette.accent)

                    Text("Custom words work on this model. Teach it names, product terms and the words it keeps getting wrong.")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    VoiceEnginePillButton(title: "Open dictionary", role: .primary) {
                        NotificationCenter.default.post(name: .openCustomDictionaryFromVoiceEngine, object: nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.theme.palette.accent.opacity(0.10))
            }
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
    }

    // MARK: - Filler words

    var fillerWordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove filler words")
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("Strips the ums, uhs and ers out of a transcript before it lands.")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: self.$viewModel.removeFillerWordsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(self.theme.palette.accent)
                    .onChange(of: self.viewModel.removeFillerWordsEnabled) { _, newValue in
                        self.settings.removeFillerWordsEnabled = newValue
                    }
            }
            .padding(.vertical, 18)

            if self.viewModel.removeFillerWordsEnabled {
                FillerWordsEditor()
                    .padding(.bottom, 18)
            }
        }
    }
}

// MARK: - One model row

/// A single speech model in the list. Lanes are fixed so the column of sizes,
/// actions and delete buttons lines up across every row regardless of state.
struct VoiceEngineModelRow: View {
    @Environment(\.theme) private var theme

    @ObservedObject var viewModel: VoiceEngineSettingsViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var actionLog: VoiceEngineActionLog

    let model: SettingsStore.SpeechModel

    private var isConfiguredActive: Bool { self.viewModel.isActiveSpeechModel(self.model) }

    private var isActive: Bool {
        self.isConfiguredActive && self.model.isInstalled && self.viewModel.asr.isAsrReady
    }

    private var isPreviewing: Bool {
        self.viewModel.previewSpeechModel == self.model && !self.isActive
    }

    private var isDownloadingThis: Bool { self.viewModel.downloadingModel == self.model }

    private var isPreparingActive: Bool {
        (self.viewModel.asr.isDownloadingModel
            || self.viewModel.asr.isLoadingModel
            || self.viewModel.asr.isCancellingModelPreparation)
            && self.isConfiguredActive
            && !self.viewModel.asr.isAsrReady
    }

    private var failure: VoiceEngineActionLog.Failure? { self.actionLog.failure(for: self.model.id) }

    private var rowBackground: Color {
        if self.isActive { return self.theme.palette.accent.opacity(0.10) }
        if self.isPreviewing { return self.theme.palette.sidebarBackground }
        return .clear
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VoiceEngineRadio(isFilled: self.isActive)

            VStack(alignment: .leading, spacing: 5) {
                self.titleLine
                self.detailLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(VoiceEngineModelCopy.rowSizeText(for: self.model))
                .basicsMono(12)
                .monospacedDigit()
                .foregroundStyle(
                    self.model.isInstalled ? self.theme.palette.secondaryText : self.theme.palette.tertiaryText
                )
                .frame(width: 84, alignment: .trailing)

            self.actionSlot
                .frame(width: 104, alignment: .trailing)

            self.deleteSlot
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { self.viewModel.previewSpeechModel = self.model }
        .animation(.easeInOut(duration: 0.18), value: self.isPreviewing)
        .opacity(self.viewModel.asr.isRunning ? 0.45 : 1)
        .allowsHitTesting(!self.viewModel.asr.isRunning)
    }

    // MARK: Title line

    private var titleLine: some View {
        HStack(spacing: 9) {
            Text(self.model.humanReadableName)
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)
                .lineLimit(1)

            if self.isActive {
                VoiceEngineStatusChip(text: "Active", style: .brandFilled)
            }

            VoiceEngineStatusChip(
                text: VoiceEngineModelCopy.runsWhereLabel(for: self.model),
                style: self.isActive ? .card : .muted
            )

            if !self.isActive, let badge = VoiceEngineModelCopy.badgeLabel(for: self.model) {
                VoiceEngineStatusChip(
                    text: badge,
                    style: VoiceEngineModelCopy.badgeIsBrand(badge) ? .brandSoft : .muted
                )
            }

            if VoiceEngineModelCopy.isStreamingModel(self.model) {
                VoiceEngineStatusChip(text: "Streaming", style: .muted)
            }

            if self.isPreviewing {
                VoiceEngineStatusChip(text: "Previewing", style: .outlined)
            }

            if self.model == .cohereTranscribeSixBit {
                VoiceEngineCohereLanguageChip(
                    settings: self.settings,
                    isEnabled: !self.viewModel.areSpeechModelActionsBlocked
                )
            } else if VoiceEngineModelCopy.usesNemotronLanguage(self.model) {
                VoiceEngineNemotronLanguageChip(
                    settings: self.settings,
                    isEnabled: !self.viewModel.areSpeechModelActionsBlocked
                )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Detail line

    @ViewBuilder
    private var detailLine: some View {
        if let failure = self.failure {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(BasicsTokens.display(13, .medium))
                    .foregroundStyle(BasicsTokens.Semantic.danger)
                Text(failure.message)
                    .basicsProse(13)
                    .foregroundStyle(BasicsTokens.Semantic.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(BasicsTokens.Semantic.danger.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .stroke(BasicsTokens.Semantic.danger.opacity(0.28), lineWidth: 1)
                    )
            )
        } else if self.isDownloadingThis || self.isPreparingActive {
            VStack(alignment: .leading, spacing: 7) {
                VoiceEngineProgressTrack(
                    progress: self.viewModel.asr.downloadProgress,
                    isDimmed: self.isCancelling
                )
                Text(self.progressStatusText)
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.model.cardDescription)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(2)

                if self.model.externalCoreMLSpec?.sourceURL != nil {
                    Button {
                        self.viewModel.openExternalModelSource(for: self.model)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open model source").basicsLabel(13)
                            Image(systemName: "arrow.up.right.square")
                                .font(BasicsTokens.display(11, .medium))
                        }
                        .foregroundStyle(self.theme.palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.viewModel.areSpeechModelActionsBlocked)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var isCancelling: Bool {
        (self.isDownloadingThis && self.viewModel.isCancellingModelDownload)
            || (self.isPreparingActive && self.viewModel.asr.isCancellingModelPreparation)
    }

    private var progressStatusText: String {
        if self.isCancelling {
            if let progress = self.viewModel.asr.downloadProgress {
                return "Cancelling… · stopping at \(Int((progress * 100).rounded()))%"
            }
            return "Cancelling…"
        }

        let status = self.viewModel.asr.modelPreparationStatusText
        let size = VoiceEngineModelCopy.rowSizeText(for: self.model)
        guard self.viewModel.asr.modelPreparationPhase == .downloading, size != "—" else { return status }
        return "\(status) · \(size)"
    }

    // MARK: Action + delete lanes

    @ViewBuilder
    private var actionSlot: some View {
        if let failure = self.failure {
            VoiceEnginePillButton(title: "Retry", isEnabled: !self.viewModel.areSpeechModelActionsBlocked) {
                self.actionLog.clearFailure(for: self.model.id)
                switch failure.action {
                case .download:
                    self.startDownload()
                case .activate:
                    self.startActivate()
                }
            }
        } else if self.isDownloadingThis {
            VoiceEnginePillButton(
                title: self.viewModel.isCancellingModelDownload ? "Cancelling…" : "Cancel",
                isEnabled: !self.viewModel.isCancellingModelDownload
            ) {
                self.viewModel.cancelSpeechModelDownload()
            }
        } else if self.isPreparingActive {
            VoiceEnginePillButton(
                title: self.viewModel.asr.isCancellingModelPreparation ? "Cancelling…" : "Cancel",
                isEnabled: !self.viewModel.asr.isCancellingModelPreparation
            ) {
                self.viewModel.cancelActiveModelPreparation()
            }
        } else if self.model.isInstalled {
            if !self.isActive {
                VoiceEnginePillButton(
                    title: "Activate",
                    isEnabled: !self.viewModel.areSpeechModelActionsBlocked
                ) {
                    self.startActivate()
                }
            }
        } else {
            VoiceEnginePillButton(
                title: "Download",
                isEnabled: !self.viewModel.areSpeechModelActionsBlocked
            ) {
                self.startDownload()
            }
        }
    }

    @ViewBuilder
    private var deleteSlot: some View {
        if self.model.isInstalled, !self.model.usesAppleLogo {
            VoiceEngineIconButton(
                systemImage: "trash",
                isEnabled: !self.viewModel.areSpeechModelActionsBlocked,
                help: "Delete \(self.model.humanReadableName) from this Mac"
            ) {
                self.actionLog.clearFailure(for: self.model.id)
                self.viewModel.deleteSpeechModel(self.model)
            }
        } else {
            Color.clear
        }
    }

    private func startDownload() {
        self.viewModel.previewSpeechModel = self.model
        self.actionLog.begin(.download, for: self.model.id)
        self.viewModel.downloadSpeechModel(self.model)
    }

    private func startActivate() {
        self.actionLog.begin(.activate, for: self.model.id)
        self.viewModel.activateSpeechModel(self.model)
    }
}

// MARK: - Language chips

/// Globe chip on the Cohere row. Cohere has no auto-detect, so it always reads
/// as the neutral variant.
struct VoiceEngineCohereLanguageChip: View {
    @ObservedObject var settings: SettingsStore
    let isEnabled: Bool

    var body: some View {
        Menu {
            Picker("Transcription language", selection: self.$settings.selectedCohereLanguage) {
                ForEach(SettingsStore.CohereLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.inline)
        } label: {
            VoiceEngineLanguageChipLabel(
                title: self.settings.selectedCohereLanguage.displayName,
                isBrand: false
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.45)
    }
}

/// Globe chip on the Nemotron rows, opening the 260pt language popover. Reads as
/// the brand variant while the language is being auto-detected.
struct VoiceEngineNemotronLanguageChip: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore
    let isEnabled: Bool

    @State private var isOpen = false

    private var isAuto: Bool { self.settings.selectedNemotronLanguage == .auto }

    var body: some View {
        Button {
            self.isOpen.toggle()
        } label: {
            VoiceEngineLanguageChipLabel(
                title: self.settings.selectedNemotronLanguage.compactDisplayName,
                isBrand: self.isAuto
            )
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.45)
        .popover(isPresented: self.$isOpen, arrowEdge: .bottom) {
            self.popoverBody
        }
    }

    private var popoverBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcription language")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(SettingsStore.NemotronLanguage.allCases) { language in
                        self.languageRow(language)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 260, height: 420)
        .background(self.theme.palette.cardBackground)
    }

    private func languageRow(_ language: SettingsStore.NemotronLanguage) -> some View {
        let isSelected = language == self.settings.selectedNemotronLanguage
        let parts = VoiceEngineModelCopy.languageNameAndTier(language.displayName)

        return Button {
            self.settings.selectedNemotronLanguage = language
            self.isOpen = false
        } label: {
            HStack(spacing: 8) {
                Text(parts.name)
                    .basicsLabel(13)
                    .foregroundStyle(isSelected ? self.theme.palette.accent : self.theme.palette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let tier = parts.tier {
                    VoiceEngineStatusChip(text: tier, style: .muted)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(BasicsTokens.display(12, .medium))
                        .foregroundStyle(self.theme.palette.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(isSelected ? self.theme.palette.accent.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VoiceEngineLanguageChipLabel: View {
    @Environment(\.theme) private var theme

    let title: String
    let isBrand: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(BasicsTokens.display(11, .medium))
                .foregroundStyle(self.isBrand ? self.theme.palette.accent : self.theme.palette.tertiaryText)
            Text(self.title)
                .basicsLabel(11)
                .lineLimit(1)
                .foregroundStyle(self.isBrand ? self.theme.palette.accent : self.theme.palette.primaryText)
            Image(systemName: "chevron.down")
                .font(BasicsTokens.display(9, .medium))
                .foregroundStyle(self.isBrand ? self.theme.palette.accent : self.theme.palette.tertiaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            Capsule()
                .fill(self.isBrand ? self.theme.palette.accent.opacity(0.10) : self.theme.palette.cardBackground)
                .overlay(
                    Capsule().stroke(
                        self.isBrand ? self.theme.palette.accent : self.theme.palette.cardBorder,
                        lineWidth: 1
                    )
                )
        )
    }
}

// MARK: - Copy derived from the real model catalogue

/// Pure presentation helpers over `SettingsStore.SpeechModel`. Nothing here
/// invents a value — each function reformats a stored one for the board.
enum VoiceEngineModelCopy {
    /// `downloadSize` ships as "~460.9 MiB" / "Built-in"; rows want a bare figure
    /// and an em dash for the models that ship with macOS.
    static func rowSizeText(for model: SettingsStore.SpeechModel) -> String {
        let raw = model.downloadSize
        if raw.caseInsensitiveCompare("Built-in") == .orderedSame { return "—" }
        return raw.hasPrefix("~") ? String(raw.dropFirst()) : raw
    }

    /// Stats-panel size chip: nil for built-in models, which occupy no disk of
    /// their own.
    static func sizeChipText(for model: SettingsStore.SpeechModel) -> String? {
        let size = self.rowSizeText(for: model)
        guard size != "—" else { return nil }
        return model.isInstalled ? "\(size) on disk" : "\(size) download"
    }

    /// Where the model runs. Every model in the catalogue transcribes locally;
    /// the Apple engines are part of macOS rather than a download.
    static func runsWhereLabel(for model: SettingsStore.SpeechModel) -> String {
        model.usesAppleLogo ? "Built in" : "On device"
    }

    /// `badgeText` is a frozen store string; "FluidVoice Pick" is shown under the
    /// app's redesigned name.
    static func badgeLabel(for model: SettingsStore.SpeechModel) -> String? {
        guard let badge = model.badgeText else { return nil }
        return badge == "FluidVoice Pick" ? "Basics pick" : badge
    }

    static func badgeIsBrand(_ badge: String) -> Bool {
        badge == "Basics pick" || badge == "New"
    }

    /// `memoryWarning` carries its own ⚠️ in some cases; the row draws the icon.
    static func memoryWarning(for model: SettingsStore.SpeechModel) -> String? {
        guard let warning = model.memoryWarning else { return nil }
        return warning
            .replacingOccurrences(of: "⚠️", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func isStreamingModel(_ model: SettingsStore.SpeechModel) -> Bool {
        model == .nemotronStreaming || model == .nemotronStreaming320
    }

    static func usesNemotronLanguage(_ model: SettingsStore.SpeechModel) -> Bool {
        model == .nemotronOffline || model == .nemotronStreaming || model == .nemotronStreaming320
    }

    /// Nemotron display names encode a maturity tier as a " - Alpha" /
    /// " - Experimental" suffix; the popover shows it as a trailing chip.
    static func languageNameAndTier(_ displayName: String) -> (name: String, tier: String?) {
        let parts = displayName.components(separatedBy: " - ")
        guard parts.count > 1, let tier = parts.last else { return (displayName, nil) }
        return (parts.dropLast().joined(separator: " - "), tier)
    }
}

extension Notification.Name {
    static let openCustomDictionaryFromVoiceEngine = Notification.Name("OpenCustomDictionaryFromVoiceEngine")
}
