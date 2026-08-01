//
//  CustomDictionaryView.swift
//  fluid
//
//  Dictionary — replacements, boost terms and punctuation rules.
//  Created: 2025-12-21
//  Restyled to the Basics boards 07 (page), 07b (popovers), 07c (sheets &
//  flows) and 07d (teach words).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CustomDictionaryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appServices: AppServices

    @State private var entries: [SettingsStore.CustomDictionaryEntry] = SettingsStore.shared.customDictionaryEntries
    @State private var boostTerms: [ParakeetVocabularyStore.VocabularyConfig.Term] = []
    @State private var editingEntry: SettingsStore.CustomDictionaryEntry?

    @State private var boostStatusMessage = "Add custom words for better Parakeet recognition."
    @State private var boostHasError = false
    @State private var automaticDictionaryLearningEnabled = SettingsStore.shared.automaticDictionaryLearningEnabled
    @State private var vocabBoostingEnabled: Bool = SettingsStore.shared.vocabularyBoostingEnabled
    @State private var isCustomWordsPresented = false
    @State private var isBoostWordEditorPresented = false
    @State private var editingBoostTermIndex: Int?
    @State private var boostTermText = ""
    @State private var boostTermStrength: BoostStrengthPreset = .balanced

    @State private var trainingReplacement = ""
    @State private var trainingVariants: [String] = []
    @State private var pronunciationMatchingEnabled = SettingsStore.shared.pronunciationMatchingEnabled
    @State private var trainingPronunciationEnrollments: [PronunciationEnrollmentCapture] = []
    @State private var trainingSampleCount = 0
    @State private var lastTrainingOutput = ""
    @State private var lastTrainingOutputIsCovered = false
    @State private var consecutiveCoveredCaptures = 0
    @State private var trainingStatusMessage = "Type the correct text."
    @State private var trainingHasError = false
    /// Set alongside every `trainingStatusMessage` that carries `trainingHasError`,
    /// so the readiness strip can name the failure ("Microphone blocked") instead
    /// of the UI guessing it back out of the sentence.
    @State private var trainingErrorTitle = ""
    @State private var isTrainingStarting = false
    @State private var isTrainingRecording = false
    @State private var trainingStopRequestedDuringStart = false
    @State private var isTrainingProcessing = false
    @State private var isAutomaticTrainingEnabled = false
    @State private var replacementConfirmation: ReplacementConfirmation?
    @State private var composerMode: DictionaryComposerMode = .train
    @State private var manualTriggerDraft = ""
    @State private var manualReplacement = ""
    @State private var isYourDictionaryPresented = false
    @State private var isPunctuationDictionaryPresented = false
    @State private var punctuationAutoConvertEnabled = SettingsStore.shared.autoConvertPunctuationEnabled
    @State private var punctuationPrefix = SettingsStore.shared.punctuationDictionaryPrefix
    @State private var punctuationRules = SettingsStore.shared.punctuationDictionaryRules
    @State private var isPunctuationInfoExpanded = false
    @State private var isPunctuationRuleEditorPresented = false
    @State private var editingPunctuationRuleID: UUID?
    @State private var punctuationAliasesText = ""
    @State private var punctuationSymbolText = ""

    @State private var selectedTab: DictionaryTab = .replacements
    @State private var isTeachWordsPresented = false

    private var normalizedTrainingReplacement: String {
        self.trainingReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activePronunciationMatching: Bool {
        self.pronunciationMatchingEnabled && SettingsStore.shared.selectedSpeechModel.supportsPronunciationMatching
    }

    private var trainingTargetReference: String {
        DictionaryTrainingCopy.target(for: self.normalizedTrainingReplacement)
    }

    private var composerModeDetail: String {
        DictionaryTrainingCopy.composerDetail(mode: self.composerMode, target: self.trainingTargetReference)
    }

    private var canUseTrainingRecorderButton: Bool {
        if self.isAutomaticTrainingEnabled {
            return true
        }
        guard !self.trainingStopRequestedDuringStart, !self.isTrainingProcessing else { return false }
        return self.isTrainingRecording || self.canRecordTrainingSample || self.canRetryTrainingAfterMaximum
    }

    private var trainingRecorderIsStop: Bool {
        self.isAutomaticTrainingEnabled || self.isTrainingRecording || self.isTrainingStarting
    }

    private var trainingRecorderButtonTitle: String {
        if self.trainingRecorderIsStop {
            return "Stop"
        }
        return self.canRetryTrainingAfterMaximum ? "Try again" : "Start"
    }

    private var trainingFinalOutputIsReady: Bool {
        if self.activePronunciationMatching {
            return !self.trainingAlreadyCorrectWithoutReplacement &&
                self.trainingPronunciationEnrollments.count >= CustomDictionaryTrainingMerge.readyCoveredCount
        }
        return !self.trainingAlreadyCorrectWithoutReplacement &&
            self.trainingOutputIsCovered &&
            self.consecutiveCoveredCaptures >= CustomDictionaryTrainingMerge.readyCoveredCount
    }

    private var trainingAlreadyCorrectWithoutReplacement: Bool {
        if self.activePronunciationMatching {
            return self.trainingVariants.isEmpty &&
                !self.lastTrainingOutput.isEmpty &&
                self.lastTrainingOutput.caseInsensitiveCompare(self.normalizedTrainingReplacement) == .orderedSame &&
                self.trainingPronunciationEnrollments.count >= CustomDictionaryTrainingMerge.readyCoveredCount
        }
        return self.trainingVariants.isEmpty &&
            self.trainingOutputIsCovered &&
            !self.lastTrainingOutput.isEmpty &&
            self.lastTrainingOutput.caseInsensitiveCompare(self.normalizedTrainingReplacement) == .orderedSame &&
            self.consecutiveCoveredCaptures >= CustomDictionaryTrainingMerge.readyCoveredCount
    }

    private var trainingReadinessProgress: Int {
        if self.activePronunciationMatching {
            return min(self.trainingPronunciationEnrollments.count, CustomDictionaryTrainingMerge.readyCoveredCount)
        }
        guard !self.trainingAlreadyCorrectWithoutReplacement else {
            return CustomDictionaryTrainingMerge.readyCoveredCount
        }
        guard self.trainingOutputIsCovered else { return 0 }
        return min(self.consecutiveCoveredCaptures, CustomDictionaryTrainingMerge.readyCoveredCount)
    }

    private var trainingOutputIsCovered: Bool {
        if self.activePronunciationMatching {
            return !self.trainingPronunciationEnrollments.isEmpty
        }
        return self.lastTrainingOutputIsCovered
    }

    private var trainingFinalOutputText: String {
        guard !self.lastTrainingOutput.isEmpty else { return "Record to check" }
        return self.trainingOutputIsCovered ? self.normalizedTrainingReplacement : self.lastTrainingOutput
    }

    private var canRecordTrainingSample: Bool {
        !self.normalizedTrainingReplacement.isEmpty &&
            !self.isTrainingProcessing &&
            !self.asr.isRunning &&
            self.trainingSampleCount < CustomDictionaryTrainingMerge.maxSamples
    }

    private var canRetryTrainingAfterMaximum: Bool {
        !self.normalizedTrainingReplacement.isEmpty &&
            !self.trainingFinalOutputIsReady &&
            !self.trainingAlreadyCorrectWithoutReplacement &&
            !self.isTrainingRecording &&
            !self.isTrainingProcessing &&
            !self.asr.isRunning &&
            self.trainingSampleCount >= CustomDictionaryTrainingMerge.maxSamples
    }

    private var canAddTrainedReplacement: Bool {
        !self.normalizedTrainingReplacement.isEmpty &&
            (!self.trainingVariants.isEmpty || !self.trainingPronunciationEnrollments.isEmpty) &&
            !self.isTrainingRecording &&
            !self.isTrainingProcessing &&
            self.trainingFinalOutputIsReady
    }

    private var manualTriggers: [String] {
        CustomDictionaryManualEntry.normalizedDraftTriggers(self.manualTriggerDraft)
    }

    private var manualDuplicateTriggers: [String] {
        self.manualTriggers.filter { self.allExistingTriggers().contains($0) }
    }

    private var canAddManualReplacement: Bool {
        !self.manualTriggers.isEmpty &&
            !self.manualReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            self.manualDuplicateTriggers.isEmpty
    }

    private var punctuationEditorTitle: String {
        self.editingPunctuationRuleID == nil ? "Add rule" : "Edit rule"
    }

    private var normalizedPunctuationAliases: [String] {
        SettingsStore.PunctuationDictionaryRule.normalizedAliases(
            self.punctuationAliasesText.components(separatedBy: .newlines)
        )
    }

    private var normalizedPunctuationSymbol: String? {
        SettingsStore.PunctuationDictionaryRule.normalizedSymbol(self.punctuationSymbolText)
    }

    private var canSavePunctuationRule: Bool {
        !self.normalizedPunctuationAliases.isEmpty && self.normalizedPunctuationSymbol != nil
    }

    private var punctuationPreviewPrefix: String {
        SettingsStore.normalizedPunctuationDictionaryPrefix(self.punctuationPrefix) ?? SettingsStore.defaultPunctuationDictionaryPrefix
    }

    private var boostEditorTitle: String {
        self.editingBoostTermIndex == nil ? "Add word" : "Edit word"
    }

    private var normalizedBoostTermText: String {
        self.boostTermText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBoostTermDuplicate: Bool {
        self.existingBoostTerms(excludingIndex: self.editingBoostTermIndex)
            .contains(self.normalizedBoostTermText.lowercased())
    }

    private var canSaveBoostTerm: Bool {
        !self.normalizedBoostTermText.isEmpty && !self.isBoostTermDuplicate
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                self.pageHeader
                self.tabBar
                self.tabContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 40)
        }
        .background(self.theme.palette.contentBackground)
        .dismissTextFocusOnBackgroundTap()
        .sheet(isPresented: self.$isTeachWordsPresented) {
            self.teachWordsComposer
        }
        .overlay(alignment: .bottom) {
            if let confirmation = self.replacementConfirmation {
                ReplacementConfirmationToast(confirmation: confirmation)
                    .padding(.bottom, 28)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: self.$editingEntry) { entry in
            EditDictionaryEntrySheet(
                entry: entry,
                existingTriggers: self.allExistingTriggers(excluding: entry.id)
            ) { updatedEntry in
                if let index = self.entries.firstIndex(where: { $0.id == updatedEntry.id }) {
                    self.entries[index] = updatedEntry
                    self.saveEntries()
                    Task {
                        if PronunciationProfileEditPolicy.shouldDiscardProfile(
                            previousReplacement: entry.replacement,
                            updatedReplacement: updatedEntry.replacement
                        ) {
                            try? await PronunciationDictionaryStore.shared.delete(dictionaryEntryID: updatedEntry.id)
                        } else {
                            try? await PronunciationDictionaryStore.shared.updateLabel(
                                dictionaryEntryID: updatedEntry.id,
                                label: updatedEntry.replacement
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            self.entries = SettingsStore.shared.customDictionaryEntries
            self.loadBoostTerms()
            self.automaticDictionaryLearningEnabled = SettingsStore.shared.automaticDictionaryLearningEnabled
            self.pronunciationMatchingEnabled = SettingsStore.shared.pronunciationMatchingEnabled
            if !SettingsStore.shared.selectedSpeechModel.supportsPronunciationMatching {
                self.pronunciationMatchingEnabled = false
                SettingsStore.shared.pronunciationMatchingEnabled = false
            }
            self.punctuationAutoConvertEnabled = SettingsStore.shared.autoConvertPunctuationEnabled
            self.punctuationPrefix = SettingsStore.shared.punctuationDictionaryPrefix
            self.punctuationRules = SettingsStore.shared.punctuationDictionaryRules
            self.vocabBoostingEnabled = SettingsStore.shared.vocabularyBoostingEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .parakeetVocabularyDidChange)) { _ in
            self.entries = SettingsStore.shared.customDictionaryEntries
        }
        .onDisappear {
            self.isAutomaticTrainingEnabled = false
            DictionaryTrainingEndpointMonitor.shared.stop()
            guard self.isTrainingRecording else { return }
            Task { @MainActor in
                await self.stopTrainingSample()
            }
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.accent)

                Text("Dictionary")
                    .basicsLabel(28)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text("Names, jargon and spellings the model keeps getting wrong. Every entry here is applied after transcription, before typing.")
                    .basicsProse(15)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: self.importDictionary) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 32))
                .help("Import a FluidVoice dictionary export (.json).")

                Button(action: self.exportDictionary) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 32))
                .help("Export replacements and custom words to a .json file.")

                Button {
                    self.presentTeachWords()
                } label: {
                    Text("Add word")
                }
                .buttonStyle(BasicsPillButtonStyle(tone: .primary, height: 36))
                .help("Teach a word by voice, or type the pair in.")
            }
            .fixedSize()
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        BasicsSegmented(
            items: DictionaryTab.allCases.map { tab in
                BasicsSegmentedItem(id: tab.rawValue, title: "\(tab.title) (\(self.count(for: tab)))")
            },
            selection: self.selectedTab.rawValue,
            isDisabled: false,
            fillsWidth: false
        ) { rawValue in
            guard let tab = DictionaryTab(rawValue: rawValue) else { return }
            self.selectedTab = tab
        }
    }

    private func count(for tab: DictionaryTab) -> Int {
        switch tab {
        case .replacements: return self.entries.count
        case .boostTerms: return self.boostTerms.count
        case .punctuation: return self.punctuationRules.count
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch self.selectedTab {
        case .replacements:
            VStack(alignment: .leading, spacing: 26) {
                self.replacementsTable
                VStack(spacing: 0) {
                    self.replacementsControlRow
                    self.autoLearnRow
                }
            }
        case .boostTerms:
            VStack(alignment: .leading, spacing: 26) {
                self.boostTermsTable
                self.boostTermsControlRow
            }
        case .punctuation:
            VStack(alignment: .leading, spacing: 26) {
                self.punctuationTable
                self.punctuationControlRow
            }
        }
    }

    // MARK: - Tab tables

    private var replacementsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsTableHeader(leading: "When it hears", leadingWidth: 280, trailing: "It types", trailingWidth: nil)

            if self.entries.isEmpty {
                BasicsEmptyState(
                    title: "No replacements yet",
                    detail: "Use Add word to teach FluidVoice its first correction."
                )
                .overlay(alignment: .top) { self.hairline }
            } else {
                ForEach(self.entries) { entry in
                    BasicsTableRow(
                        leading: entry.triggers.joined(separator: ", "),
                        leadingWidth: 280
                    ) {
                        Text(entry.replacement)
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                self.hairline
            }
        }
    }

    private var boostTermsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsTableHeader(leading: "Word", leadingWidth: nil, trailing: "Priority", trailingWidth: 96)

            if self.boostTerms.isEmpty {
                BasicsEmptyState(
                    title: "No custom words yet",
                    detail: "Add a name or term that needs a little extra recognition help."
                )
                .overlay(alignment: .top) { self.hairline }
            } else {
                ForEach(Array(self.boostTerms.enumerated()), id: \.offset) { _, term in
                    HStack(spacing: 20) {
                        Text(term.text)
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            BasicsChip(text: BoostStrengthPreset.nearest(for: term.weight ?? BoostStrengthPreset.balanced.weight).rawValue)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 96, alignment: .leading)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 2)
                    .overlay(alignment: .top) { self.hairline }
                }
                self.hairline
            }
        }
    }

    private var punctuationTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsTableHeader(leading: "When you say", leadingWidth: 280, trailing: "It types", trailingWidth: nil)

            if self.punctuationRules.isEmpty {
                BasicsEmptyState(
                    title: "No punctuation rules",
                    detail: "Add what you say and what FluidVoice should type."
                )
                .overlay(alignment: .top) { self.hairline }
            } else {
                ForEach(self.punctuationRules) { rule in
                    BasicsTableRow(
                        leading: rule.aliases.joined(separator: ", "),
                        leadingWidth: 280
                    ) {
                        Text(rule.symbol)
                            .basicsMono(14)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                self.hairline
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(self.theme.palette.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Tab control rows

    private var replacementsControlRow: some View {
        BasicsSettingRow(
            title: "Replacements",
            detail: "Words and phrases FluidVoice corrects automatically. Always on."
        ) {
            Button("Modify") { self.presentYourDictionary() }
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 32))
                .help("Modify dictionary replacements")
                .popover(isPresented: self.$isYourDictionaryPresented, arrowEdge: .top) {
                    self.yourDictionaryPopover
                }
        } trailing: {
            Color.clear
                .frame(width: 44, height: 26)
                .accessibilityHidden(true)
        }
    }

    private var autoLearnRow: some View {
        BasicsSettingRow(
            title: "Auto-learn words",
            detail: "When you correct the same word twice by hand, it proposes a rule."
        ) {
            EmptyView()
        } trailing: {
            BasicsSwitch(isOn: self.$automaticDictionaryLearningEnabled, label: "Auto-learn words")
                .onChange(of: self.automaticDictionaryLearningEnabled) { _, newValue in
                    SettingsStore.shared.automaticDictionaryLearningEnabled = newValue
                    if !newValue {
                        AutomaticDictionaryCorrectionTracker.shared.cancel()
                    }
                }
                .help("Notice corrections to recent dictation and show Train by voice suggestions.")
        }
    }

    private var boostTermsControlRow: some View {
        BasicsSettingRow(
            title: "Boost terms",
            detail: "Custom words boosting — helps Parakeet recognise names, products and uncommon terms."
        ) {
            Button("Modify") { self.presentCustomWords() }
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 32, isEnabled: self.vocabBoostingEnabled))
                .disabled(!self.vocabBoostingEnabled)
                .help(self.vocabBoostingEnabled ? "Modify custom words" : "Turn on boosting to modify custom words.")
                .popover(isPresented: self.$isCustomWordsPresented, arrowEdge: .top) {
                    self.customWordsPopover
                }
        } trailing: {
            BasicsSwitch(isOn: self.$vocabBoostingEnabled, label: "Custom words boosting")
                .onChange(of: self.vocabBoostingEnabled) { _, newValue in
                    SettingsStore.shared.vocabularyBoostingEnabled = newValue
                    if !newValue {
                        self.closeCustomWords()
                    }
                }
                .help("Improve recognition of your custom words when using Parakeet.")
        }
    }

    private var punctuationControlRow: some View {
        BasicsSettingRow(
            title: "Punctuation",
            detail: "Punctuation dictionary — say a start word, then a punctuation name, to type the symbol."
        ) {
            Button("Modify") { self.presentPunctuationDictionary() }
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 32, isEnabled: self.punctuationAutoConvertEnabled))
                .disabled(!self.punctuationAutoConvertEnabled)
                .help(self.punctuationAutoConvertEnabled ? "Modify punctuation rules" : "Turn on the punctuation dictionary to modify rules.")
                .popover(isPresented: self.$isPunctuationDictionaryPresented, arrowEdge: .top) {
                    self.punctuationDictionaryPopover
                }
        } trailing: {
            BasicsSwitch(isOn: self.$punctuationAutoConvertEnabled, label: "Punctuation dictionary")
                .onChange(of: self.punctuationAutoConvertEnabled) { _, newValue in
                    SettingsStore.shared.autoConvertPunctuationEnabled = newValue
                    if !newValue {
                        self.closePunctuationDictionary()
                    }
                }
                .help("Turn the punctuation dictionary on or off.")
        }
    }

    // MARK: - Your Dictionary popover

    private var yourDictionaryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsPanelHeader(
                title: "Your dictionary",
                detail: "FluidVoice automatically corrects these words and phrases."
            ) {
                self.closeYourDictionary()
            }

            VStack(alignment: .leading, spacing: 12) {
                BasicsSectionHead(
                    label: "Saved replacements",
                    detail: "These run automatically after dictation."
                )

                if self.entries.isEmpty {
                    BasicsEmptyState(
                        title: "No replacements yet",
                        detail: "Use Add word to create your first one."
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(self.entries) { entry in
                                DictionaryEntryRow(
                                    entry: entry,
                                    onEdit: {
                                        self.closeYourDictionary()
                                        self.editingEntry = entry
                                    },
                                    onDelete: { self.deleteEntry(entry) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 235)
                }

                BasicsNote(text: "Use Add word on the Dictionary page to create an entry by voice or by hand.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 420, alignment: .leading)
    }

    // MARK: - Custom Words popover

    private var customWordsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsPanelHeader(
                title: "Custom words",
                detail: "Add names, products and uncommon terms for Parakeet to recognise."
            ) {
                self.closeCustomWords()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 16) {
                    BasicsSectionHead(
                        label: "Saved words",
                        detail: "These get extra recognition help while boosting is on."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !self.isBoostWordEditorPresented {
                        Button {
                            self.startAddingBoostTerm()
                        } label: {
                            Label("Add word", systemImage: "plus")
                        }
                        .buttonStyle(BasicsPillButtonStyle(tone: .primary, height: 28))
                    }
                }

                if self.isBoostWordEditorPresented {
                    self.boostWordEditor
                }

                if self.boostTerms.isEmpty {
                    BasicsEmptyState(
                        title: "No custom words yet",
                        detail: "Add a name or term that needs a little extra recognition help."
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(self.boostTerms.enumerated()), id: \.offset) { index, term in
                                BoostTermRow(
                                    term: term,
                                    onEdit: { self.editBoostTerm(at: index) },
                                    onDelete: { self.deleteBoostTerm(at: index) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 235)
                }

                if self.boostHasError {
                    BasicsWarningBanner(text: self.boostStatusMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 420, alignment: .leading)
        .onDisappear {
            self.dismissBoostTermEditor()
        }
    }

    private var boostWordEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(self.boostEditorTitle)
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            VStack(alignment: .leading, spacing: 7) {
                Text("Word or phrase")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.tertiaryText)

                TextField("FluidVoice", text: self.$boostTermText)
                    .basicsProse(14)
                    .dictionaryInputChrome(isInvalid: self.isBoostTermDuplicate)
                    .onSubmit { self.saveBoostTermIfValid() }

                if self.isBoostTermDuplicate {
                    BasicsInlineWarning(text: "This word already exists.")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Word priority")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.tertiaryText)

                BasicsSegmented(
                    items: BoostStrengthPreset.allCases.map { BasicsSegmentedItem(id: $0.rawValue, title: $0.rawValue) },
                    selection: self.boostTermStrength.rawValue,
                    isDisabled: false,
                    fillsWidth: true
                ) { rawValue in
                    guard let preset = BoostStrengthPreset(rawValue: rawValue) else { return }
                    self.boostTermStrength = preset
                }

                Text(self.boostTermStrength.hint)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BasicsEditorFooter(
                onClear: { self.clearBoostTermFields() },
                onCancel: { self.dismissBoostTermEditor() },
                saveTitle: "Save word",
                canSave: self.canSaveBoostTerm,
                onSave: { self.saveBoostTermIfValid() }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .strokeBorder(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Punctuation popover

    private var punctuationDictionaryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicsPanelHeader(
                title: "Punctuation dictionary",
                detail: "Say the start word first, then the punctuation name you want to type."
            ) {
                self.closePunctuationDictionary()
            } accessory: {
                Button {
                    withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        self.isPunctuationInfoExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(BasicsSquareIconButtonStyle(isActive: self.isPunctuationInfoExpanded))
                .help("About punctuation rules")
                .accessibilityLabel("About punctuation rules")
            }

            if self.isPunctuationInfoExpanded {
                self.punctuationDictionaryInfoPanel
            }

            VStack(alignment: .leading, spacing: 8) {
                BasicsSectionHead(
                    label: "Start word",
                    detail: "Say this first so normal words do not change."
                )

                TextField("literal", text: self.$punctuationPrefix)
                    .basicsProse(14)
                    .dictionaryInputChrome()
                    .onSubmit { self.savePunctuationDictionaryPrefix() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { self.hairline }

            self.punctuationTrySayingSection

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 16) {
                    BasicsSectionHead(
                        label: "Saved rules",
                        detail: "After the start word, these spoken versions type the symbol."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !self.isPunctuationRuleEditorPresented {
                        Button {
                            self.startAddingPunctuationRule()
                        } label: {
                            Label("Add rule", systemImage: "plus")
                        }
                        .buttonStyle(BasicsPillButtonStyle(tone: .primary, height: 28))
                    }
                }

                if self.isPunctuationRuleEditorPresented {
                    self.punctuationRuleEditor
                }

                if self.punctuationRules.isEmpty {
                    BasicsEmptyState(
                        title: "No punctuation rules",
                        detail: "Add what you say and what FluidVoice should type."
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(self.punctuationRules) { rule in
                                PunctuationDictionaryRuleRow(
                                    rule: rule,
                                    onEdit: { self.editPunctuationRule(rule) },
                                    onDelete: { self.deletePunctuationRule(rule) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 235)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)

            HStack(spacing: 16) {
                Text("\(self.punctuationRules.count) \(self.punctuationRules.count == 1 ? "rule" : "rules")")
                    .basicsProse(12)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Reset defaults") { self.resetPunctuationDictionary() }
                    .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 30))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(self.theme.palette.windowBackground)
            .overlay(alignment: .top) { self.hairline }
        }
        .frame(width: 420, alignment: .leading)
        .onDisappear {
            self.savePunctuationDictionaryPrefix()
        }
    }

    private var punctuationDictionaryInfoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Say the start word first, then say the punctuation name.")
            Text("When you say “\(self.punctuationPreviewPrefix) comma”, it types “,”.")
            Text("When you say “\(self.punctuationPreviewPrefix) question mark”, it types “?”.")
            Text("For each rule, add one spoken version per line. Then choose what FluidVoice types.")
        }
        .basicsProse(13)
        .foregroundStyle(BasicsTokens.Green.g800)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(BasicsTokens.Semantic.brandSoft)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var punctuationTrySayingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BasicsSectionHead(
                label: "Try saying",
                detail: "Examples of what FluidVoice will type."
            )

            VStack(alignment: .leading, spacing: 6) {
                self.punctuationExampleRow(spoken: "\(self.punctuationPreviewPrefix) comma", typed: ",")
                self.punctuationExampleRow(spoken: "\(self.punctuationPreviewPrefix) question mark", typed: "?")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(self.theme.palette.sidebarBackground)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { self.hairline }
    }

    private func punctuationExampleRow(spoken: String, typed: String) -> some View {
        HStack(spacing: 10) {
            Text("“\(spoken)” types")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            BasicsSymbolChip(symbol: typed)
        }
    }

    private var punctuationRuleEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(self.punctuationEditorTitle)
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    self.punctuationAliasesEditor
                    self.punctuationSymbolEditor
                }

                VStack(alignment: .leading, spacing: 14) {
                    self.punctuationAliasesEditor
                    self.punctuationSymbolEditor
                }
            }

            BasicsEditorFooter(
                onClear: { self.clearPunctuationRuleFields() },
                onCancel: { self.dismissPunctuationRuleEditor() },
                saveTitle: "Save rule",
                canSave: self.canSavePunctuationRule,
                onSave: { self.savePunctuationRuleIfValid() }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .strokeBorder(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private var punctuationAliasesEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What you say")
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)

            TextEditor(text: self.$punctuationAliasesText)
                .basicsProse(14)
                .frame(minHeight: 64, maxHeight: 86)
                .scrollContentBackground(.hidden)
                .dictionaryInputChrome(minHeight: 64)

            Text("One way per line, like comma or full stop.")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var punctuationSymbolEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("It types")
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)

            TextField(",", text: self.$punctuationSymbolText)
                .basicsMono(14)
                .dictionaryInputChrome()
                .frame(width: 92)

            Text("One symbol.")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
    }

    // MARK: - Teach words composer

    private var teachWordsComposer: some View {
        VStack(spacing: 0) {
            self.composerHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch self.composerMode {
                    case .train:
                        self.trainReplacementComposer
                    case .manual:
                        self.manualReplacementComposer
                    }
                }
            }
            .frame(maxHeight: 560)

            self.composerFooter
        }
        .frame(width: 460)
        .background(self.theme.palette.cardBackground)
        .dismissTextFocusOnBackgroundTap()
        .task {
            await DictionaryTrainingEndpointMonitor.shared.prepare()
        }
    }

    private var composerHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Teach words")
                        .basicsLabel(16)
                        .foregroundStyle(self.theme.palette.primaryText)

                    Text("Show FluidVoice the right spelling, by voice or by typing.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Close") { self.dismissTeachWords() }
                    .buttonStyle(BasicsPillButtonStyle(tone: .quiet, height: 28))
                    .keyboardShortcut(.cancelAction)
            }

            BasicsSegmented(
                items: DictionaryComposerMode.allCases.map { BasicsSegmentedItem(id: $0.rawValue, title: $0.title) },
                selection: self.composerMode.rawValue,
                isDisabled: self.isTrainingRecording || self.isTrainingProcessing,
                fillsWidth: false
            ) { rawValue in
                guard let mode = DictionaryComposerMode(rawValue: rawValue) else { return }
                self.selectComposerMode(mode)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { self.hairline }
    }

    private var trainReplacementComposer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(self.composerModeDetail)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Type the correct text, e.g. FluidVoice", text: self.$trainingReplacement)
                    .basicsProse(15)
                    .dictionaryInputChrome(minHeight: 36)
                    .disabled(self.isTrainingRecording || self.isTrainingProcessing)
                    .onChange(of: self.trainingReplacement) { oldValue, newValue in
                        self.handleTrainingReplacementChange(oldValue: oldValue, newValue: newValue)
                    }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            self.voiceMatchingSection

            self.trainingRecorderPanel

            self.trainingOutputSection

            if !self.trainingVariants.isEmpty {
                self.trainingCapturedSection
            }
        }
    }

    private var voiceMatchingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matching")
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)

            BasicsSegmented(
                items: [
                    BasicsSegmentedItem(id: "basic", title: "Basic"),
                    BasicsSegmentedItem(
                        id: "advanced",
                        title: "Advanced",
                        badge: "Research",
                        isEnabled: SettingsStore.shared.selectedSpeechModel.supportsPronunciationMatching
                    ),
                ],
                selection: self.activePronunciationMatching ? "advanced" : "basic",
                isDisabled: self.isTrainingRecording || self.isTrainingProcessing,
                fillsWidth: true
            ) { rawValue in
                let enabled = rawValue == "advanced"
                guard enabled != self.activePronunciationMatching else { return }
                self.pronunciationMatchingEnabled = enabled
                self.handlePronunciationMatchingChange(enabled: enabled)
            }

            if self.activePronunciationMatching {
                Text("Research preview: compares how your voice sounds instead of only the words FluidVoice hears. Results may vary.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !SettingsStore.shared.selectedSpeechModel.supportsPronunciationMatching {
                Text("Advanced voice matching requires Parakeet TDT on Apple silicon.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trainingRecorderPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach FluidVoice your pronunciation")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            if self.trainingState == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    self.trainingInstruction(number: 1, text: "Type the correct word you want to teach in the box above.")
                    self.trainingInstruction(number: 2, text: "Press Start once.")
                    self.trainingInstruction(
                        number: 3,
                        text: "Say \(self.trainingTargetReference) naturally, then pause. FluidVoice records and listens again automatically."
                    )
                    self.trainingInstruction(
                        number: 4,
                        text: self.activePronunciationMatching
                            ? "Repeat 3 times to teach FluidVoice how your voice sounds."
                            : "Keep repeating it until the circle reaches 3/3."
                    )
                }
            }

            HStack(alignment: .center, spacing: 16) {
                DictionaryTrainingReadinessRing(
                    progress: self.trainingReadinessProgress,
                    total: CustomDictionaryTrainingMerge.readyCoveredCount,
                    isReady: self.trainingFinalOutputIsReady || self.trainingAlreadyCorrectWithoutReplacement
                )

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = self.trainingStateTitle {
                            Text(title)
                                .basicsLabel(14)
                                .foregroundStyle(self.theme.palette.primaryText)
                        }

                        Text(self.trainingStateDetail)
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await self.toggleAutomaticTraining() }
                        } label: {
                            if self.trainingRecorderIsStop {
                                Label {
                                    Text(self.trainingRecorderButtonTitle)
                                } icon: {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .frame(width: 9, height: 9)
                                }
                            } else if self.canRetryTrainingAfterMaximum {
                                Text(self.trainingRecorderButtonTitle)
                            } else {
                                Label(self.trainingRecorderButtonTitle, systemImage: "mic.fill")
                            }
                        }
                        .buttonStyle(
                            BasicsPillButtonStyle(
                                tone: self.trainingRecorderIsStop ? .danger : .primary,
                                height: 34,
                                isEnabled: self.canUseTrainingRecorderButton
                            )
                        )
                        .disabled(!self.canUseTrainingRecorderButton)

                        Button("Clear") { self.resetTraining() }
                            .buttonStyle(
                                BasicsPillButtonStyle(
                                    tone: .outline,
                                    height: 34,
                                    isEnabled: !(self.isTrainingRecording || self.isTrainingProcessing)
                                )
                            )
                            .disabled(self.isTrainingRecording || self.isTrainingProcessing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.trainingHasError ? BasicsTokens.Semantic.warning.opacity(0.08) : self.theme.palette.windowBackground)
        .overlay(alignment: .top) { self.hairline }
    }

    private var trainingOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Final output")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(width: 96, alignment: .leading)

                Text(self.trainingFinalOutputText)
                    .basicsProse(14)
                    .foregroundStyle(
                        self.lastTrainingOutput.isEmpty
                            ? self.theme.palette.tertiaryText
                            : self.theme.palette.primaryText
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Heard")
                    .basicsMicroLabel()
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(width: 96, alignment: .leading)

                Text(self.lastTrainingOutput.isEmpty ? "—" : self.lastTrainingOutput)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { self.hairline }
    }

    private var trainingCapturedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Captured")
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)

            FlowLayout(spacing: 6) {
                ForEach(Array(self.trainingVariants.prefix(5)), id: \.self) { variant in
                    TrainingVariantChip(variant: variant) {
                        self.removeTrainingVariant(variant)
                    }
                }

                if self.trainingVariants.count > 5 {
                    Text("+\(self.trainingVariants.count - 5)")
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(self.theme.palette.sidebarBackground))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { self.hairline }
    }

    private var manualReplacementComposer: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                BasicsSectionHead(
                    label: "When FluidVoice hears",
                    detail: "Separate different versions with commas. Enter only commas to replace comma punctuation."
                )

                TextField("fluid voice, fluid boys", text: self.$manualTriggerDraft)
                    .basicsProse(14)
                    .dictionaryInputChrome(minHeight: 36, isInvalid: !self.manualDuplicateTriggers.isEmpty)
                    .onSubmit { self.addManualReplacementIfValid() }

                if !self.manualDuplicateTriggers.isEmpty {
                    BasicsInlineWarning(text: "Already used: \(self.manualDuplicateTriggers.joined(separator: ", "))")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                BasicsSectionHead(
                    label: "Change it to",
                    detail: "This is what appears in your transcription."
                )

                TextField("FluidVoice", text: self.$manualReplacement)
                    .basicsProse(14)
                    .dictionaryInputChrome(minHeight: 36)
                    .onSubmit { self.addManualReplacementIfValid() }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var composerFooter: some View {
        switch self.composerMode {
        case .train:
            HStack(spacing: 12) {
                if self.trainingHasError {
                    BasicsInlineWarning(text: self.trainingStatusMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(self.trainingStatusMessage.isEmpty ? "Type the correct text." : self.trainingStatusMessage)
                        .basicsProse(12)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await self.addTrainedReplacement() }
                } label: {
                    Text(self.trainedReplacementButtonTitle)
                }
                .buttonStyle(
                    BasicsPillButtonStyle(
                        tone: .primary,
                        height: 32,
                        isEnabled: self.canAddTrainedReplacement
                    )
                )
                .disabled(!self.canAddTrainedReplacement)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(self.theme.palette.windowBackground)
            .overlay(alignment: .top) { self.hairline }

        case .manual:
            HStack(spacing: 12) {
                if self.manualDuplicateTriggers.isEmpty {
                    Text("Return also saves")
                        .basicsProse(12)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    BasicsInlineWarning(text: "Fix the duplicate to continue")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Add replacement") { self.addManualReplacementIfValid() }
                    .buttonStyle(
                        BasicsPillButtonStyle(
                            tone: .primary,
                            height: 32,
                            isEnabled: self.canAddManualReplacement
                        )
                    )
                    .disabled(!self.canAddManualReplacement)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(self.theme.palette.windowBackground)
            .overlay(alignment: .top) { self.hairline }
        }
    }

    // MARK: - Training state

    private enum TrainingState: Equatable {
        case idle
        case recording
        case processing
        case ready
        case alreadyCorrect
        case maxSamples
        case failed
    }

    private var trainingState: TrainingState {
        if self.isTrainingRecording || self.isTrainingStarting { return .recording }
        if self.isTrainingProcessing { return .processing }
        if self.trainingHasError { return .failed }
        if self.trainingAlreadyCorrectWithoutReplacement { return .alreadyCorrect }
        if self.trainingFinalOutputIsReady { return .ready }
        if self.canRetryTrainingAfterMaximum { return .maxSamples }
        return .idle
    }

    private var trainingStateTitle: String? {
        switch self.trainingState {
        case .idle: return nil
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .ready: return "Ready"
        case .alreadyCorrect: return "Already correct"
        case .maxSamples: return "Max samples reached"
        case .failed: return self.trainingErrorTitle.isEmpty ? "Try again" : self.trainingErrorTitle
        }
    }

    private var trainingStateDetail: String {
        switch self.trainingState {
        case .failed, .maxSamples:
            return self.trainingStatusMessage
        case .processing:
            return self.trainingStatusMessage.isEmpty
                ? "Controls stay disabled until the sample is scored."
                : self.trainingStatusMessage
        default:
            return self.trainingReadinessCaption
        }
    }

    private var trainingReadinessCaption: String {
        DictionaryTrainingCopy.readinessCaption(
            target: self.trainingTargetReference,
            isAlreadyCorrect: self.trainingAlreadyCorrectWithoutReplacement,
            isReady: self.trainingFinalOutputIsReady,
            usesVoiceMatching: self.activePronunciationMatching
        )
    }

    // MARK: - Actions

    private func presentTeachWords() {
        self.entries = SettingsStore.shared.customDictionaryEntries
        self.isTeachWordsPresented = true
    }

    private func dismissTeachWords() {
        self.isAutomaticTrainingEnabled = false
        DictionaryTrainingEndpointMonitor.shared.stop()
        if self.isTrainingRecording {
            Task { @MainActor in
                await self.stopTrainingSample()
            }
        }
        self.isTeachWordsPresented = false
    }

    private func saveEntries() {
        SettingsStore.shared.customDictionaryEntries = self.entries
        // Invalidate cached regex patterns so changes take effect immediately
        ASRService.invalidateDictionaryCache()
        NotificationCenter.default.post(name: .parakeetVocabularyDidChange, object: nil)
    }

    private func addReplacementEntry(_ entry: SettingsStore.CustomDictionaryEntry) {
        self.entries.insert(entry, at: 0)
        self.saveEntries()
        self.showReplacementConfirmation(
            title: "Replacement added",
            detail: "It is at the top of the list."
        )
    }

    private func selectComposerMode(_ mode: DictionaryComposerMode) {
        guard !self.isTrainingRecording, !self.isTrainingProcessing else { return }
        self.composerMode = mode
    }

    private func addManualReplacementIfValid() {
        guard self.canAddManualReplacement else { return }
        let entry = SettingsStore.CustomDictionaryEntry(
            triggers: self.manualTriggers,
            replacement: self.manualReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.addReplacementEntry(entry)
        self.manualTriggerDraft = ""
        self.manualReplacement = ""
    }

    private func presentYourDictionary() {
        self.entries = SettingsStore.shared.customDictionaryEntries
        self.isYourDictionaryPresented = true
    }

    private func closeYourDictionary() {
        self.isYourDictionaryPresented = false
    }

    private func presentPunctuationDictionary() {
        self.punctuationPrefix = SettingsStore.shared.punctuationDictionaryPrefix
        self.punctuationRules = SettingsStore.shared.punctuationDictionaryRules
        self.isPunctuationInfoExpanded = false
        self.dismissPunctuationRuleEditor()
        self.isPunctuationDictionaryPresented = true
    }

    private func closePunctuationDictionary() {
        self.savePunctuationDictionaryPrefix()
        self.isPunctuationInfoExpanded = false
        self.isPunctuationDictionaryPresented = false
    }

    private func savePunctuationDictionaryPrefix() {
        SettingsStore.shared.punctuationDictionaryPrefix = self.punctuationPrefix
        self.punctuationPrefix = SettingsStore.shared.punctuationDictionaryPrefix
    }

    private func savePunctuationRules() {
        SettingsStore.shared.punctuationDictionaryRules = self.punctuationRules
        self.punctuationRules = SettingsStore.shared.punctuationDictionaryRules
    }

    private func startAddingPunctuationRule() {
        self.editingPunctuationRuleID = nil
        self.clearPunctuationRuleFields()
        self.isPunctuationRuleEditorPresented = true
    }

    private func savePunctuationRuleIfValid() {
        guard self.canSavePunctuationRule, let symbol = self.normalizedPunctuationSymbol else { return }
        self.savePunctuationDictionaryPrefix()
        let rule = SettingsStore.PunctuationDictionaryRule(
            id: self.editingPunctuationRuleID ?? UUID(),
            aliases: self.normalizedPunctuationAliases,
            symbol: symbol
        )

        if let editingID = self.editingPunctuationRuleID,
           let index = self.punctuationRules.firstIndex(where: { $0.id == editingID })
        {
            self.punctuationRules[index] = rule
        } else {
            self.punctuationRules.insert(rule, at: 0)
        }

        self.savePunctuationRules()
        self.dismissPunctuationRuleEditor()
    }

    private func editPunctuationRule(_ rule: SettingsStore.PunctuationDictionaryRule) {
        self.editingPunctuationRuleID = rule.id
        self.punctuationAliasesText = rule.aliases.joined(separator: "\n")
        self.punctuationSymbolText = rule.symbol
        self.isPunctuationRuleEditorPresented = true
    }

    private func deletePunctuationRule(_ rule: SettingsStore.PunctuationDictionaryRule) {
        self.punctuationRules.removeAll { $0.id == rule.id }
        if self.editingPunctuationRuleID == rule.id {
            self.dismissPunctuationRuleEditor()
        }
        self.savePunctuationRules()
    }

    private func resetPunctuationDictionary() {
        self.punctuationPrefix = SettingsStore.defaultPunctuationDictionaryPrefix
        self.punctuationRules = SettingsStore.defaultPunctuationDictionaryRules
        self.dismissPunctuationRuleEditor()
        self.savePunctuationDictionaryPrefix()
        self.savePunctuationRules()
    }

    private func clearPunctuationRuleFields() {
        self.punctuationAliasesText = ""
        self.punctuationSymbolText = ""
    }

    private func dismissPunctuationRuleEditor() {
        self.editingPunctuationRuleID = nil
        self.clearPunctuationRuleFields()
        self.isPunctuationRuleEditorPresented = false
    }

    private func presentCustomWords() {
        self.loadBoostTerms()
        self.dismissBoostTermEditor()
        self.isCustomWordsPresented = true
    }

    private func closeCustomWords() {
        self.dismissBoostTermEditor()
        self.isCustomWordsPresented = false
    }

    private func startAddingBoostTerm() {
        self.editingBoostTermIndex = nil
        self.clearBoostTermFields()
        self.isBoostWordEditorPresented = true
    }

    private func editBoostTerm(at index: Int) {
        guard self.boostTerms.indices.contains(index) else { return }
        let term = self.boostTerms[index]
        self.editingBoostTermIndex = index
        self.boostTermText = term.text
        self.boostTermStrength = BoostStrengthPreset.nearest(for: term.weight ?? BoostStrengthPreset.balanced.weight)
        self.isBoostWordEditorPresented = true
    }

    private func saveBoostTermIfValid() {
        guard self.canSaveBoostTerm else { return }
        let updatedTerm = ParakeetVocabularyStore.VocabularyConfig.Term(
            text: self.normalizedBoostTermText,
            weight: self.boostTermStrength.weight,
            aliases: []
        )

        if let index = self.editingBoostTermIndex,
           self.boostTerms.indices.contains(index)
        {
            self.boostTerms[index] = ParakeetVocabularyStore.VocabularyConfig.Term(
                text: updatedTerm.text,
                weight: updatedTerm.weight,
                aliases: self.boostTerms[index].aliases
            )
        } else {
            self.boostTerms.append(updatedTerm)
        }

        self.saveBoostTerms()
        self.dismissBoostTermEditor()
    }

    private func clearBoostTermFields() {
        self.boostTermText = ""
        self.boostTermStrength = .balanced
    }

    private func dismissBoostTermEditor() {
        self.editingBoostTermIndex = nil
        self.clearBoostTermFields()
        self.isBoostWordEditorPresented = false
    }

    private func toggleAutomaticTraining() async {
        if self.isAutomaticTrainingEnabled {
            self.isAutomaticTrainingEnabled = false
            if self.isTrainingRecording {
                await self.stopTrainingSample()
            }
            return
        }

        if self.canRetryTrainingAfterMaximum {
            self.resetTrainingVerificationAttempts()
        }
        guard self.canRecordTrainingSample else { return }
        self.isAutomaticTrainingEnabled = true
        await self.startTrainingSample()
    }

    private func startTrainingSample() async {
        guard self.isAutomaticTrainingEnabled, self.canRecordTrainingSample else {
            self.isAutomaticTrainingEnabled = false
            return
        }
        self.trainingHasError = false
        self.trainingErrorTitle = ""
        self.trainingStatusMessage = ""
        self.trainingStopRequestedDuringStart = false
        self.isTrainingStarting = true
        self.isTrainingRecording = true

        await self.asr.start(forDictionaryTraining: true)
        self.isTrainingStarting = false
        if !self.asr.isRunning {
            self.isTrainingRecording = false
            self.trainingStopRequestedDuringStart = false
            self.isAutomaticTrainingEnabled = false
            self.trainingHasError = true
            self.trainingErrorTitle = "Microphone blocked"
            self.trainingStatusMessage = "Couldn't start recording. Check microphone access and try again."
            return
        }

        if self.trainingStopRequestedDuringStart {
            await self.finishTrainingSampleStop()
            return
        }
        DictionaryTrainingEndpointMonitor.shared.start(asr: self.asr) {
            self.handleAutomaticTrainingSpeechEnd()
        }
    }

    private func stopTrainingSample() async {
        DictionaryTrainingEndpointMonitor.shared.stop()
        guard self.isTrainingRecording else { return }
        guard !self.trainingStopRequestedDuringStart else { return }

        guard !self.isTrainingStarting, self.asr.isRunning else {
            self.trainingStopRequestedDuringStart = true
            self.trainingHasError = false
            self.trainingErrorTitle = ""
            self.trainingStatusMessage = "Stopping..."
            return
        }

        await self.finishTrainingSampleStop()
    }

    private func handleAutomaticTrainingSpeechEnd() {
        guard self.isAutomaticTrainingEnabled, self.isTrainingRecording else { return }
        Task { await self.stopTrainingSample() }
    }

    private func finishTrainingSampleStop() async {
        guard self.isTrainingRecording else { return }
        DictionaryTrainingEndpointMonitor.shared.stop()
        self.isTrainingRecording = false
        self.isTrainingStarting = false
        self.trainingStopRequestedDuringStart = false
        self.isTrainingProcessing = true
        self.trainingHasError = false
        self.trainingErrorTitle = ""
        self.trainingStatusMessage = ""

        let transcript = await self.asr.stop(forDictionaryTraining: true)
        self.isTrainingProcessing = false
        if self.activePronunciationMatching,
           CustomDictionaryTrainingMerge.normalizedTrigger(transcript) != nil,
           let enrollment = self.asr.lastDictionaryTrainingResult?.pronunciationEnrollment
        {
            self.trainingPronunciationEnrollments.append(enrollment)
        }
        self.addTrainingVariant(from: transcript)
        await self.continueAutomaticTrainingIfNeeded()
    }

    private func continueAutomaticTrainingIfNeeded() async {
        guard self.isAutomaticTrainingEnabled,
              !self.trainingFinalOutputIsReady,
              !self.trainingAlreadyCorrectWithoutReplacement,
              self.trainingSampleCount < CustomDictionaryTrainingMerge.maxSamples
        else {
            self.isAutomaticTrainingEnabled = false
            return
        }

        await Task.yield()
        await self.startTrainingSample()
    }

    private func resetTrainingVerificationAttempts() {
        self.trainingSampleCount = 0
        self.lastTrainingOutput = ""
        self.lastTrainingOutputIsCovered = false
        self.consecutiveCoveredCaptures = 0
        self.trainingStatusMessage = ""
        self.trainingHasError = false
        self.trainingErrorTitle = ""
    }

    private func addTrainingVariant(from transcript: String) {
        if self.activePronunciationMatching,
           self.asr.lastDictionaryTrainingResult?.pronunciationEnrollment == nil
        {
            self.trainingHasError = true
            self.trainingErrorTitle = "Voice profile not captured"
            self.trainingStatusMessage = "Couldn't capture a voice profile. Try again with one clear word."
            return
        }
        guard let detected = CustomDictionaryTrainingMerge.normalizedTrigger(transcript) else {
            self.lastTrainingOutput = ""
            self.lastTrainingOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
            self.trainingHasError = true
            self.trainingErrorTitle = "Nothing heard"
            self.trainingStatusMessage = "Nothing heard. Try again."
            return
        }

        self.lastTrainingOutput = detected
        self.trainingSampleCount = min(self.trainingSampleCount + 1, CustomDictionaryTrainingMerge.maxSamples)

        if detected.caseInsensitiveCompare(self.normalizedTrainingReplacement) == .orderedSame {
            self.lastTrainingOutputIsCovered = true
            self.consecutiveCoveredCaptures += 1
            self.trainingHasError = false
            self.trainingErrorTitle = ""
            if self.consecutiveCoveredCaptures >= CustomDictionaryTrainingMerge.readyCoveredCount {
                self.trainingStatusMessage = self.trainingVariants.isEmpty
                    ? "Looks good already. No replacement needed."
                    : "Looks ready. Add this replacement when you're ready."
            } else {
                self.trainingStatusMessage = "Covered. Try a couple more."
            }
            return
        }

        let wasAlreadyCaptured = self.trainingVariants.contains { $0.caseInsensitiveCompare(detected) == .orderedSame }
        let wasAlreadySaved = self.savedDictionaryCovers(detected)

        if wasAlreadyCaptured || wasAlreadySaved {
            self.lastTrainingOutputIsCovered = true
            self.consecutiveCoveredCaptures += 1
            self.trainingHasError = false
            self.trainingErrorTitle = ""
            if self.consecutiveCoveredCaptures >= CustomDictionaryTrainingMerge.readyCoveredCount {
                self.trainingStatusMessage = "Looks ready. Add this replacement when you're ready."
            } else if wasAlreadySaved {
                self.trainingStatusMessage = "Covered by your dictionary."
            } else {
                self.trainingStatusMessage = "Already captured. Try a couple more."
            }
            return
        }

        guard self.trainingVariants.count < CustomDictionaryTrainingMerge.maxSamples else {
            self.lastTrainingOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
            self.trainingHasError = false
            self.trainingErrorTitle = ""
            self.trainingStatusMessage = "Max samples reached. Add it or clear one."
            return
        }

        self.trainingVariants.append(detected)
        self.lastTrainingOutputIsCovered = false
        self.consecutiveCoveredCaptures = 0
        self.trainingHasError = false
        self.trainingErrorTitle = ""
        if self.trainingSampleCount >= CustomDictionaryTrainingMerge.maxSamples || self.trainingVariants.count >= CustomDictionaryTrainingMerge.maxSamples {
            self.trainingStatusMessage = "Max samples reached. Add it or clear one."
        } else {
            self.trainingStatusMessage = "New pronunciation captured. Add replacement to cover it."
        }
    }

    private func addTrainedReplacement() async {
        guard self.canAddTrainedReplacement else { return }
        self.isTrainingProcessing = true
        let replacementText = self.normalizedTrainingReplacement
        let updatesExisting = self.entries.contains {
            $0.replacement.caseInsensitiveCompare(replacementText) == .orderedSame
        }
        self.entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: self.entries,
            replacement: replacementText,
            triggers: self.trainingVariants
        )
        let entry = self.entries.first {
            $0.replacement.caseInsensitiveCompare(replacementText) == .orderedSame
        }
        let enrollments = self.trainingPronunciationEnrollments
        if self.activePronunciationMatching, let entry, let modelKey = enrollments.first?.modelKey {
            do {
                try await PronunciationDictionaryStore.shared.upsert(
                    dictionaryEntryID: entry.id,
                    label: replacementText,
                    modelKey: modelKey,
                    enrollments: enrollments
                )
            } catch {
                self.isTrainingProcessing = false
                self.trainingHasError = true
                self.trainingErrorTitle = "Voice profile not saved"
                self.trainingStatusMessage = "Couldn't save the voice profile. Try again."
                DebugLogger.shared.error(
                    "Failed to save pronunciation profile: \(error.localizedDescription)",
                    source: "PronunciationMatching"
                )
                return
            }
        }
        self.saveEntries()
        self.resetTraining()
        self.showReplacementConfirmation(
            title: updatesExisting ? "Replacement updated" : "Recorded",
            detail: updatesExisting ? "Your variants are ready." : "Replacement added at the top."
        )
    }

    private func removeTrainingVariant(_ variant: String) {
        self.trainingVariants.removeAll { $0 == variant }
        self.refreshLastTrainingCoverage()
    }

    private func refreshLastTrainingCoverage() {
        guard !self.lastTrainingOutput.isEmpty else {
            self.lastTrainingOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
            return
        }

        let matchesReplacement = self.lastTrainingOutput.caseInsensitiveCompare(self.normalizedTrainingReplacement) == .orderedSame
        let isStillCaptured = self.trainingVariants.contains {
            $0.caseInsensitiveCompare(self.lastTrainingOutput) == .orderedSame
        }

        if matchesReplacement || isStillCaptured || self.savedDictionaryCovers(self.lastTrainingOutput) {
            self.lastTrainingOutputIsCovered = true
        } else {
            self.lastTrainingOutputIsCovered = false
            self.consecutiveCoveredCaptures = 0
        }
    }

    private func resetTraining(statusMessage: String = "Type the correct text.") {
        self.isAutomaticTrainingEnabled = false
        DictionaryTrainingEndpointMonitor.shared.stop()
        self.trainingReplacement = ""
        self.trainingVariants = []
        self.trainingPronunciationEnrollments = []
        self.trainingSampleCount = 0
        self.lastTrainingOutput = ""
        self.lastTrainingOutputIsCovered = false
        self.consecutiveCoveredCaptures = 0
        self.trainingStatusMessage = statusMessage
        self.trainingHasError = false
        self.trainingErrorTitle = ""
        self.isTrainingStarting = false
        self.isTrainingRecording = false
        self.trainingStopRequestedDuringStart = false
        self.isTrainingProcessing = false
    }

    private func handleTrainingReplacementChange(oldValue: String, newValue: String) {
        let oldKey = CustomDictionaryTrainingMerge.normalizedReplacement(oldValue).lowercased()
        let newKey = CustomDictionaryTrainingMerge.normalizedReplacement(newValue).lowercased()
        guard oldKey != newKey else { return }

        self.trainingVariants = self.existingTrainingVariants(for: newValue)
        self.trainingPronunciationEnrollments = []
        self.trainingSampleCount = 0
        self.lastTrainingOutput = ""
        self.lastTrainingOutputIsCovered = false
        self.consecutiveCoveredCaptures = 0
        if newKey.isEmpty {
            self.trainingStatusMessage = "Type the correct text."
        } else if self.trainingVariants.isEmpty {
            self.trainingStatusMessage = ""
        } else {
            self.trainingStatusMessage = "Loaded \(self.trainingVariants.count) saved \(self.trainingVariants.count == 1 ? "capture" : "captures")."
        }
        self.trainingHasError = false
        self.trainingErrorTitle = ""
    }

    private func existingTrainingVariants(for replacement: String) -> [String] {
        let replacementText = CustomDictionaryTrainingMerge.normalizedReplacement(replacement)
        guard !replacementText.isEmpty else { return [] }

        let triggers = self.entries
            .filter { $0.replacement.caseInsensitiveCompare(replacementText) == .orderedSame }
            .flatMap(\.triggers)

        return CustomDictionaryTrainingMerge.normalizedTriggers(
            from: triggers,
            intendedReplacement: replacementText
        )
    }

    private func savedDictionaryCovers(_ trigger: String) -> Bool {
        guard let triggerKey = CustomDictionaryTrainingMerge.normalizedTrigger(trigger),
              !self.normalizedTrainingReplacement.isEmpty
        else {
            return false
        }

        return self.entries.contains { entry in
            entry.replacement.caseInsensitiveCompare(self.normalizedTrainingReplacement) == .orderedSame &&
                entry.triggers.contains { savedTrigger in
                    guard let savedKey = CustomDictionaryTrainingMerge.normalizedTrigger(savedTrigger) else { return false }
                    return savedKey == triggerKey
                }
        }
    }

    private func showReplacementConfirmation(title: String, detail: String) {
        let confirmation = ReplacementConfirmation(title: title, detail: detail)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        withAnimation(self.reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78)) {
            self.replacementConfirmation = confirmation
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard self.replacementConfirmation?.id == confirmation.id else { return }
            withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.16)) {
                self.replacementConfirmation = nil
            }
        }
    }

    private func loadBoostTerms() {
        do {
            self.boostTerms = try ParakeetVocabularyStore.shared.loadUserBoostTerms()
            self.boostStatusMessage = "Loaded \(self.boostTerms.count) custom words."
            self.boostHasError = false
        } catch {
            self.boostTerms = []
            self.boostStatusMessage = "Couldn't load custom words: \(error.localizedDescription)"
            self.boostHasError = true
        }
    }

    private func saveBoostTerms() {
        do {
            try ParakeetVocabularyStore.shared.saveUserBoostTerms(self.boostTerms)
            self.boostStatusMessage = "Saved \(self.boostTerms.count) custom words."
            self.boostHasError = false
        } catch {
            self.boostStatusMessage = "Couldn't save custom words: \(error.localizedDescription)"
            self.boostHasError = true
        }
    }

    private func exportDictionary() {
        do {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = DictionaryTransferService.shared.suggestedFilename()

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let document = try DictionaryTransferService.shared.makeExportDocument()
            let data = try DictionaryTransferService.shared.encode(document)
            try data.write(to: url, options: .atomic)

            self.presentInfoAlert(
                title: "Dictionary exported",
                message: "Saved \(document.replacements.count) replacement rules and \(document.customWords.count) custom words."
            )
        } catch {
            self.presentErrorAlert(title: "Dictionary export failed", message: error.localizedDescription)
        }
    }

    private func importDictionary() {
        do {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.json]

            guard panel.runModal() == .OK, let url = panel.url else { return }

            let data = try Data(contentsOf: url)
            let document = try DictionaryTransferService.shared.decode(data)
            guard let mode = self.confirmDictionaryImport(document) else { return }
            let summary = try DictionaryTransferService.shared.restore(document, mode: mode)
            self.entries = SettingsStore.shared.customDictionaryEntries
            self.punctuationRules = SettingsStore.shared.punctuationDictionaryRules
            self.loadBoostTerms()

            self.presentInfoAlert(
                title: "Dictionary imported",
                message: "Now using \(summary.replacementCount) replacement rules and \(summary.customWordCount) custom words."
            )
        } catch {
            self.presentErrorAlert(title: "Dictionary import failed", message: error.localizedDescription)
        }
    }

    private func confirmDictionaryImport(_ document: DictionaryTransferDocument) -> DictionaryTransferImportMode? {
        let confirm = NSAlert()
        confirm.messageText = "Import this dictionary?"
        confirm.informativeText = """
        Found \(document.replacements.count) replacement rules and \(document.customWords.count) custom words. \
        Merge adds them to your current dictionary. Replace clears the current dictionary first.
        """
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Merge")
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")

        switch confirm.runModal() {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replace
        default:
            return nil
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

    private func deleteBoostTerm(at index: Int) {
        guard self.boostTerms.indices.contains(index) else { return }
        self.boostTerms.remove(at: index)
        if self.editingBoostTermIndex == index {
            self.dismissBoostTermEditor()
        } else if let editingIndex = self.editingBoostTermIndex, index < editingIndex {
            self.editingBoostTermIndex = editingIndex - 1
        }
        self.saveBoostTerms()
    }

    private func deleteEntry(_ entry: SettingsStore.CustomDictionaryEntry) {
        self.entries.removeAll { $0.id == entry.id }
        self.saveEntries()
        Task {
            try? await PronunciationDictionaryStore.shared.delete(dictionaryEntryID: entry.id)
        }
    }

    /// Returns all existing trigger words for duplicate detection
    private func allExistingTriggers(excluding entryId: UUID? = nil) -> Set<String> {
        var triggers = Set<String>()
        for entry in self.entries where entry.id != entryId {
            for trigger in entry.triggers {
                triggers.insert(trigger.lowercased())
            }
        }
        return triggers
    }

    private func existingBoostTerms(excludingIndex: Int? = nil) -> Set<String> {
        var terms: Set<String> = []
        for (index, term) in self.boostTerms.enumerated() where index != excludingIndex {
            terms.insert(term.text.lowercased())
        }
        return terms
    }
}

private extension CustomDictionaryView {
    var asr: ASRService { self.appServices.asr }

    var trainedReplacementButtonTitle: String {
        self.trainingAlreadyCorrectWithoutReplacement ? "Nothing to save" : "Add replacement"
    }

    func trainingInstruction(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 19, height: 19)
                .background(Circle().fill(self.theme.palette.sidebarBackground))

            Text(text)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func handlePronunciationMatchingChange(enabled: Bool) {
        SettingsStore.shared.pronunciationMatchingEnabled = enabled
        self.isAutomaticTrainingEnabled = false
        DictionaryTrainingEndpointMonitor.shared.stop()
        self.trainingVariants = self.existingTrainingVariants(for: self.trainingReplacement)
        self.trainingPronunciationEnrollments = []
        self.resetTrainingVerificationAttempts()
        self.trainingStatusMessage = self.normalizedTrainingReplacement.isEmpty
            ? "Type the correct text."
            : ""
    }
}

// MARK: - Tabs and composer modes

private enum DictionaryTab: String, CaseIterable, Identifiable {
    case replacements
    case boostTerms
    case punctuation

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .replacements: return "Replacements"
        case .boostTerms: return "Boost terms"
        case .punctuation: return "Punctuation"
        }
    }
}

