//
//  AISettingsView+AdvancedSettings.swift
//  fluid
//
//  Boards "04c — prompts" (+ · editor sheet & dialogs) and
//  "04d — routing & overrides" (+ · states, menus, popovers).
//

import AppKit
import SwiftUI

private struct PromptCardAssignments {
    let isDefault: Bool
    let shortcutDisplay: String?
    let modelPicker: PromptCardModelPicker?
    let onMakeDefault: () -> Void
}

private struct PromptCardModelPicker {
    let summary: String
    let selectedModel: String
    let models: [String]
    let providerName: String
    let onSelectModel: (String) -> Void
    let onOpenProviders: () -> Void
}

extension AIEnhancementSettingsView {
    // MARK: - Advanced prompts tab

    var advancedSettingsCard: some View {
        self.promptModeSection(mode: .dictate)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .sheet(item: self.$viewModel.promptEditorMode) { mode in
                self.promptEditorSheet(mode: mode)
            }
    }

    /// Board 04c · popover — "Prompt profiles".
    var promptProfilesHelpPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt profiles")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("Choose the prompt behavior for dictation.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                self.promptProfilesHelpRow("Built-in is the normal prompt. Assign any prompt as Primary to use it with your main hotkey.")
                self.promptProfilesHelpRow("\(PrivateAIProviderFeature.displayName) uses its own local prompt.")
                self.promptProfilesHelpRow("Custom prompts can be assigned globally, by app, or by shortcut.")
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(self.theme.palette.cardBackground)
    }

    private func promptProfilesHelpRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(self.theme.palette.accent)
                .frame(width: 4, height: 4)
                .padding(.top, 7)

            Text(text)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func promptModeSection(mode: SettingsStore.PromptMode) -> some View {
        let customProfiles = self.viewModel.dictationPromptProfiles
            .filter { $0.mode.normalized == mode }
        let isPrivateAI = mode.normalized == .dictate && self.viewModel.isPrivateAIModelSelected()
        let isSelectedAppsOnly = !isPrivateAI && self.viewModel.promptRoutingScope(for: mode) == .selectedAppsOnly

        VStack(alignment: .leading, spacing: 24) {
            if isPrivateAI {
                self.privateAIPromptSection(mode: mode)
            } else {
                self.promptRoutingScopeSection(mode: mode)

                self.promptProfilesSection(
                    mode: mode,
                    customProfiles: customProfiles,
                    isSelectedAppsOnly: isSelectedAppsOnly
                )

                if mode.normalized == .dictate {
                    self.customPromptOnlyToggleRow
                }
            }

            self.appPromptBindingsSection(mode: mode, isEnabled: !isPrivateAI)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Prompt profiles

    @ViewBuilder
    private func promptProfilesSection(
        mode: SettingsStore.PromptMode,
        customProfiles: [SettingsStore.DictationPromptProfile],
        isSelectedAppsOnly: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "Prompt profiles", count: customProfiles.count + 1) {
                Button {
                    self.viewModel.openNewPromptEditor(prefillMode: .dictate)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add prompt")
                    }
                }
                .fluidButton(.accent, size: .small)
            }

            VStack(spacing: 8) {
                let defaultSelection = SettingsStore.DictationPromptSelection.default
                self.promptProfileCard(
                    cardKey: "\(mode.normalized.rawValue)-default",
                    title: mode.normalized == .dictate ? "Built-in Default" : "Default \(self.friendlyModeName(mode))",
                    mode: mode,
                    isSelected: self.viewModel.selectedPromptID(for: mode) == nil,
                    assignments: mode.normalized == .dictate
                        ? self.promptAssignments(selection: defaultSelection)
                        : nil,
                    onManage: { self.viewModel.openDefaultPromptViewer(for: mode) },
                    isEnabled: !isSelectedAppsOnly
                )

                ForEach(customProfiles) { profile in
                    let profileSelection = SettingsStore.DictationPromptSelection.profile(profile.id)
                    self.promptProfileCard(
                        cardKey: "\(profile.mode.normalized.rawValue)-\(profile.id)",
                        title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                        isUntitled: profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        mode: profile.mode,
                        isSelected: self.viewModel.selectedPromptID(for: profile.mode) == profile.id,
                        assignments: profile.mode.normalized == .dictate
                            ? self.promptAssignments(selection: profileSelection)
                            : nil,
                        onManage: { self.viewModel.openEditor(for: profile) },
                        onDelete: { self.viewModel.requestDeletePrompt(profile) },
                        isEnabled: !isSelectedAppsOnly
                    )
                }
            }
            .opacity(isSelectedAppsOnly ? 0.5 : 1)
        }
    }

    /// Board 04d · states — "local model selected". One locked card, no Add prompt.
    @ViewBuilder
    private func privateAIPromptSection(mode: SettingsStore.PromptMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "Prompt profiles", count: 1)

            self.promptProfileCard(
                cardKey: "\(mode.normalized.rawValue)-\(PrivateAIProviderFeature.shared.providerID)",
                title: PrivateAIProviderFeature.displayName,
                mode: mode,
                isSelected: true,
                assignments: self.promptAssignments(
                    selection: SettingsStore.DictationPromptSelection.privateAI,
                    isPrivateAI: true
                ),
                isLocked: true,
                onManage: { self.viewModel.openPrivateAIPromptEditor() },
                isEnabled: true
            )

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.theme.palette.tertiaryText)
                Text("\(PrivateAIProviderFeature.displayName) uses its own built-in system prompt. Switch to another provider to create custom prompts.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// Board 04c — a 74pt card: title + status chip on line one, the three
    /// configuration chips on line two, actions revealed on hover.
    private func promptProfileCard(
        cardKey: String,
        title: String,
        isUntitled: Bool = false,
        mode: SettingsStore.PromptMode,
        isSelected: Bool,
        assignments: PromptCardAssignments? = nil,
        isLocked: Bool = false,
        onManage: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        isEnabled: Bool = true
    ) -> some View {
        let isHovering = self.hoveredPromptCardKey == cardKey
        let isDefaultRow = assignments?.isDefault == true
        let isSelectedRow = isDefaultRow || (assignments == nil && isSelected)
        let showsActions = isHovering || isSelectedRow
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
        // A locked card is not a choice, so it never takes the brand outline.
        let isBrandOutlined = isSelectedRow && !isLocked
        let border: Color = isBrandOutlined
            ? self.theme.palette.accent
            : (isHovering
                ? BasicsBorder.strong(self.theme, self.colorScheme)
                : self.theme.palette.cardBorder)

        return HStack(alignment: .center, spacing: 16) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.theme.palette.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .basicsLabel(15)
                        .foregroundStyle(isUntitled
                            ? self.theme.palette.tertiaryText
                            : self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isSelectedRow {
                        AIChip(
                            text: isLocked ? "Locked" : "Selected",
                            tone: isLocked ? .neutral : .brand,
                            isUppercase: true
                        )
                    }

                    if mode.normalized == .edit {
                        AIChip(text: "Context: Auto", tone: .soft)
                    }
                }

                if let assignments {
                    self.promptCardMetadataChips(assignments: assignments)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let onManage {
                    Button {
                        onManage()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(SquareIconButtonStyle())
                    .disabled(!isEnabled)
                    .help("Configure")
                    .opacity(showsActions ? 1 : 0)
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(SquareIconButtonStyle(
                        foreground: BasicsTokens.Semantic.danger,
                        borderColor: BasicsTokens.Semantic.danger.opacity(0.4)
                    ))
                    .disabled(!isEnabled)
                    .help("Delete")
                    .opacity(showsActions ? 1 : 0)
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 19)
        .padding(.trailing, 15)
        .frame(minHeight: AISettingsLayout.promptCardHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.68)
        .background(shape.fill(self.theme.palette.cardBackground))
        .overlay(shape.stroke(border, lineWidth: isBrandOutlined ? 2 : 1))
        .clipShape(shape)
        .onHover { hovering in
            if hovering {
                self.hoveredPromptCardKey = cardKey
            } else if self.hoveredPromptCardKey == cardKey {
                self.hoveredPromptCardKey = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func promptCardMetadataChips(assignments: PromptCardAssignments) -> some View {
        HStack(spacing: 7) {
            if let modelPicker = assignments.modelPicker {
                AIChip(
                    text: modelPicker.providerName.isEmpty ? "Choose provider first" : modelPicker.providerName,
                    systemImage: "server.rack",
                    tone: modelPicker.providerName.isEmpty ? .ghost : .neutral
                )

                AIChip(
                    text: modelPicker.selectedModel.isEmpty ? "No model" : modelPicker.selectedModel,
                    systemImage: "cpu",
                    tone: modelPicker.selectedModel.isEmpty ? .ghost : .neutral,
                    isMono: !modelPicker.selectedModel.isEmpty
                )
            }

            if let shortcutDisplay = assignments.shortcutDisplay {
                AIChip(text: shortcutDisplay, systemImage: "keyboard", tone: .soft, isMono: true)
            } else {
                AIChip(text: "No shortcut", systemImage: "keyboard", tone: .ghost)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Routing scope (board 04d)

    private func promptRoutingScopeSection(mode: SettingsStore.PromptMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "Where custom prompts apply")

            HStack(spacing: 10) {
                self.promptRoutingScopeCard(
                    title: "All apps",
                    helper: "Custom prompts run based on your shortcut or the app you're in.",
                    scope: .allApps,
                    mode: mode
                )
                self.promptRoutingScopeCard(
                    title: "Selected apps only",
                    helper: "Custom prompts only run in apps listed in App overrides.",
                    scope: .selectedAppsOnly,
                    mode: mode
                )
            }
        }
    }

    private func promptRoutingScopeCard(
        title: String,
        helper: String,
        scope: SettingsStore.PromptRoutingScope,
        mode: SettingsStore.PromptMode
    ) -> some View {
        let key = "\(mode.normalized.rawValue)-\(scope.rawValue)"
        let isSelected = self.viewModel.promptRoutingScope(for: mode) == scope
        let isHovering = self.hoveredPromptScopeKey == key
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
        let border: Color = isSelected
            ? self.theme.palette.accent
            : (isHovering
                ? BasicsBorder.strong(self.theme, self.colorScheme)
                : self.theme.palette.cardBorder)

        return Button {
            self.viewModel.setPromptRoutingScope(scope, for: mode)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected
                                ? self.theme.palette.accent
                                : BasicsBorder.strong(self.theme, self.colorScheme),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)

                    if isSelected {
                        Circle()
                            .fill(self.theme.palette.accent)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text(helper)
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .background(shape.fill(self.theme.palette.cardBackground))
            .overlay(shape.stroke(border, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            self.hoveredPromptScopeKey = hovering ? key : nil
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    // MARK: - App overrides (board 04d)

    @ViewBuilder
    private func appPromptBindingsSection(mode: SettingsStore.PromptMode, isEnabled: Bool = true) -> some View {
        let bindings = self.viewModel.appBindings(for: mode)
        let appTargets = self.viewModel.appBindingTargets(for: mode)
        let modeProfiles = self.viewModel.dictationPromptProfiles
            .filter { $0.mode.normalized == mode.normalized }

        VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "App overrides", count: bindings.count) {
                Menu {
                    if appTargets.isEmpty {
                        Text("No unassigned running apps")
                    } else {
                        ForEach(appTargets) { target in
                            Button(self.appBindingTargetMenuTitle(target)) {
                                self.viewModel.addAppPromptBinding(
                                    for: mode,
                                    appBundleID: target.bundleID,
                                    appName: target.name
                                )
                            }
                        }
                    }

                    Divider()

                    Button("Choose app…") {
                        self.viewModel.addAppPromptBindingFromFilePicker(for: mode)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add app")
                    }
                }
                .fluidCompactButton(size: .small)
                .fixedSize()
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.48)
            }

            if bindings.isEmpty {
                AIEmptyWell {
                    Text("No app overrides yet. Add one to use a different prompt for a specific app.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            } else {
                AIListCard {
                    ForEach(Array(bindings.enumerated()), id: \.element.id) { index, binding in
                        if index > 0 {
                            AIHairline()
                        }
                        self.appPromptBindingRow(
                            binding: binding,
                            mode: mode,
                            modeProfiles: modeProfiles,
                            isEnabled: isEnabled
                        )
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private func appPromptBindingRow(
        binding: SettingsStore.AppPromptBinding,
        mode: SettingsStore.PromptMode,
        modeProfiles: [SettingsStore.DictationPromptProfile],
        isEnabled: Bool = true
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            self.appIconView(bundleID: binding.appBundleID)

            VStack(alignment: .leading, spacing: 2) {
                Text(binding.appName)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                Text(binding.appBundleID)
                    .basicsMono(11)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Default") {
                    self.viewModel.setPromptID(nil, for: binding)
                }

                if !modeProfiles.isEmpty {
                    Divider()
                    ForEach(modeProfiles) { profile in
                        Button(profile.name.isEmpty ? "Untitled Prompt" : profile.name) {
                            self.viewModel.setPromptID(profile.id, for: binding)
                        }
                    }
                }

                Divider()

                Button("Create new prompt…") {
                    self.viewModel.openNewPromptEditor(prefillMode: mode)
                }
            } label: {
                HStack(spacing: 10) {
                    Text(self.viewModel.promptName(for: mode, promptID: binding.promptID))
                        .basicsProse(13)
                        .foregroundStyle(binding.promptID == nil
                            ? self.theme.palette.secondaryText
                            : self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    FluidPickerDisclosureIcon(backgroundOpacity: 0.6)
                }
                .searchablePickerControlChrome(
                    width: 240,
                    height: AISettingsLayout.controlHeight,
                    usesMaterial: false,
                    showsShadow: false
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!isEnabled)

            Button {
                guard isEnabled else { return }
                self.viewModel.removeAppPromptBinding(binding)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SquareIconButtonStyle(
                foreground: BasicsTokens.Semantic.danger,
                borderColor: BasicsTokens.Semantic.danger.opacity(0.4)
            ))
            .disabled(!isEnabled)
            .help("Remove app-specific override")
        }
        .padding(.horizontal, AISettingsLayout.cardGutter)
        .frame(height: AISettingsLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func appIconView(bundleID: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .frame(width: 28, height: 28)
                .background(shape.fill(self.theme.palette.sidebarBackground))
                .clipShape(shape)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: 28, height: 28)
                .background(
                    shape.strokeBorder(
                        BasicsBorder.strong(self.theme, self.colorScheme),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                )
        }
    }

    // MARK: - Prompt configuration drafts

    private func promptAssignments(
        selection: SettingsStore.DictationPromptSelection,
        isPrivateAI: Bool = false
    ) -> PromptCardAssignments {
        let configuration = self.settings.dictationPromptConfiguration(for: selection)
        return PromptCardAssignments(
            isDefault: self.viewModel.isDictationPromptSelection(selection, for: .primary),
            shortcutDisplay: configuration.shortcut?.displayString,
            modelPicker: self.promptModelPicker(selection: selection, isPrivateAI: isPrivateAI),
            onMakeDefault: {
                self.viewModel.setDictationPromptSelection(selection, for: .primary)
            }
        )
    }

    private func promptEditorSelection(for mode: PromptEditorMode) -> SettingsStore.DictationPromptSelection? {
        switch mode {
        case let .defaultPrompt(promptMode):
            guard promptMode.normalized == .dictate else { return nil }
            return .default
        case let .edit(promptID):
            guard self.viewModel.draftPromptMode.normalized == .dictate else { return nil }
            return .profile(promptID)
        case .newPrompt:
            return nil
        case .privateAI:
            return .privateAI
        }
    }

    private func preparePromptEditorConfigurationDraft(mode: PromptEditorMode) {
        self.promptEditorPrimarySelectionDraft = self.viewModel.dictationPromptSelection(for: .primary)

        if case .newPrompt = mode {
            let pending = self.viewModel.pendingNewPromptConfiguration
            self.promptEditorOriginalConfiguration = nil
            self.promptEditorShortcutDraft = pending?.shortcut
            let providerID = pending?.providerID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.promptEditorProviderIDDraft = providerID.isEmpty
                ? self.viewModel.defaultVerifiedPromptProviderID()
                : providerID
            self.promptEditorModelDraft = pending?.modelName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if self.promptEditorModelDraft.isEmpty, !self.promptEditorProviderIDDraft.isEmpty {
                self.promptEditorModelDraft = self.viewModel.selectedModel(for: self.promptEditorProviderIDDraft)
            }
            return
        }

        let selection = self.promptEditorSelection(for: mode)
        let configuration = selection.map { self.settings.dictationPromptConfiguration(for: $0) }
        self.promptEditorOriginalConfiguration = configuration
        self.promptEditorShortcutDraft = configuration?.shortcut

        let providerID = configuration?.providerID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.promptEditorProviderIDDraft = providerID.isEmpty ? self.viewModel.defaultVerifiedPromptProviderID() : providerID
        self.promptEditorModelDraft = configuration?.modelName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if self.promptEditorModelDraft.isEmpty, !self.promptEditorProviderIDDraft.isEmpty {
            self.promptEditorModelDraft = self.viewModel.selectedModel(for: self.promptEditorProviderIDDraft)
        }

        if mode.isPrivateAI {
            self.promptEditorProviderIDDraft = PrivateAIProviderFeature.shared.providerID
            self.promptEditorModelDraft = PrivateAIIntegrationService.configuredModelID
        }

        if mode.isDefault, let promptMode = mode.mode {
            self.viewModel.draftPromptMode = promptMode.normalized
        }
    }

    private func applyPromptEditorConfigurationDraft(mode: PromptEditorMode) {
        if case .newPrompt = mode {
            let providerID = self.promptEditorProviderIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = self.promptEditorModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            self.viewModel.pendingNewPromptConfiguration = SettingsStore.DictationPromptConfiguration(
                shortcut: self.promptEditorShortcutDraft,
                providerID: providerID,
                modelName: modelName
            )
            return
        }

        if let selection = self.promptEditorSelection(for: mode) {
            if self.promptEditorPrimarySelectionDraft == selection {
                self.viewModel.setDictationPromptSelection(selection, for: .primary)
            }
            let providerID = self.promptEditorProviderIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = self.promptEditorModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let configuration = SettingsStore.DictationPromptConfiguration(
                shortcut: self.promptEditorShortcutDraft,
                providerID: providerID,
                modelName: modelName
            )
            self.settings.setDictationPromptConfiguration(configuration, for: selection)
            NotificationCenter.default.post(name: .dictationPromptShortcutsChanged, object: nil)
        }
    }

    private func restorePromptEditorConfigurationDraft(mode: PromptEditorMode) {
        guard let selection = self.promptEditorSelection(for: mode) else { return }
        if let original = self.promptEditorOriginalConfiguration {
            self.settings.setDictationPromptConfiguration(original, for: selection)
        } else {
            self.settings.removeDictationPromptConfiguration(for: selection)
        }
        NotificationCenter.default.post(name: .dictationPromptShortcutsChanged, object: nil)
    }

    private func syncDraftToPendingConfig() {
        guard self.viewModel.promptEditorMode?.isNewPrompt == true else { return }
        self.viewModel.pendingNewPromptConfiguration = SettingsStore.DictationPromptConfiguration(
            shortcut: self.promptEditorShortcutDraft,
            providerID: self.promptEditorProviderIDDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: self.promptEditorModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func shouldShowPromptEditorConfigurationPanel(for mode: PromptEditorMode) -> Bool {
        if case .newPrompt = mode {
            return self.viewModel.draftPromptMode.normalized == .dictate
        }
        if case .privateAI = mode {
            return true
        }
        return self.promptEditorSelection(for: mode) != nil
    }

    private func promptModelPicker(
        selection: SettingsStore.DictationPromptSelection,
        isPrivateAI: Bool
    ) -> PromptCardModelPicker? {
        if isPrivateAI {
            return PromptCardModelPicker(
                summary: PrivateAIIntegrationService.configuredModelID,
                selectedModel: PrivateAIIntegrationService.configuredModelID,
                models: PrivateAIModelRegistry.modelIDs(),
                providerName: PrivateAIProviderFeature.displayName,
                onSelectModel: { _ in
                    self.selectedConfigurationSection = .providers
                    self.expandedProviderID = PrivateAIProviderFeature.shared.providerID
                },
                onOpenProviders: {
                    self.selectedConfigurationSection = .providers
                    self.expandedProviderID = PrivateAIProviderFeature.shared.providerID
                }
            )
        }

        guard !self.viewModel.isPrivateAIModelSelected() else { return nil }
        let configuration = self.settings.dictationPromptConfiguration(for: selection)
        let configuredProviderID = configuration.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = configuredProviderID.isEmpty
            ? self.viewModel.selectedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
            : configuredProviderID
        guard !providerID.isEmpty else {
            return PromptCardModelPicker(
                summary: "Choose provider first",
                selectedModel: "",
                models: [],
                providerName: "",
                onSelectModel: { _ in },
                onOpenProviders: {
                    self.selectedConfigurationSection = .providers
                    self.expandedProviderID = nil
                }
            )
        }

        let providerName = self.viewModel.providerDisplayName(for: providerID)
        let configuredModel = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = configuredModel.isEmpty ? self.viewModel.selectedModel(for: providerID) : configuredModel
        let summary = selectedModel.isEmpty ? providerName : "\(providerName) - \(selectedModel)"

        return PromptCardModelPicker(
            summary: summary,
            selectedModel: selectedModel,
            models: self.viewModel.models(for: providerID),
            providerName: providerName,
            onSelectModel: { modelName in
                var updated = self.settings.dictationPromptConfiguration(for: selection)
                updated.providerID = providerID
                updated.modelName = modelName
                self.settings.setDictationPromptConfiguration(updated, for: selection)
            },
            onOpenProviders: {
                self.selectedConfigurationSection = .providers
                self.expandedProviderID = providerID
            }
        )
    }

    private func canFetchModels(for providerID: String) -> Bool {
        let apiKey = self.viewModel.providerAPIKey(for: providerID)
        let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let baseURL: String
        if let saved = self.viewModel.savedProviders.first(where: { $0.id == providerID }) {
            baseURL = saved.baseURL
        } else {
            baseURL = ModelRepository.shared.defaultBaseURL(for: providerID)
        }
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.viewModel.isLocalEndpoint(trimmedBaseURL)

        return isLocal ? !trimmedBaseURL.isEmpty : (hasAPIKey && !trimmedBaseURL.isEmpty)
    }

    private func appBindingTargetMenuTitle(_ target: AIEnhancementSettingsViewModel.AppBindingTarget) -> String {
        if target.name.caseInsensitiveCompare(target.bundleID) == .orderedSame {
            return target.bundleID
        }
        return "\(target.name) (\(target.bundleID))"
    }

    private func friendlyModeName(_ mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate:
            return "Dictate"
        case .edit, .write, .rewrite:
            return "Edit Text"
        }
    }

    // MARK: - Prompt editor sheet (board 04c · editor sheet & dialogs)

    func promptEditorSheet(mode: PromptEditorMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.promptEditorHeader(mode: mode)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if !mode.isPrivateAI {
                        self.promptEditorNameSection(mode: mode)
                        self.promptEditorBodySection

                        if self.viewModel.draftPromptMode == .dictate {
                            self.baseDictationPromptReference
                        }
                    }

                    if self.viewModel.draftPromptMode != .dictate {
                        self.promptEditorContextTemplate
                    }

                    if self.shouldShowPromptEditorConfigurationPanel(for: mode) {
                        AIHairline()
                        self.promptEditorConfigurationPanel(mode: mode)
                    }

                    if self.viewModel.draftPromptMode == .dictate, !mode.isPrivateAI {
                        AIHairline()
                        self.promptEditorTestSection
                    } else if self.promptTest.isActive {
                        AIInlineNotice(text: "Prompt test mode is available only for Dictate prompts.")
                            .padding(.vertical, 16)
                            .onAppear { self.promptTest.deactivate() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            AIHairline()

            self.promptEditorFooter(mode: mode)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .background(self.theme.palette.cardBackground)
        .onAppear {
            self.preparePromptEditorConfigurationDraft(mode: mode)
        }
        .onDisappear {
            self.promptTest.deactivate()
        }
        .onChange(of: self.viewModel.promptEditorSessionID) { _, _ in
            self.preparePromptEditorConfigurationDraft(mode: mode)
        }
        .onChange(of: self.activeShortcutRecordingTarget) { oldValue, newValue in
            if case .newPrompt = mode {
                if newValue == nil, oldValue != nil {
                    if let pending = self.viewModel.pendingNewPromptConfiguration {
                        self.promptEditorShortcutDraft = pending.shortcut
                    } else {
                        self.promptEditorShortcutDraft = nil
                    }
                }
                return
            }
            guard newValue == nil, oldValue != nil,
                  let selection = self.promptEditorSelection(for: mode)
            else {
                return
            }
            self.promptEditorShortcutDraft = self.settings.dictationPromptConfiguration(for: selection).shortcut
        }
        .onChange(of: self.viewModel.selectedProviderID) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.providerAPIKeys) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.savedProviders) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
    }

    private func promptEditorHeader(mode: PromptEditorMode) -> some View {
        let title: String = {
            switch mode {
            case let .defaultPrompt(promptMode): return "Default \(self.friendlyModeName(promptMode)) Prompt"
            case let .newPrompt(prefillMode): return "New \(self.friendlyModeName(prefillMode)) Prompt"
            case .edit: return "Edit prompt"
            case .privateAI: return PrivateAIProviderFeature.displayName
            }
        }()
        let subtitle: String? = {
            if mode.isPrivateAI {
                return "Built-in system prompt. Only the shortcut can be customized."
            }
            if mode.isDefault {
                return "This is the built-in prompt. Create a custom prompt to override it."
            }
            if case .edit = mode {
                return "Runs instead of the built-in dictation prompt whenever its shortcut or app override fires."
            }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .basicsLabel(19)
                    .foregroundStyle(self.theme.palette.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            AIHairline()
        }
    }

    private func promptEditorNameSection(mode: PromptEditorMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)

            TextField("Prompt name", text: self.$viewModel.draftPromptName)
                .textFieldStyle(.plain)
                .basicsProse(13)
                .modifier(AIFieldChrome(width: nil))
                .disabled(mode.isDefault)
                .opacity(mode.isDefault ? 0.6 : 1)
        }
        .padding(.top, 20)
    }

    private var promptEditorBodySection: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)

            PromptTextView(text: self.$viewModel.draftPromptText, isEditable: true)
                .id(self.viewModel.promptEditorSessionID)
                .frame(minHeight: 180)
                .background(shape.fill(self.theme.palette.cardBackground))
                .overlay(shape.stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1))
                .onChange(of: self.viewModel.draftPromptText) { _, newValue in
                    guard self.viewModel.draftPromptMode == .dictate else { return }
                    let combined = self.viewModel.combinedDraftPrompt(newValue, mode: self.viewModel.draftPromptMode)
                    self.promptTest.updateDraftPromptText(combined)
                }
        }
        .padding(.top, 18)
    }

    /// Board 04c · "built-in base prompt" — a disclosure, closed by default so the
    /// reference never competes with the prompt you are writing.
    private var baseDictationPromptReference: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    self.isBasePromptExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: self.isBasePromptExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.theme.palette.tertiaryText)
                    Text("Built-in base prompt")
                        .basicsLabel(13)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("Reference only. Copy any parts you want into a custom prompt.")
                        .basicsProse(12)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.isBasePromptExpanded {
                Text(SettingsStore.baseDictationPromptText())
                    .basicsMono(11)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(shape.fill(self.theme.palette.sidebarBackground))
                    .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
            }
        }
        .padding(.top, 16)
    }

    private var promptEditorContextTemplate: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Selected text is added automatically when text is selected.")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)

            Text("Context block added automatically:")
                .basicsProse(12)
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text(SettingsStore.contextTemplateText())
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(shape.fill(self.theme.palette.sidebarBackground))
                .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))

            HStack(spacing: 10) {
                AIChip(text: "Context: Auto", tone: .soft)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 18)
    }

    // MARK: - Prompt editor configuration rows

    private func promptEditorConfigurationPanel(mode: PromptEditorMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.promptEditorShortcutRow(mode: mode)

            AIHairline()

            Group {
                self.promptEditorProviderRow

                AIHairline()

                self.promptEditorModelRow
            }
            .disabled(mode.isPrivateAI)
            .opacity(mode.isPrivateAI ? 0.6 : 1)
        }
    }

    private func promptEditorShortcutRow(mode: PromptEditorMode) -> some View {
        let isNewPrompt: Bool = {
            if case .newPrompt = mode { return true }
            return false
        }()
        let selection = self.promptEditorSelection(for: mode)
        let configurationKey = selection.flatMap { self.settings.dictationPromptConfigurationKey(for: $0) }
        let isRecording: Bool = {
            if isNewPrompt {
                return self.activeShortcutRecordingTarget == .newPrompt
            }
            return configurationKey.map { self.activeShortcutRecordingTarget == .dictationPrompt($0) } ?? false
        }()
        let hasShortcut = self.promptEditorShortcutDraft != nil

        return AISettingRow(title: "Custom shortcut", helper: "Optional shortcut just for this prompt.") {
            HStack(spacing: 8) {
                if isRecording {
                    Text("Press shortcut…")
                        .basicsLabel(12)
                        .foregroundStyle(BasicsTokens.Semantic.warning)
                        .frame(width: 120, height: AISettingsLayout.controlHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .strokeBorder(
                                    BasicsTokens.Semantic.warning,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                )
                        )
                } else if let shortcut = self.promptEditorShortcutDraft {
                    Text(shortcut.displayString)
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .frame(width: 120, height: AISettingsLayout.controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .fill(self.theme.palette.sidebarBackground)
                        )
                } else {
                    Text("None")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .frame(width: 120, height: AISettingsLayout.controlHeight)
                }

                Button {
                    self.shortcutRecordingMessage = nil
                    if isNewPrompt {
                        self.activeShortcutRecordingTarget = .newPrompt
                    } else if let configurationKey {
                        self.activeShortcutRecordingTarget = .dictationPrompt(configurationKey)
                    }
                } label: {
                    Text(isRecording ? "Recording…" : "Change")
                }
                .fluidCompactButton(size: .small, isReady: !isRecording)
                .disabled(isRecording)

                if hasShortcut {
                    Button {
                        self.promptEditorShortcutDraft = nil
                        if isNewPrompt {
                            if self.activeShortcutRecordingTarget == .newPrompt {
                                self.activeShortcutRecordingTarget = nil
                            }
                        } else if let configurationKey,
                                  self.activeShortcutRecordingTarget == .dictationPrompt(configurationKey)
                        {
                            self.activeShortcutRecordingTarget = nil
                        }
                    } label: {
                        Text("Clear")
                    }
                    .fluidCompactButton(
                        size: .small,
                        foreground: BasicsTokens.Semantic.danger,
                        borderColor: BasicsTokens.Semantic.danger.opacity(0.4)
                    )
                }
            }
        }
    }

    private var promptEditorProviderRow: some View {
        AISettingRow(title: "AI provider", helper: "Verified providers only.") {
            Menu {
                let providers = self.viewModel.verifiedPromptProviders()
                if providers.isEmpty {
                    Text("No verified providers")
                } else {
                    ForEach(providers) { provider in
                        Button {
                            self.promptEditorProviderIDDraft = provider.id
                            let models = self.viewModel.models(for: provider.id)
                            if !models.contains(self.promptEditorModelDraft) {
                                self.promptEditorModelDraft = self.viewModel.selectedModel(for: provider.id)
                            }
                            self.syncDraftToPendingConfig()
                        } label: {
                            Label(provider.name, systemImage: provider.id == self.promptEditorProviderIDDraft ? "checkmark" : "")
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(self.viewModel.providerDisplayName(for: self.promptEditorProviderIDDraft))
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    FluidPickerDisclosureIcon(backgroundOpacity: 0.6)
                }
                .searchablePickerControlChrome(
                    width: AISettingsLayout.promptEditorControlColumnWidth,
                    height: AISettingsLayout.controlHeight,
                    usesMaterial: false,
                    showsShadow: false
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var promptEditorModelRow: some View {
        AISettingRow(title: "Model", helper: "Used for this prompt.") {
            HStack(spacing: 8) {
                SearchableModelPicker(
                    models: self.viewModel.models(for: self.promptEditorProviderIDDraft),
                    selectedModel: self.promptEditorModelBinding,
                    onRefresh: nil,
                    selectionEnabled: !self.viewModel.models(for: self.promptEditorProviderIDDraft).isEmpty,
                    controlWidth: AISettingsLayout.promptEditorControlColumnWidth - 38,
                    controlHeight: AISettingsLayout.controlHeight
                )

                self.companionIconButton(
                    isRefreshing: self.viewModel.refreshingProviderID == self.promptEditorProviderIDDraft,
                    disabled: !self.canFetchModels(for: self.promptEditorProviderIDDraft),
                    opacity: self.canFetchModels(for: self.promptEditorProviderIDDraft) ? 1 : 0.45,
                    help: "Refresh model list"
                ) {
                    Task { await self.viewModel.fetchModels(for: self.promptEditorProviderIDDraft) }
                }
            }
        }
    }

    private var promptEditorModelBinding: Binding<String> {
        Binding(
            get: { self.promptEditorModelDraft },
            set: { newValue in
                self.promptEditorModelDraft = newValue
                self.syncDraftToPendingConfig()
            }
        )
    }

    // MARK: - Test mode (board 04c · test mode, five readings)

    private var promptEditorTestSection: some View {
        let hotkeyDisplay = self.settings.primaryDictationShortcutDisplayString
        let canTest = self.viewModel.isAIPostProcessingConfiguredForDictation()

        return VStack(alignment: .leading, spacing: 14) {
            Text("Test")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)

            HStack(alignment: .center, spacing: AISettingsLayout.settingRowGap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Enable test mode")
                            .basicsLabel(14)
                            .foregroundStyle(self.theme.palette.primaryText)

                        AIChip(text: "Hotkey: \(hotkeyDisplay)", tone: .soft, isMono: true)
                    }

                    Text(canTest
                        ? "Press the hotkey to start and stop recording. The transcription is post-processed with your draft prompt and shown below — nothing is typed into other apps."
                        : "Testing is disabled because AI post-processing is not configured.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: Binding(
                    get: { self.promptTest.isActive },
                    set: { enabled in
                        if enabled {
                            let combined = self.viewModel.combinedDraftPrompt(
                                self.viewModel.draftPromptText,
                                mode: self.viewModel.draftPromptMode
                            )
                            self.promptTest.activate(draftPromptText: combined)
                        } else {
                            self.promptTest.deactivate()
                        }
                    }
                ))
                .toggleStyle(GlassToggleStyle())
                .labelsHidden()
                .disabled(!canTest)
                .accessibilityLabel("Enable test mode")
            }

            if self.promptTest.isActive {
                if self.promptTest.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .fixedSize()
                        Text("Processing…")
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                }

                if !self.promptTest.lastError.isEmpty {
                    AIInlineNotice(
                        text: self.promptTest.lastError,
                        systemImage: "exclamationmark.circle",
                        tone: BasicsTokens.Semantic.danger
                    )
                }

                self.promptTestOutputBox(
                    title: "Raw transcription",
                    text: self.promptTest.lastTranscriptionText,
                    minHeight: 70,
                    isEmphasized: false
                )

                self.promptTestOutputBox(
                    title: "Post-processed output",
                    text: self.promptTest.lastOutputText,
                    minHeight: 110,
                    isEmphasized: !self.promptTest.lastOutputText.isEmpty
                )
            }
        }
        .padding(.vertical, 20)
    }

    private func promptTestOutputBox(
        title: String,
        text: String,
        minHeight: CGFloat,
        isEmphasized: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)

            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: minHeight)
            .background(shape.fill(self.theme.palette.cardBackground))
            .overlay(
                shape.stroke(
                    isEmphasized ? self.theme.palette.accent : BasicsBorder.strong(self.theme, self.colorScheme),
                    lineWidth: 1
                )
            )
        }
    }

    private func promptEditorFooter(mode: PromptEditorMode) -> some View {
        HStack(spacing: 10) {
            if mode.isDefault,
               let promptMode = mode.mode,
               self.viewModel.hasDefaultPromptOverride(for: promptMode)
            {
                Button {
                    self.viewModel.resetDefaultPromptOverride(for: promptMode)
                    self.viewModel.openDefaultPromptViewer(for: promptMode)
                    self.preparePromptEditorConfigurationDraft(mode: .defaultPrompt(mode: promptMode))
                } label: {
                    Text("Reset to built-in")
                }
                .fluidCompactButton(size: .small)
            }

            Spacer(minLength: 0)

            Button {
                self.restorePromptEditorConfigurationDraft(mode: mode)
                self.viewModel.closePromptEditor()
            } label: {
                Text("Cancel")
            }
            .fluidCompactButton(size: .small)

            Button {
                self.applyPromptEditorConfigurationDraft(mode: mode)
                self.viewModel.savePromptEditor(mode: mode)
            } label: {
                Text("Save")
            }
            .fluidButton(.accent, size: .small)
            .disabled(!mode.isDefault && self.viewModel.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func autoDisablePromptTestIfNeeded() {
        guard self.promptTest.isActive else { return }
        if !self.viewModel.isAIPostProcessingConfiguredForDictation() {
            self.promptTest.deactivate()
        }
    }

    func openDefaultPromptViewer(for mode: SettingsStore.PromptMode) {
        self.viewModel.openDefaultPromptViewer(for: mode)
    }

    func openNewPromptEditor(prefillMode: SettingsStore.PromptMode = .edit) {
        self.viewModel.openNewPromptEditor(prefillMode: prefillMode)
    }

    func openPrivateAIPromptEditor() {
        self.viewModel.openPrivateAIPromptEditor()
    }

    func openEditor(for profile: SettingsStore.DictationPromptProfile) {
        self.viewModel.openEditor(for: profile)
    }

    func closePromptEditor() {
        self.viewModel.closePromptEditor()
    }

    // MARK: - Prompt Test Gating

    func isAIPostProcessingConfiguredForDictation() -> Bool {
        self.viewModel.isAIPostProcessingConfiguredForDictation()
    }

    func savePromptEditor(mode: PromptEditorMode) {
        self.viewModel.savePromptEditor(mode: mode)
    }
}