private enum DictionaryComposerMode: String, CaseIterable, Identifiable {
    case train
    case manual

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .train: return "Train by voice"
        case .manual: return "Add manually"
        }
    }

    var detail: String {
        switch self {
        case .train: return "Teach a word by speaking it."
        case .manual: return "Type the misheard text and the spelling you want."
        }
    }
}

private enum DictionaryTrainingCopy {
    static func target(for normalizedTarget: String) -> String {
        normalizedTarget.isEmpty ? "the word" : "“\(normalizedTarget)”"
    }

    static func composerDetail(mode: DictionaryComposerMode, target: String) -> String {
        mode == .train && target != "the word" ? "Teach \(target) by speaking it." : mode.detail
    }

    static func readinessCaption(
        target: String,
        isAlreadyCorrect: Bool,
        isReady: Bool,
        usesVoiceMatching: Bool
    ) -> String {
        if isAlreadyCorrect {
            return "No replacement is needed for \(target)."
        }
        if isReady {
            return usesVoiceMatching
                ? "Ready. FluidVoice learned how \(target) sounds in your voice."
                : "Ready. FluidVoice got \(target) right 3 times in a row."
        }
        return usesVoiceMatching
            ? "Say \(target) 3 times to unlock Add replacement."
            : "Keep trying until FluidVoice gets \(target) right 3 times in a row."
    }
}

// MARK: - Basics primitives (Dictionary)

private enum BasicsPillTone {
    case primary
    case outline
    case quiet
    case danger
}

private struct BasicsPillButtonStyle: ButtonStyle {
    let tone: BasicsPillTone
    var height: CGFloat = 32
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        PillBody(tone: self.tone, height: self.height, isEnabled: self.isEnabled, isPressed: configuration.isPressed) {
            configuration.label
        }
    }

    private struct PillBody<Label: View>: View {
        let tone: BasicsPillTone
        let height: CGFloat
        let isEnabled: Bool
        let isPressed: Bool
        @ViewBuilder let label: Label

        @Environment(\.theme) private var theme

        var body: some View {
            self.label
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
                .basicsButtonLabel(self.height >= 32 ? 14 : 13)
                .foregroundStyle(self.foreground)
                .padding(.horizontal, self.height >= 32 ? 16 : 12)
                .frame(height: self.height)
                .background(
                    Capsule(style: .continuous)
                        .fill(self.fill)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(self.stroke, lineWidth: 1)
                        )
                )
                .opacity(self.isPressed ? 0.84 : 1)
                .contentShape(Capsule(style: .continuous))
        }

        private var foreground: Color {
            guard self.isEnabled else { return self.theme.palette.tertiaryText }
            switch self.tone {
            case .primary: return .white
            case .outline: return self.theme.palette.primaryText
            case .quiet: return self.theme.palette.secondaryText
            case .danger: return BasicsTokens.Semantic.danger
            }
        }

        private var fill: Color {
            guard self.isEnabled else {
                return self.tone == .primary ? self.theme.palette.sidebarBackground : .clear
            }
            switch self.tone {
            case .primary: return self.theme.palette.accent
            case .outline, .danger: return self.theme.palette.cardBackground
            case .quiet: return .clear
            }
        }

        private var stroke: Color {
            guard self.isEnabled else { return .clear }
            switch self.tone {
            case .primary, .quiet: return .clear
            case .outline: return BasicsTokens.Surface.borderStrong
            case .danger: return BasicsTokens.Semantic.danger
            }
        }
    }
}

private struct BasicsSquareIconButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        IconBody(isActive: self.isActive, isPressed: configuration.isPressed) {
            configuration.label
        }
    }

    private struct IconBody<Label: View>: View {
        let isActive: Bool
        let isPressed: Bool
        @ViewBuilder let label: Label

        @Environment(\.theme) private var theme

        var body: some View {
            self.label
                .foregroundStyle(self.isActive ? self.theme.palette.accent : self.theme.palette.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(self.isActive ? BasicsTokens.Semantic.brandSoft : self.theme.palette.sidebarBackground)
                )
                .opacity(self.isPressed ? 0.82 : 1)
                .contentShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous))
        }
    }
}

private struct BasicsSegmentedItem: Identifiable {
    let id: String
    let title: String
    var badge: String?
    var isEnabled: Bool = true
}

private struct BasicsSegmented: View {
    let items: [BasicsSegmentedItem]
    let selection: String
    let isDisabled: Bool
    let fillsWidth: Bool
    let onSelect: (String) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(self.items) { item in
                Button {
                    guard item.isEnabled, !self.isDisabled, item.id != self.selection else { return }
                    self.onSelect(item.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .basicsLabel(13)

                        if let badge = item.badge {
                            Text(badge)
                                .basicsMicroLabel(10)
                                .foregroundStyle(self.theme.palette.accent)
                                .padding(.horizontal, 6)
                                .frame(height: 17)
                                .background(Capsule().fill(BasicsTokens.Semantic.brandSoft))
                        }
                    }
                    .foregroundStyle(
                        item.id == self.selection ? self.theme.palette.primaryText : self.theme.palette.secondaryText
                    )
                    .padding(.horizontal, 14)
                    .frame(maxWidth: self.fillsWidth ? CGFloat.infinity : nil)
                    .frame(height: 30)
                    .background(self.background(isSelected: item.id == self.selection))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(self.isDisabled || !item.isEnabled)
                .opacity(item.isEnabled ? 1 : 0.45)
                .accessibilityAddTraits(item.id == self.selection ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(maxWidth: self.fillsWidth ? CGFloat.infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.sidebarBackground)
        )
        .fixedSize(horizontal: !self.fillsWidth, vertical: true)
        .opacity(self.isDisabled ? 0.55 : 1)
    }

    @ViewBuilder
    private func background(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        } else {
            Color.clear
        }
    }
}

/// The 44×26 Basics switch: brand when on, borderStrong when off, white 20pt knob.
private struct BasicsSwitch: View {
    @Binding var isOn: Bool
    let label: String

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.16)) {
                self.isOn.toggle()
            }
        } label: {
            ZStack(alignment: self.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(self.isOn ? self.theme.palette.accent : BasicsTokens.Surface.borderStrong)

                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                    .padding(3)
            }
            .frame(width: 44, height: 26)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// A 26pt row action — quiet at rest, outlined on hover.
private struct BasicsRowIconButton: View {
    let systemName: String
    var isDestructive: Bool = false
    let help: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(self.isHovered ? self.theme.palette.cardBackground : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .strokeBorder(self.isHovered ? self.theme.palette.cardBorder : .clear, lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .help(self.help)
    }

    private var foreground: Color {
        if self.isDestructive {
            return self.isHovered ? BasicsTokens.Semantic.danger : self.theme.palette.tertiaryText
        }
        return self.isHovered ? self.theme.palette.primaryText : self.theme.palette.tertiaryText
    }
}

private struct BasicsPanelHeader<Accessory: View>: View {
    let title: String
    let detail: String
    let onClose: () -> Void
    let accessory: Accessory

    @Environment(\.theme) private var theme

    init(
        title: String,
        detail: String,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.onClose = onClose
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(self.title)
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)

                    self.accessory
                }

                Text(self.detail)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: self.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(BasicsSquareIconButtonStyle())
            .help("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(self.theme.palette.cardBorder)
                .frame(height: 1)
        }
    }
}

private extension BasicsPanelHeader where Accessory == EmptyView {
    init(title: String, detail: String, onClose: @escaping () -> Void) {
        self.init(title: title, detail: detail, onClose: onClose) { EmptyView() }
    }
}

private struct BasicsSectionHead: View {
    let label: String
    let detail: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.label)
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text(self.detail)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BasicsTableHeader: View {
    let leading: String
    let leadingWidth: CGFloat?
    let trailing: String
    let trailingWidth: CGFloat?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            Text(self.leading)
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: self.leadingWidth, alignment: .leading)
                .frame(maxWidth: self.leadingWidth == nil ? CGFloat.infinity : nil, alignment: .leading)

            Text(self.trailing)
                .basicsMicroLabel()
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: self.trailingWidth, alignment: .leading)
                .frame(maxWidth: self.trailingWidth == nil ? CGFloat.infinity : nil, alignment: .leading)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
    }
}

private struct BasicsTableRow<Trailing: View>: View {
    let leading: String
    let leadingWidth: CGFloat
    @ViewBuilder let trailing: Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            Text(self.leading)
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: self.leadingWidth, alignment: .leading)

            self.trailing
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(self.theme.palette.cardBorder)
                .frame(height: 1)
        }
    }
}

private struct BasicsSettingRow<Control: View, Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control
    @ViewBuilder let trailing: Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(self.detail)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                self.control
            }
            .frame(width: 120, alignment: .trailing)

            HStack {
                Spacer(minLength: 0)
                self.trailing
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(self.theme.palette.cardBorder)
                .frame(height: 1)
        }
    }
}

private struct BasicsEmptyState: View {
    let title: String
    let detail: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 5) {
            Text(self.title)
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.detail)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 38)
        .padding(.bottom, 40)
    }
}

private struct BasicsNote: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text(self.text)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(self.theme.palette.sidebarBackground)
        )
    }
}

private struct BasicsWarningBanner: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BasicsTokens.Semantic.warning)

            Text(self.text)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(BasicsTokens.Semantic.warning.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .strokeBorder(BasicsTokens.Semantic.warning.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct BasicsInlineWarning: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BasicsTokens.Semantic.warning)

            Text(self.text)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BasicsChip: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        Text(self.text)
            .basicsLabel(11)
            .foregroundStyle(self.theme.palette.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(Capsule().fill(self.theme.palette.sidebarBackground))
    }
}

private struct BasicsSymbolChip: View {
    let symbol: String

    @Environment(\.theme) private var theme

    var body: some View {
        Text(self.symbol)
            .basicsMono(13)
            .foregroundStyle(self.theme.palette.primaryText)
            .lineLimit(1)
            .frame(width: 28, height: 24)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .strokeBorder(self.theme.palette.cardBorder, lineWidth: 1)
                    )
            )
    }
}

private struct BasicsEditorFooter: View {
    let onClear: () -> Void
    let onCancel: () -> Void
    let saveTitle: String
    let canSave: Bool
    let onSave: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button("Clear", action: self.onClear)
                .buttonStyle(BasicsPillButtonStyle(tone: .quiet, height: 30))

            Spacer(minLength: 0)

            Button("Cancel", action: self.onCancel)
                .buttonStyle(BasicsPillButtonStyle(tone: .outline, height: 30))

            Button(self.saveTitle, action: self.onSave)
                .buttonStyle(BasicsPillButtonStyle(tone: .primary, height: 30, isEnabled: self.canSave))
                .disabled(!self.canSave)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(self.theme.palette.cardBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Input chrome

private struct DictionaryInputChrome: ViewModifier {
    let minHeight: CGFloat
    let isInvalid: Bool

    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused(self.$isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: self.minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(self.border, lineWidth: 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.ring, lineWidth: 3)
                    .padding(-2)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var border: Color {
        if self.isInvalid { return BasicsTokens.Semantic.warning }
        return self.isFocused ? self.theme.palette.accent : BasicsTokens.Surface.borderStrong
    }

    private var ring: Color {
        if self.isInvalid { return BasicsTokens.Semantic.warning.opacity(0.16) }
        return self.isFocused ? BasicsTokens.Semantic.brandSoft : .clear
    }
}

private extension View {
    func dictionaryInputChrome(minHeight: CGFloat = 34, isInvalid: Bool = false) -> some View {
        self.modifier(DictionaryInputChrome(minHeight: minHeight, isInvalid: isInvalid))
    }

    func dismissTextFocusOnBackgroundTap() -> some View {
        self.background(DictionaryFocusDismissMonitor())
    }
}

private struct DictionaryFocusDismissMonitor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        FocusDismissView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class FocusDismissView: NSView {
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.removeEventMonitor()
            guard self.window != nil else { return }

            self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let contentView = self.window?.contentView
                let location = contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
                let hitView = contentView?.hitTest(location)
                if !self.isTextInput(hitView) {
                    self.window?.makeFirstResponder(nil)
                }
                return event
            }
        }

        deinit {
            self.removeEventMonitor()
        }

        private func isTextInput(_ view: NSView?) -> Bool {
            var candidate = view
            while let current = candidate {
                if current is NSTextField || current is NSTextView {
                    return true
                }
                candidate = current.superview
            }
            return false
        }

        private func removeEventMonitor() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

// MARK: - Shared dictionary logic

enum CustomDictionaryManualEntry {
    static func normalizedTrigger(_ text: String) -> String? {
        let trigger = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trigger.isEmpty ? nil : trigger
    }

    static func normalizedTriggers(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var triggers: [String] = []
        triggers.reserveCapacity(values.count)

        for value in values {
            guard let trigger = self.normalizedTrigger(value), !seen.contains(trigger) else { continue }
            seen.insert(trigger)
            triggers.append(trigger)
        }

        return triggers
    }

    static func normalizedDraftTriggers(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.allSatisfy({ $0 == "," || $0.isWhitespace }) {
            return self.normalizedTriggers([trimmed])
        }

        return self.normalizedTriggers(trimmed.split(separator: ",").map(String.init))
    }
}

enum PronunciationProfileEditPolicy {
    static func shouldDiscardProfile(previousReplacement: String, updatedReplacement: String) -> Bool {
        previousReplacement.caseInsensitiveCompare(updatedReplacement) != .orderedSame
    }
}

enum CustomDictionaryTrainingMerge {
    static let recommendedSamples = 5
    static let maxSamples = 20
    static let readyCoveredCount = 3

    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:\"'“”‘’")

    static func normalizedReplacement(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTrigger(_ value: String) -> String? {
        let edgeCharacters = CharacterSet.whitespacesAndNewlines.union(self.edgePunctuation)
        let trimmed = value.trimmingCharacters(in: edgeCharacters).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedTriggers(from values: [String], intendedReplacement: String) -> [String] {
        let replacement = self.normalizedReplacement(intendedReplacement)
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(values.count)

        for value in values {
            guard let trigger = self.normalizedTrigger(value),
                  trigger.caseInsensitiveCompare(replacement) != .orderedSame,
                  !seen.contains(trigger)
            else {
                continue
            }
            seen.insert(trigger)
            result.append(trigger)
            if result.count >= self.maxSamples {
                break
            }
        }

        return result
    }

    static func mergedEntries(
        current entries: [SettingsStore.CustomDictionaryEntry],
        replacement: String,
        triggers: [String]
    ) -> [SettingsStore.CustomDictionaryEntry] {
        let replacementText = self.normalizedReplacement(replacement)
        let incomingTriggers = self.normalizedTriggers(from: triggers, intendedReplacement: replacementText)
        guard !replacementText.isEmpty, !incomingTriggers.isEmpty else { return entries }

        let matchingIndex = entries.firstIndex {
            $0.replacement.caseInsensitiveCompare(replacementText) == .orderedSame
        }
        let replacementID = matchingIndex.map { entries[$0].id }
        let storedReplacementText = matchingIndex.map { entries[$0].replacement } ?? replacementText
        let matchingEntries = entries.filter {
            $0.replacement.caseInsensitiveCompare(storedReplacementText) == .orderedSame
        }
        let existingTriggers = matchingEntries.flatMap(\.triggers)
        let combinedTriggers = self.normalizedTriggers(
            from: existingTriggers + incomingTriggers,
            intendedReplacement: storedReplacementText
        )
        let triggerKeys = Set(combinedTriggers)

        let mergedEntry = replacementID.map {
            SettingsStore.CustomDictionaryEntry(
                id: $0,
                triggers: combinedTriggers,
                replacement: storedReplacementText
            )
        } ?? SettingsStore.CustomDictionaryEntry(
            triggers: combinedTriggers,
            replacement: storedReplacementText
        )

        var didInsertMergedEntry = false
        var updatedEntries: [SettingsStore.CustomDictionaryEntry] = []
        updatedEntries.reserveCapacity(entries.count + (matchingIndex == nil ? 1 : 0))

        for entry in entries {
            if entry.replacement.caseInsensitiveCompare(storedReplacementText) == .orderedSame {
                if !didInsertMergedEntry {
                    updatedEntries.append(mergedEntry)
                    didInsertMergedEntry = true
                }
                continue
            }

            let remainingTriggers = entry.triggers.filter { trigger in
                guard let key = self.normalizedTrigger(trigger) else { return false }
                return !triggerKeys.contains(key)
            }
            guard !remainingTriggers.isEmpty else { continue }
            updatedEntries.append(
                SettingsStore.CustomDictionaryEntry(
                    id: entry.id,
                    triggers: remainingTriggers,
                    replacement: entry.replacement
                )
            )
        }

        if !didInsertMergedEntry {
            updatedEntries.insert(mergedEntry, at: 0)
        }

        return updatedEntries
    }
}

// MARK: - Confirmation toast

private struct ReplacementConfirmation: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct ReplacementConfirmationToast: View {
    let confirmation: ReplacementConfirmation

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(BasicsTokens.Semantic.brandSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.confirmation.title)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(self.confirmation.detail)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.theme.palette.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Readiness ring

private struct DictionaryTrainingReadinessRing: View {
    let progress: Int
    let total: Int
    let isReady: Bool

    @Environment(\.theme) private var theme

    private var fraction: Double {
        guard self.total > 0 else { return 0 }
        return min(max(Double(self.progress) / Double(self.total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(BasicsTokens.Surface.borderStrong, lineWidth: 5)

            Circle()
                .trim(from: 0, to: self.fraction)
                .stroke(
                    self.theme.palette.accent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(self.progress)/\(self.total)")
                    .basicsLabel(19)
                    .foregroundStyle(self.isReady ? self.theme.palette.accent : self.theme.palette.primaryText)
                    .monospacedDigit()

                Text("Ready")
                    .basicsMicroLabel(10)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            }
        }
        .frame(width: 76, height: 76)
        .animation(.easeOut(duration: 0.24), value: self.progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training progress")
        .accessibilityValue("\(self.progress) of \(self.total) correct")
    }
}

private struct TrainingVariantChip: View {
    let variant: String
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Text(self.variant)
                .basicsLabel(12)
                .foregroundStyle(self.theme.palette.accent)
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: self.onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(self.theme.palette.accent)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(self.variant)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 24)
        .frame(maxWidth: 180)
        .background(Capsule().fill(BasicsTokens.Semantic.brandSoft))
    }
}

private struct DictionaryTriggerChip: View {
    let text: String
    var isDuplicate: Bool = false

    @Environment(\.theme) private var theme

    var body: some View {
        Text(self.text)
            .basicsLabel(11)
            .foregroundStyle(self.isDuplicate ? self.theme.palette.primaryText : self.theme.palette.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(
                Capsule()
                    .fill(self.isDuplicate ? BasicsTokens.Semantic.warning.opacity(0.16) : self.theme.palette.cardBackground)
                    .overlay(
                        Capsule().strokeBorder(
                            self.isDuplicate ? BasicsTokens.Semantic.warning.opacity(0.42) : self.theme.palette.cardBorder,
                            lineWidth: 1
                        )
                    )
            )
    }
}

private enum BoostStrengthPreset: String, CaseIterable, Identifiable {
    case mild = "Mild"
    case balanced = "Balanced"
    case strong = "Strong"

    var id: String { self.rawValue }

    var weight: Float {
        switch self {
        case .mild: return 5.0
        case .balanced: return 10.0
        case .strong: return 13.0
        }
    }

    var hint: String {
        switch self {
        case .mild: return "Very light nudge with minimal impact."
        case .balanced: return "Best default for most names and product terms."
        case .strong: return "Use when this word should win more often in noisy audio."
        }
    }

    static func nearest(for weight: Float) -> Self {
        if weight < 8.5 { return .mild }
        if weight > 11.5 { return .strong }
        return .balanced
    }
}

// MARK: - Popover rows

private struct BasicsPopoverRow<Content: View>: View {
    let content: Content
    let editHelp: String
    let editSymbol: String
    let deleteHelp: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    init(
        editSymbol: String = "slider.horizontal.3",
        editHelp: String,
        deleteHelp: String,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.editSymbol = editSymbol
        self.editHelp = editHelp
        self.deleteHelp = deleteHelp
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            self.content
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                BasicsRowIconButton(systemName: self.editSymbol, help: self.editHelp, action: self.onEdit)
                BasicsRowIconButton(systemName: "trash", isDestructive: true, help: self.deleteHelp, action: self.onDelete)
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.isHovered ? self.theme.palette.sidebarBackground : Color.clear)
        )
        .onHover { self.isHovered = $0 }
    }
}

struct BoostTermRow: View {
    let term: ParakeetVocabularyStore.VocabularyConfig.Term
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        BasicsPopoverRow(
            editHelp: "Configure \(self.term.text)",
            deleteHelp: "Delete \(self.term.text)",
            onEdit: self.onEdit,
            onDelete: self.onDelete
        ) {
            HStack(spacing: 10) {
                Text(self.term.text)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let weight = self.term.weight {
                    BasicsChip(text: BoostStrengthPreset.nearest(for: weight).rawValue)
                }
            }
        }
    }
}

struct DictionaryEntryRow: View {
    let entry: SettingsStore.CustomDictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        BasicsPopoverRow(
            editHelp: "Configure replacement",
            deleteHelp: "Delete replacement",
            onEdit: self.onEdit,
            onDelete: self.onDelete
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.entry.triggers.joined(separator: ", "))
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    Text(self.entry.replacement)
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct PunctuationDictionaryRuleRow: View {
    let rule: SettingsStore.PunctuationDictionaryRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        BasicsPopoverRow(
            editSymbol: "pencil",
            editHelp: "Edit punctuation rule",
            deleteHelp: "Delete punctuation rule",
            onEdit: self.onEdit,
            onDelete: self.onDelete
        ) {
            HStack(spacing: 10) {
                Text(self.rule.symbol)
                    .basicsMono(13)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .fill(self.theme.palette.sidebarBackground)
                    )

                Text(self.rule.aliases.joined(separator: ", "))
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Edit entry sheet

struct EditDictionaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let entry: SettingsStore.CustomDictionaryEntry
    let existingTriggers: Set<String>
    let onSave: (SettingsStore.CustomDictionaryEntry) -> Void

    @State private var triggersText = ""
    @State private var replacement = ""

    private var parsedTriggers: [String] {
        CustomDictionaryManualEntry.normalizedTriggers(
            self.triggersText.components(separatedBy: .newlines)
        )
    }

    private var duplicateTriggers: [String] {
        self.parsedTriggers.filter { self.existingTriggers.contains($0) }
    }

    private var trimmedReplacement: String {
        self.replacement.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !self.parsedTriggers.isEmpty &&
            !self.trimmedReplacement.isEmpty &&
            self.duplicateTriggers.isEmpty
    }

    private var showsPreview: Bool {
        !self.parsedTriggers.isEmpty && !self.trimmedReplacement.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Edit dictionary entry")
                    .basicsLabel(16)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Cancel") { self.dismiss() }
                    .buttonStyle(BasicsPillButtonStyle(tone: .quiet, height: 28))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 22)
            .padding(.trailing, 18)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { self.hairline }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    BasicsSectionHead(
                        label: "Misheard words",
                        detail: "Add one version per line. Commas can be saved too."
                    )

                    TextEditor(text: self.$triggersText)
                        .basicsProse(14)
                        .frame(height: 86)
                        .scrollContentBackground(.hidden)
                        .dictionaryInputChrome(minHeight: 86, isInvalid: !self.duplicateTriggers.isEmpty)

                    if !self.duplicateTriggers.isEmpty {
                        BasicsInlineWarning(text: "Duplicate triggers: \(self.duplicateTriggers.joined(separator: ", "))")
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    BasicsSectionHead(
                        label: "Correct spelling",
                        detail: "This is what will appear in the final transcription."
                    )

                    TextField("FluidVoice", text: self.$replacement)
                        .basicsProse(14)
                        .dictionaryInputChrome()
                        .onSubmit { self.saveIfValid() }
                }

                if self.showsPreview {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .basicsMicroLabel()
                            .foregroundStyle(self.theme.palette.tertiaryText)

                        FlowLayout(spacing: 8) {
                            ForEach(self.parsedTriggers, id: \.self) { trigger in
                                DictionaryTriggerChip(
                                    text: trigger,
                                    isDuplicate: self.duplicateTriggers.contains(trigger)
                                )
                            }

                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(self.theme.palette.tertiaryText)

                            Text(self.trimmedReplacement)
                                .basicsLabel(15)
                                .foregroundStyle(self.theme.palette.primaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                            .fill(self.theme.palette.sidebarBackground)
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)

            HStack(spacing: 12) {
                if self.duplicateTriggers.isEmpty {
                    Text("\(self.parsedTriggers.count) \(self.parsedTriggers.count == 1 ? "trigger" : "triggers")")
                        .basicsProse(12)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    BasicsInlineWarning(
                        text: self.duplicateTriggers.count == 1
                            ? "1 trigger is already used by another entry"
                            : "\(self.duplicateTriggers.count) triggers are already used by another entry"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Save changes") { self.saveIfValid() }
                    .buttonStyle(BasicsPillButtonStyle(tone: .primary, height: 32, isEnabled: self.canSave))
                    .disabled(!self.canSave)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(self.theme.palette.windowBackground)
            .overlay(alignment: .top) { self.hairline }
        }
        .frame(width: 480)
        .background(self.theme.palette.cardBackground)
        .dismissTextFocusOnBackgroundTap()
        .onAppear {
            self.triggersText = self.entry.triggers.joined(separator: "\n")
            self.replacement = self.entry.replacement
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(self.theme.palette.cardBorder)
            .frame(height: 1)
    }

    private func saveIfValid() {
        guard self.canSave else { return }

        let updatedEntry = SettingsStore.CustomDictionaryEntry(
            id: self.entry.id,
            triggers: self.parsedTriggers,
            replacement: self.trimmedReplacement
        )
        self.onSave(updatedEntry)
        self.dismiss()
    }
}
