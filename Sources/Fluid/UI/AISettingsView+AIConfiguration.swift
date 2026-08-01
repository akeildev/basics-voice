//
//  AISettingsView+AIConfiguration.swift
//  fluid
//
//  Board "04b — providers" (+ · states, · Fluid Intelligence runtime).
//  Extracted from AISettingsView.swift to keep view body under lint limit.
//

import AppKit
import SwiftUI

extension AIEnhancementSettingsView {
    // MARK: - Page body

    /// The AI enhancements page under its head: a segmented tab strip with the
    /// tab's own action pinned opposite, then whichever tab is open.
    var aiConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            self.configurationTabRow

            Group {
                switch self.selectedConfigurationSection {
                case .providers:
                    self.providerConfigurationContent
                case .advancedPrompts:
                    self.promptsStepContent
                }
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.12), value: self.selectedConfigurationSection)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var configurationTabRow: some View {
        HStack(alignment: .center, spacing: 16) {
            self.aiConfigurationSectionPicker

            Spacer(minLength: 12)

            switch self.selectedConfigurationSection {
            case .providers:
                self.helpToggleButton
            case .advancedPrompts:
                self.promptProfilesAboutButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiConfigurationSectionPicker: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        return HStack(spacing: 4) {
            ForEach(AIEnhancementConfigurationSection.allCases) { section in
                self.aiConfigurationSectionButton(section)
            }
        }
        .padding(4)
        .background(shape.fill(self.theme.palette.sidebarBackground))
        .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private func aiConfigurationSectionButton(_ section: AIEnhancementConfigurationSection) -> some View {
        let isSelected = self.selectedConfigurationSection == section
        let isHovering = self.hoveredConfigurationSection == section
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
        let ink: Color = isSelected
            ? self.theme.palette.primaryText
            : (isHovering ? self.theme.palette.primaryText : self.theme.palette.secondaryText)

        return Button {
            self.selectedConfigurationSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? self.theme.palette.accent : ink)
                Text(section.title)
                    .basicsLabel(13)
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .contentShape(shape)
            .background {
                if isSelected {
                    shape
                        .fill(self.theme.palette.cardBackground)
                        .basicsShadows([
                            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 1, y: 1),
                        ])
                } else if isHovering {
                    shape.fill(self.theme.palette.cardBackground.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            self.hoveredConfigurationSection = hovering ? section : nil
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var helpToggleButton: some View {
        Button {
            self.viewModel.showHelp.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: self.viewModel.showHelp ? "questionmark.circle.fill" : "questionmark.circle")
                    .font(.system(size: 13, weight: .medium))
                Text("Help")
            }
        }
        .fluidCompactButton(size: .small, isReady: self.viewModel.showHelp)
        .help("Show the quick start guide")
    }

    private var promptProfilesAboutButton: some View {
        Button {
            self.isPromptProfilesHelpPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                Text("About prompt profiles")
            }
        }
        .fluidCompactButton(size: .small, isReady: self.isPromptProfilesHelpPresented)
        .help("About prompt profiles")
        .popover(isPresented: self.$isPromptProfilesHelpPresented, arrowEdge: .bottom) {
            self.promptProfilesHelpPopover
        }
    }

    // MARK: - AI providers tab

    private var providerConfigurationContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if self.viewModel.showHelp {
                self.helpSectionView
            }

            self.verifiedProvidersSection
            self.allProvidersSection
        }
    }

    /// Board 04b · states — "Help expanded". Drops in under the tab strip.
    var helpSectionView: some View {
        AIListCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick start guide")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)

                VStack(alignment: .leading, spacing: 10) {
                    self.helpStep(1, "Choose a provider")
                    self.helpStep(2, "Add an API key if needed")
                    self.helpStep(3, "Pick the model you want")
                    self.helpStep(4, "Verify the connection")
                    self.helpStep(5, "Set Dictate to Off, Default, or a custom prompt")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            AIHairline()

            HStack(spacing: 22) {
                self.helpFact("desktopcomputer", "Local models run on Mac")
                self.helpFact("cloud", "Cloud models use provider APIs")
                self.helpFact("keyboard", "Shortcuts choose when prompts run")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .transition(.opacity)
    }

    private func helpStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .basicsMono(12)
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 12, alignment: .leading)

            Text(text)
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.primaryText)
        }
    }

    private func helpFact(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)
            Text(text)
                .basicsLabel(12)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Verified providers

    private var verifiedProvidersSection: some View {
        let verified = self.verifiedProviderItems

        return VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "Verified providers", count: verified.count)

            if verified.isEmpty {
                AIEmptyWell {
                    Text("No verified providers yet")
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    Text("Set up a provider below and verify its connection")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(verified) { item in
                        self.verifiedProviderRow(item)
                    }
                }
            }
        }
    }

    struct ProviderItem: Identifiable, Hashable {
        let id: String
        let name: String
        let isBuiltIn: Bool
    }

    private struct PrivateAIProviderModelStatus {
        let detail: String
        let color: Color
    }

    // Use cached provider items from ViewModel for scroll performance
    private var verifiedProviderItems: [ProviderItem] {
        self.viewModel.cachedVerifiedProviderItems.map {
            ProviderItem(id: $0.id, name: $0.name, isBuiltIn: $0.isBuiltIn)
        }
    }

    private var unverifiedProviderItems: [ProviderItem] {
        self.viewModel.cachedUnverifiedProviderItems.map {
            ProviderItem(id: $0.id, name: $0.name, isBuiltIn: $0.isBuiltIn)
        }
    }

    /// Shared companion button for provider rows — identical size/style everywhere.
    @ViewBuilder
    func companionIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(SquareIconButtonStyle())
        .help(help)
    }

    /// Shared companion button with loading state — for refresh buttons.
    @ViewBuilder
    func companionIconButton(
        isRefreshing: Bool,
        disabled: Bool = false,
        opacity: Double = 1,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .fixedSize()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .buttonStyle(SquareIconButtonStyle())
        .disabled(disabled)
        .opacity(opacity)
        .help(help)
    }

    /// The row a provider is promoted to once its connection is verified. Border
    /// goes brand while it is the provider dictation actually uses.
    private func verifiedProviderRow(_ item: ProviderItem) -> some View {
        let providerKey = self.viewModel.providerKey(for: item.id)
        let models = self.viewModel.availableModelsByProvider[providerKey] ?? []
        let isSelected = item.id == self.viewModel.selectedProviderID
        let isPrivateAIProvider = item.id == PrivateAIProviderFeature.shared.providerID
        let fluidModel = self.selectedPrivateAIModel
        let fluidStatus = self.privateAIModelStatus(for: fluidModel)
        let isFluidInstalled = PrivateAIIntegrationService.isModelInstalled(fluidModel)
        let isFluidDownloading = self.privateAILoadState.isDownloading(fluidModel.id)
        let fluidDownloadProgress = self.privateAILoadState.downloadProgress(for: fluidModel.id)
        let isFluidLoading = self.privateAILoadState.isLoading(fluidModel.id)
        let isFluidLoaded = self.privateAILoadState.isLoaded(fluidModel.id)
        let hasFluidLoadFailure = self.privateAILoadState.failureMessage(for: fluidModel.id) != nil
        let isFluidVerified = self.isPrivateAIModelVerified(fluidModel)
        let isFluidTesting = self.viewModel.isTestingConnection && self.viewModel.selectedProviderID == PrivateAIProviderFeature.shared.providerID
        let isFluidBusy = isFluidDownloading || isFluidLoading || isFluidTesting
        let isRefreshing = self.viewModel.isFetchingModels && self.viewModel.selectedProviderID == item.id
        let baseURL = self.providerBaseURL(for: item).trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.viewModel.isLocalEndpoint(baseURL)
        let apiKeyValue = self.viewModel.providerAPIKey(for: item.id)
        let hasAPIKey = !apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canFetchModels = isLocal ? !baseURL.isEmpty : (hasAPIKey && !baseURL.isEmpty)
        let hasModels = !models.isEmpty
        let isEditing = self.viewModel.showingEditProvider && self.viewModel.selectedProviderID == item.id
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .lineLimit(1)

                        if isPrivateAIProvider {
                            AIChip(text: "On device", tone: .neutral, isUppercase: true)
                        } else if isSelected {
                            AIChip(text: "Active", tone: .brand, isUppercase: true)
                        }
                    }

                    self.verifiedProviderSubtitle(
                        item: item,
                        isPrivateAIProvider: isPrivateAIProvider,
                        detail: fluidStatus.detail,
                        baseURL: baseURL,
                        apiKey: apiKeyValue
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isPrivateAIProvider {
                        SearchableModelPicker(
                            models: PrivateAIModelRegistry.modelIDs(),
                            selectedModel: self.privateAIModelBinding,
                            selectionEnabled: !isFluidBusy,
                            controlWidth: 180,
                            controlHeight: AISettingsLayout.providerRowControlHeight
                        )

                        self.companionIconButton(systemName: "folder", help: "Open downloaded model folder") {
                            self.revealPrivateAIModelFolder()
                        }

                        // Keeps the action lane aligned with API rows, which carry a
                        // reasoning button here. Reasoning does not apply on-device.
                        Color.clear
                            .frame(width: 28, height: 28)

                        Button {
                            self.activateProvider(item.id)
                            if isEditing {
                                self.viewModel.clearEditProviderDraft()
                            } else {
                                self.viewModel.startEditingProvider()
                            }
                        } label: {
                            Text("Edit")
                        }
                        .fluidCompactButton(size: .small, isReady: isEditing)
                        .help("Edit provider")
                    } else {
                        SearchableModelPicker(
                            models: models,
                            selectedModel: self.modelBinding(for: item.id),
                            selectionEnabled: hasModels,
                            controlWidth: 180,
                            controlHeight: AISettingsLayout.providerRowControlHeight
                        )

                        self.companionIconButton(
                            isRefreshing: isRefreshing,
                            disabled: isRefreshing || !canFetchModels,
                            opacity: canFetchModels ? 1 : 0.45,
                            help: "Refresh model list"
                        ) {
                            self.activateProvider(item.id)
                            Task { await self.viewModel.fetchModelsForCurrentProvider() }
                        }

                        self.reasoningButton(for: item.id)

                        Button {
                            self.activateProvider(item.id)
                            if isEditing {
                                self.viewModel.clearEditProviderDraft()
                                self.viewModel.setEditingAPIKey(false, for: item.id)
                            } else {
                                self.viewModel.startEditingProvider()
                                self.viewModel.setEditingAPIKey(true, for: item.id)
                            }
                        } label: {
                            Text("Edit")
                        }
                        .fluidCompactButton(size: .small, isReady: isEditing)
                        .help("Edit provider")
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: AISettingsLayout.rowHeight)
            .padding(.leading, 18)
            .padding(.trailing, 14)

            if isPrivateAIProvider,
               isFluidDownloading || isFluidLoading || isFluidLoaded || hasFluidLoadFailure || isFluidVerified || !isFluidInstalled
            {
                AIHairline()

                self.privateAIModelStatusRow(
                    model: fluidModel,
                    status: fluidStatus,
                    progress: fluidDownloadProgress,
                    isDownloading: isFluidDownloading,
                    showsLoadingIndicator: isFluidLoading || isFluidTesting,
                    isInstalled: isFluidInstalled,
                    isVerified: isFluidVerified,
                    isBusy: isFluidBusy,
                    isTesting: isFluidTesting
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            if isEditing {
                AIHairline()

                Group {
                    if isPrivateAIProvider {
                        self.privateAIEditProviderSection(
                            model: fluidModel,
                            isInstalled: isFluidInstalled,
                            isBusy: isFluidBusy,
                            isVerified: isFluidVerified
                        )
                    } else {
                        self.editProviderSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            if !isPrivateAIProvider,
               self.viewModel.showingReasoningConfig,
               self.viewModel.selectedProviderID == item.id
            {
                AIHairline()

                self.reasoningConfigSection
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(self.theme.palette.cardBackground))
        .overlay(
            shape.stroke(
                isSelected ? self.theme.palette.accent : self.theme.palette.cardBorder,
                lineWidth: isSelected ? 2 : 1
            )
        )
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture {
            self.activateProvider(item.id)
            self.expandedProviderID = nil
        }
    }

    /// The second line of a verified row: what the row is actually bound to.
    /// Never a made-up timestamp — the masked key, the endpoint, or the local
    /// runtime's own status sentence.
    @ViewBuilder
    private func verifiedProviderSubtitle(
        item: ProviderItem,
        isPrivateAIProvider: Bool,
        detail: String,
        baseURL: String,
        apiKey: String
    ) -> some View {
        if isPrivateAIProvider {
            Text(detail)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
        } else if let masked = AIProviderSecretFormatter.masked(apiKey) {
            Text(masked)
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if !baseURL.isEmpty {
            Text(baseURL)
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - All providers

    private var allProvidersSection: some View {
        let query = self.providerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = self.unverifiedProviderItems
        let filteredItems = query.isEmpty
            ? items
            : items.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                    $0.id.localizedCaseInsensitiveContains(query)
            }

        return VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: "All providers", count: filteredItems.count) {
                self.providerSearchField
            }

            if filteredItems.isEmpty {
                AIEmptyWell {
                    Text(query.isEmpty
                        ? "Every provider is verified"
                        : "No providers match “\(query)”")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            } else {
                AIListCard {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            AIHairline()
                        }
                        self.providerCard(item)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    self.startCustomProvider()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add custom provider")
                    }
                }
                .fluidCompactButton(size: .small)

                Text("Any OpenAI-compatible endpoint.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.tertiaryText)

                Spacer(minLength: 0)
            }
        }
    }

    private var providerSearchField: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)

            TextField("Search providers", text: self.$providerSearchText)
                .textFieldStyle(.plain)
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.primaryText)

            if !self.providerSearchText.isEmpty {
                Button {
                    self.providerSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: AISettingsLayout.controlHeight)
        .background(shape.fill(self.theme.palette.cardBackground))
        .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
    }

    /// One row of the All-providers list. The chevron is the only structural
    /// change between rest and expanded; expanded also tints its own header.
    private func providerCard(_ item: ProviderItem) -> some View {
        let isPrivateAIProvider = item.id == PrivateAIProviderFeature.shared.providerID
        let isExpanded = self.expandedProviderID == item.id
        let isHovering = self.hoveredProviderCardID == item.id
        let isCustom = !ModelRepository.shared.isBuiltIn(item.id)
        let status = self.viewModel.connectionStatus(for: item.id)
        let collapsedError = self.viewModel.connectionErrorMessage(for: item.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                self.toggleProviderExpansion(item.id)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isExpanded
                            ? self.theme.palette.primaryText
                            : self.theme.palette.tertiaryText)
                        .frame(width: 12)

                    Text(item.name)
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)

                    if isCustom {
                        AIChip(text: "Custom", tone: .neutral, isUppercase: true)
                    }

                    Spacer(minLength: 12)

                    AIStatusReading(status: status)
                }
                .padding(.horizontal, AISettingsLayout.cardGutter)
                .frame(height: AISettingsLayout.listRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isExpanded
                        ? self.theme.palette.sidebarBackground
                        : (isHovering ? self.theme.palette.sidebarBackground.opacity(0.5) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                self.hoveredProviderCardID = hovering ? item.id : nil
            }

            if !isExpanded, status == .failed, !collapsedError.isEmpty {
                AIErrorLog(message: collapsedError, lineLimit: 2)
                    .padding(.horizontal, AISettingsLayout.cardGutter)
                    .padding(.bottom, 13)
            }

            if isExpanded {
                Group {
                    if isPrivateAIProvider {
                        self.privateAIRuntimeSection
                    } else {
                        self.providerDetailsSection(for: item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func toggleProviderExpansion(_ providerID: String) {
        if self.expandedProviderID == providerID {
            self.expandedProviderID = nil
            self.viewModel.clearEditProviderDraft()
            self.viewModel.setEditingAPIKey(false, for: providerID)
        } else {
            self.expandedProviderID = providerID
            self.selectProvider(providerID)
        }
    }

    // MARK: - Fluid Intelligence runtime (board 04b · Fluid Intelligence runtime)

    private var privateAIRuntimeSection: some View {
        let model = self.selectedPrivateAIModel
        let status = self.privateAIModelStatus(for: model)
        let isInstalled = PrivateAIIntegrationService.isModelInstalled(model)
        let isDownloading = self.privateAILoadState.isDownloading(model.id)
        let downloadProgress = self.privateAILoadState.downloadProgress(for: model.id)
        let isLoading = self.privateAILoadState.isLoading(model.id)
        let isLoaded = self.privateAILoadState.isLoaded(model.id)
        let hasLoadFailure = self.privateAILoadState.failureMessage(for: model.id) != nil
        let isVerified = self.isPrivateAIModelVerified(model)
        let isTesting = self.viewModel.isTestingConnection && self.viewModel.selectedProviderID == PrivateAIProviderFeature.shared.providerID
        let isBusy = isDownloading || isLoading || isTesting

        return VStack(alignment: .leading, spacing: 0) {
            AISettingRow(
                title: "Model",
                helper: "Downloaded once and kept on this Mac. Nothing you dictate leaves the machine.",
                isDimmed: isBusy
            ) {
                HStack(spacing: 8) {
                    SearchableModelPicker(
                        models: PrivateAIModelRegistry.modelIDs(),
                        selectedModel: self.privateAIModelBinding,
                        selectionEnabled: !isBusy,
                        controlWidth: 220,
                        controlHeight: AISettingsLayout.controlHeight
                    )

                    self.companionIconButton(systemName: "folder", help: "Open downloaded model folder") {
                        self.revealPrivateAIModelFolder()
                    }
                }
            }

            AIHairline()

            AISettingRow(
                title: "Backend",
                helper: self.settings.privateAIBackendPreference.detail,
                isDimmed: isBusy
            ) {
                self.privateAIBackendPicker(isBusy: isBusy)
                    .frame(width: 220)
            }

            AIHairline()

            AISettingRow(
                title: "Faster first result",
                helper: "Keeps Fluid-1 ready so your first dictation finishes sooner."
            ) {
                Toggle("", isOn: self.privateAIPrefixCacheBinding)
                    .toggleStyle(GlassToggleStyle())
                    .labelsHidden()
                    .disabled(isBusy)
                    .help("Keeps Fluid-1 ready so your first dictation finishes sooner.")
                    .accessibilityLabel("Faster first result")
            }

            if self.privateAIShowsBoostRow {
                AIHairline()

                AISettingRow(
                    title: "Faster results",
                    helper: "Finishes dictation up to 15% faster. Uses about 100 MB more memory."
                ) {
                    Toggle("", isOn: self.privateAIBoostBinding)
                        .toggleStyle(GlassToggleStyle())
                        .labelsHidden()
                        .disabled(isBusy)
                        .help("Uses extra local acceleration so Fluid-1 finishes faster.")
                        .accessibilityLabel("Faster results")
                }
            }

            if isDownloading || isLoading || isLoaded || hasLoadFailure || isVerified || !isInstalled {
                AIHairline()

                self.privateAIModelStatusRow(
                    model: model,
                    status: status,
                    progress: downloadProgress,
                    isDownloading: isDownloading,
                    showsLoadingIndicator: isLoading,
                    isInstalled: isInstalled,
                    isVerified: isVerified,
                    isBusy: isBusy,
                    isTesting: isTesting
                )
                .padding(.vertical, 16)
            }

            if self.viewModel.connectionStatus(for: PrivateAIProviderFeature.shared.providerID) == .failed,
               !self.viewModel.connectionErrorMessage.isEmpty
            {
                AIErrorLog(message: self.viewModel.connectionErrorMessage, lineLimit: 8)
                    .padding(.bottom, 4)
            }
        }
    }

    /// Board 04b · Fluid Intelligence runtime — "status strip, every state".
    /// One strip: reading on the left, the action it unlocks on the right.
    private func privateAIModelStatusRow(
        model: PrivateAIRegisteredModel,
        status: PrivateAIProviderModelStatus,
        progress: PrivateAIModelDownloadProgress?,
        isDownloading: Bool,
        showsLoadingIndicator: Bool,
        isInstalled: Bool,
        isVerified: Bool,
        isBusy: Bool,
        isTesting: Bool
    ) -> some View {
        let failureMessage = self.privateAILoadState.failureMessage(for: model.id)
        let canVerify = isInstalled
            && (!isVerified || failureMessage != nil)
            && !self.privateAISelectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if showsLoadingIndicator, !isDownloading {
                        ProgressView()
                            .controlSize(.mini)
                            .fixedSize()
                    } else if isVerified, failureMessage == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(status.color)
                    }

                    Text(status.detail)
                        .basicsProse(13)
                        .foregroundStyle(status.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isDownloading {
                    self.privateAIDownloadProgressBar(progress: progress, color: status.color)

                    Text(Self.downloadProgressText(progress))
                        .basicsMono(11)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(1)
                }

                if let failureMessage {
                    AIErrorLog(message: failureMessage, lineLimit: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isInstalled {
                if model.canDownload {
                    Button {
                        self.downloadPrivateAIModel(model)
                    } label: {
                        HStack(spacing: 6) {
                            if isDownloading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .fixedSize()
                            }
                            Text(
                                isDownloading
                                    ? Self.downloadButtonText(progress: progress)
                                    : "Download \(self.privateAIBackendShortName) & verify"
                            )
                        }
                    }
                    .fluidButton(.accent, size: .small)
                    .disabled(isBusy)
                }
            } else if canVerify {
                Button {
                    self.verifyPrivateAIConnection(model)
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.mini)
                                .fixedSize()
                        }
                        Text(isTesting ? "Loading…" : "Verify")
                    }
                }
                .fluidButton(.accent, size: .small)
                .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privateAIBackendPicker(isBusy: Bool) -> some View {
        Picker("", selection: self.privateAIBackendBinding) {
            ForEach(self.privateAISelectableBackendPreferences) { preference in
                Text(preference.displayName).tag(preference)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(isBusy || self.privateAISelectableBackendPreferences.count < 2)
        .help("Local Fluid-1 runtime. Default is MLX on Apple Silicon.")
    }

    private var privateAISelectableBackendPreferences: [SettingsStore.PrivateAIBackendPreference] {
        CPUArchitecture.isIntel ? [.llama] : [.mlx, .llama]
    }

    private var privateAIBackendShortName: String {
        switch self.settings.privateAIBackendPreference {
        case .auto:
            return SettingsStore.PrivateAIBackendPreference.systemDefault == .mlx ? "MLX" : "llama.cpp"
        case .llama:
            return "llama.cpp"
        case .mlx:
            return "MLX"
        }
    }

    @ViewBuilder
    private func privateAIDownloadProgressBar(
        progress: PrivateAIModelDownloadProgress?,
        color: Color
    ) -> some View {
        if let fractionCompleted = progress?.fractionCompleted {
            ProgressView(value: fractionCompleted)
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)
                .tint(color)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)
                .tint(color)
        }
    }

    private var privateAIPrefixCacheBinding: Binding<Bool> {
        Binding(
            get: { self.settings.privateAIPrefixKVCacheEnabled },
            set: { enabled in
                guard self.settings.privateAIPrefixKVCacheEnabled != enabled else { return }
                self.settings.privateAIPrefixKVCacheEnabled = enabled
                self.privateAILoadState = .idle
                Task { @MainActor in
                    await PrivateAIIntegrationService.shared.unloadCachedRuntime(
                        reason: enabled ? "prefix cache enabled" : "prefix cache disabled"
                    )
                    self.viewModel.refreshProviderItems()
                }
            }
        )
    }

    private var privateAIBoostBinding: Binding<Bool> {
        Binding(
            get: { self.settings.privateAIBoostEnabled },
            set: { enabled in
                guard self.settings.privateAIBoostEnabled != enabled else { return }
                self.settings.privateAIBoostEnabled = enabled
                self.privateAILoadState = .idle
                Task { @MainActor in
                    await PrivateAIIntegrationService.shared.unloadCachedRuntime(
                        reason: enabled ? "Fluid-1 Boost enabled" : "Fluid-1 Boost disabled"
                    )
                    self.viewModel.refreshProviderItems()
                }
            }
        )
    }

    private var privateAIBackendBinding: Binding<SettingsStore.PrivateAIBackendPreference> {
        Binding(
            get: { self.settings.privateAIBackendPreference },
            set: { preference in
                self.setPrivateAIBackendPreference(preference)
            }
        )
    }

    private var privateAIShowsBoostRow: Bool {
        switch self.settings.privateAIBackendPreference {
        case .llama:
            return true
        case .auto:
            return CPUArchitecture.isIntel
        case .mlx:
            return false
        }
    }

    private var privateAIContextTokenLimitBinding: Binding<Int> {
        Binding(
            get: { self.settings.privateAIContextTokenLimit },
            set: { value in
                let clamped = SettingsStore.clampPrivateAIContextTokenLimit(value)
                guard self.settings.privateAIContextTokenLimit != clamped else { return }
                self.settings.privateAIContextTokenLimit = clamped
                self.privateAILoadState = .idle
                Task { @MainActor in
                    await PrivateAIIntegrationService.shared.unloadCachedRuntime(
                        reason: "Fluid Intelligence context changed"
                    )
                    self.viewModel.refreshProviderItems()
                }
            }
        )
    }

    private var privateAIModelBinding: Binding<String> {
        Binding(
            get: { self.privateAISelectedModelID },
            set: { self.persistPrivateAIModelSelection($0) }
        )
    }

    private func downloadPrivateAIModel(_ model: PrivateAIRegisteredModel) {
        guard model.canDownload else {
            self.privateAILoadState = .failed(modelID: model.id, message: "Download URL is not configured yet.")
            return
        }

        guard !self.privateAILoadState.isDownloading(model.id) else { return }

        self.privateAILoadState = .downloading(
            modelID: model.id,
            progress: PrivateAIModelDownloadProgress(initialExpectedBytes: model.artifact.byteCount)
        )
        Task { @MainActor in
            do {
                DebugLogger.shared.info(
                    "Private provider download button pressed model=\(model.id)",
                    source: "AISettingsView"
                )
                _ = try await PrivateAIIntegrationService.prepareModel(model) { progress in
                    await MainActor.run {
                        guard self.privateAISelectedModelID == model.id else { return }
                        self.privateAILoadState = .downloading(
                            modelID: model.id,
                            progress: progress.withFallbackExpectedBytes(model.artifact.byteCount)
                        )
                    }
                }
                guard self.privateAISelectedModelID == model.id else { return }
                self.privateAILoadState = .loading(modelID: model.id)
                let start = ContinuousClock.now
                let verified = await self.viewModel.verifyPrivateAIProvider(model: model)
                let latencyMilliseconds = Self.elapsedMilliseconds(since: start)
                guard self.privateAISelectedModelID == model.id else { return }
                if verified {
                    self.privateAILoadState = .loaded(modelID: model.id, latencyMilliseconds: latencyMilliseconds)
                    if PrivateAIMLXUpgradeCoordinator.isUpgradePending() {
                        PrivateAIMLXUpgradeCoordinator.completeUpgrade()
                        await PrivateAIIntegrationService.shared.removeInactiveInstalledModels(keeping: model)
                    }
                } else {
                    let message = self.viewModel.connectionErrorMessage.isEmpty
                        ? "Model downloaded, but verification failed."
                        : self.viewModel.connectionErrorMessage
                    self.restoreLlamaAfterFailedMLXUpgrade(message: message, modelID: model.id)
                }
            } catch {
                guard self.privateAISelectedModelID == model.id else { return }
                self.restoreLlamaAfterFailedMLXUpgrade(
                    message: Self.errorMessage(for: error),
                    modelID: model.id
                )
            }
            self.viewModel.refreshProviderItems()
        }
    }

    private func restoreLlamaAfterFailedMLXUpgrade(message: String, modelID: String) {
        guard PrivateAIMLXUpgradeCoordinator.isUpgradePending() else {
            self.privateAILoadState = .failed(modelID: modelID, message: message)
            return
        }

        PrivateAIMLXUpgradeCoordinator.restorePreviousLlama()
        self.viewModel.onAppear()
        self.privateAILoadState = .failed(
            modelID: modelID,
            message: "MLX upgrade failed. Your previous llama.cpp model is still active. \(message)"
        )
    }

    private func verifyPrivateAIConnection(_ model: PrivateAIRegisteredModel) {
        self.privateAILoadState = .loading(modelID: model.id)
        Task { @MainActor in
            let start = ContinuousClock.now
            let verified = await self.viewModel.verifyPrivateAIProvider(model: model)
            let latencyMilliseconds = Self.elapsedMilliseconds(since: start)
            guard self.privateAISelectedModelID == model.id else { return }
            if verified {
                self.privateAILoadState = .loaded(modelID: model.id, latencyMilliseconds: latencyMilliseconds)
            } else {
                let message = self.viewModel.connectionErrorMessage.isEmpty
                    ? "Model verification failed."
                    : self.viewModel.connectionErrorMessage
                self.privateAILoadState = .failed(modelID: model.id, message: message)
            }
            self.viewModel.refreshProviderItems()
        }
    }

    private var selectedPrivateAIModel: PrivateAIRegisteredModel {
        PrivateAIModelRegistry.model(id: self.privateAISelectedModelID) ?? PrivateAIModelRegistry.defaultModel
    }

    private func isPrivateAIModelVerified(_ model: PrivateAIRegisteredModel) -> Bool {
        guard PrivateAIIntegrationService.isModelInstalled(model) else { return false }
        let key = self.viewModel.providerKey(for: PrivateAIProviderFeature.shared.providerID)
        return self.viewModel.settings.verifiedProviderFingerprints[key] == PrivateAIProviderFeature.verificationFingerprint(for: model.id)
    }

    private func privateAIModelStatus(
        for model: PrivateAIRegisteredModel
    ) -> PrivateAIProviderModelStatus {
        if self.privateAILoadState.isDownloading(model.id) {
            return PrivateAIProviderModelStatus(
                detail: "Downloading model.",
                color: self.theme.palette.accent
            )
        }

        if self.privateAILoadState.isLoading(model.id) {
            return PrivateAIProviderModelStatus(
                detail: "Loading…",
                color: self.theme.palette.accent
            )
        }

        if self.privateAILoadState.isLoaded(model.id) {
            return PrivateAIProviderModelStatus(
                detail: "For dictation only. Loaded and verified.",
                color: self.theme.palette.accent
            )
        }

        if self.privateAILoadState.failureMessage(for: model.id) != nil {
            return PrivateAIProviderModelStatus(
                detail: "Could not load the model.",
                color: BasicsTokens.Semantic.danger
            )
        }

        if self.isPrivateAIModelVerified(model) {
            return PrivateAIProviderModelStatus(
                detail: "For dictation only. Verified.",
                color: self.theme.palette.accent
            )
        }

        if PrivateAIIntegrationService.isModelInstalled(model) {
            return PrivateAIProviderModelStatus(
                detail: "Ready to verify.",
                color: self.theme.palette.accent
            )
        }

        if PrivateAIIntegrationService.isLocalRuntimeConfigured {
            return PrivateAIProviderModelStatus(
                detail: "Local model configured.",
                color: self.theme.palette.accent
            )
        }

        if model.canDownload {
            let size = model.artifact.byteCount.map {
                " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))"
            } ?? ""
            return PrivateAIProviderModelStatus(
                detail: "\(self.privateAIBackendShortName) model not downloaded\(size).",
                color: self.theme.palette.secondaryText
            )
        }

        return PrivateAIProviderModelStatus(
            detail: "Model unavailable.",
            color: BasicsTokens.Semantic.warning
        )
    }

    private func revealPrivateAIModelFolder() {
        let directoryURL = PrivateAIIntegrationService.modelDirectoryURL
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directoryURL)
        } catch {
            DebugLogger.shared.error(
                "Failed to open Private AI Provider models folder: \(error.localizedDescription)",
                source: "AISettingsView"
            )
        }
    }

    func refreshPrivateAILoadState() {
        Task { @MainActor in
            guard let loaded = await PrivateAIIntegrationService.shared.loadedModelState(),
                  loaded.state == .ready
            else {
                self.privateAILoadState = .idle
                return
            }

            self.privateAILoadState = .loaded(modelID: loaded.modelID, latencyMilliseconds: nil)
        }
    }

    private func loadPrivateAIModel(_ model: PrivateAIRegisteredModel) {
        guard PrivateAIIntegrationService.isModelInstalled(model) else {
            self.privateAILoadState = .failed(modelID: model.id, message: "Model file is not installed.")
            return
        }

        self.privateAILoadState = .loading(modelID: model.id)
        Task { @MainActor in
            do {
                let start = ContinuousClock.now
                let status = try await PrivateAIIntegrationService.shared.loadModel(model)
                let latencyMilliseconds = Self.elapsedMilliseconds(since: start)
                guard self.privateAISelectedModelID == model.id else { return }
                switch status.state {
                case .ready:
                    self.privateAILoadState = .loaded(modelID: model.id, latencyMilliseconds: latencyMilliseconds)
                default:
                    self.privateAILoadState = .failed(
                        modelID: model.id,
                        message: status.message ?? "Model did not report ready."
                    )
                }
            } catch {
                guard self.privateAISelectedModelID == model.id else { return }
                self.privateAILoadState = .failed(
                    modelID: model.id,
                    message: Self.errorMessage(for: error)
                )
            }
            self.viewModel.refreshProviderItems()
        }
    }

    private func resetPrivateAIVerification(for model: PrivateAIRegisteredModel) {
        self.viewModel.resetVerification(for: PrivateAIProviderFeature.shared.providerID)
        self.privateAILoadState = .idle
        Task { @MainActor in
            await PrivateAIIntegrationService.shared.unloadCachedRuntime(reason: "Fluid Intelligence verification reset")
            if PrivateAIIntegrationService.isModelInstalled(model) {
                self.privateAILoadState = .idle
            }
            self.viewModel.refreshProviderItems()
        }
    }

    private func deletePrivateAIModel(_ model: PrivateAIRegisteredModel) {
        guard PrivateAIIntegrationService.canRemoveInstalledModel(model) else { return }
        self.privateAILoadState = .loading(modelID: model.id)
        Task { @MainActor in
            do {
                try await PrivateAIIntegrationService.shared.unloadAndRemoveInstalledModel(
                    model,
                    reason: "settings-delete"
                )
                self.viewModel.resetVerification(for: PrivateAIProviderFeature.shared.providerID)
                if self.privateAISelectedModelID == model.id {
                    self.privateAILoadState = .idle
                }
                self.viewModel.refreshProviderItems()
            } catch {
                guard self.privateAISelectedModelID == model.id else { return }
                self.privateAILoadState = .failed(modelID: model.id, message: Self.errorMessage(for: error))
            }
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

    private static func downloadButtonText(progress: PrivateAIModelDownloadProgress?) -> String {
        PrivateAIModelDownloadProgressText.buttonTitle(for: progress)
    }

    private static func downloadProgressText(_ progress: PrivateAIModelDownloadProgress?) -> String {
        PrivateAIModelDownloadProgressText.detailText(for: progress)
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: ContinuousClock.now)
        return Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func persistPrivateAIModelSelection(_ value: String) {
        let model = PrivateAIModelRegistry.model(id: value) ?? PrivateAIModelRegistry.defaultModel
        let providerKey = self.viewModel.providerKey(for: PrivateAIProviderFeature.shared.providerID)
        let models = PrivateAIModelRegistry.modelIDs()

        self.privateAISelectedModelID = model.id
        UserDefaults.standard.set(model.id, forKey: PrivateAIIntegrationService.selectedModelDefaultsKey)
        UserDefaults.standard.removeObject(forKey: PrivateAIIntegrationService.localModelPathDefaultsKey)

        self.viewModel.availableModelsByProvider[providerKey] = models
        self.viewModel.selectedModelByProvider[providerKey] = model.id
        self.viewModel.settings.availableModelsByProvider = self.viewModel.availableModelsByProvider
        self.viewModel.settings.selectedModelByProvider = self.viewModel.selectedModelByProvider

        if self.viewModel.selectedProviderID == PrivateAIProviderFeature.shared.providerID {
            self.viewModel.availableModels = models
            self.viewModel.selectedModel = model.id
        }
        self.viewModel.resetVerification(for: PrivateAIProviderFeature.shared.providerID)
        self.viewModel.refreshProviderItems()
        if PrivateAIIntegrationService.isModelInstalled(model) {
            self.loadPrivateAIModel(model)
        } else {
            self.privateAILoadState = .idle
        }
    }

    private func setPrivateAIBackendPreference(_ preference: SettingsStore.PrivateAIBackendPreference) {
        guard self.settings.privateAIBackendPreference != preference else { return }
        let modelID = self.privateAISelectedModelID

        self.settings.privateAIBackendPreference = preference
        UserDefaults.standard.removeObject(forKey: PrivateAIIntegrationService.localModelPathDefaultsKey)
        self.privateAILoadState = .idle
        self.viewModel.resetVerification(for: PrivateAIProviderFeature.shared.providerID)

        Task { @MainActor in
            await PrivateAIIntegrationService.shared.unloadCachedRuntime(
                reason: "Fluid Intelligence backend changed to \(preference.displayName)"
            )
            guard self.privateAISelectedModelID == modelID else { return }
            let model = self.selectedPrivateAIModel
            if PrivateAIIntegrationService.isModelInstalled(model) {
                self.verifyPrivateAIConnection(model)
            } else {
                self.privateAILoadState = .idle
                self.viewModel.refreshProviderItems()
            }
        }
    }

    // MARK: - Expanded API provider (board 04b · states)

    private func providerDetailsSection(for item: ProviderItem) -> AnyView {
        let providerKey = self.viewModel.providerKey(for: item.id)
        let isCustom = !ModelRepository.shared.isBuiltIn(item.id)
        let baseURL = self.viewModel.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.viewModel.isLocalEndpoint(baseURL)
        let apiKeyValue = self.viewModel.providerAPIKey(for: item.id)
        let hasAPIKey = !apiKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let models = self.viewModel.availableModelsByProvider[providerKey] ?? []
        let hasModels = !models.isEmpty
        let isRefreshing = self.viewModel.isFetchingModels && self.viewModel.selectedProviderID == item.id
        let hasName = isCustom
            ? !(self.viewModel.savedProviders.first { $0.id == item.id }?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : true
        let canFetchModels = hasName && (isLocal ? !baseURL.isEmpty : (hasAPIKey && !baseURL.isEmpty))
        let canVerify = hasModels
            && !self.viewModel.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && canFetchModels
        let apiKeyBinding = Binding(
            get: { self.viewModel.providerAPIKey(for: item.id) },
            set: { self.viewModel.updateProviderAPIKey($0, for: item.id, persistEmptyValue: true) }
        )
        let nameBinding = Binding(
            get: { self.viewModel.savedProviders.first(where: { $0.id == item.id })?.name ?? "" },
            set: { newValue in
                self.viewModel.updateCustomProviderName(newValue, for: item.id)
            }
        )
        let baseURLBinding = Binding(
            get: { self.viewModel.savedProviders.first(where: { $0.id == item.id })?.baseURL ?? self.viewModel.openAIBaseURL },
            set: { newValue in
                self.viewModel.updateCustomProviderBaseURL(newValue, for: item.id)
            }
        )

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            if isCustom {
                AISettingRow(
                    title: "Provider name",
                    helper: "Auto-named Custom Provider, Custom Provider 2, … until you change it."
                ) {
                    TextField("Custom Provider", text: nameBinding)
                        .textFieldStyle(.plain)
                        .basicsProse(13)
                        .modifier(AIFieldChrome(width: 300))
                }

                AIHairline()

                AISettingRow(
                    title: "Base URL",
                    helper: "Any OpenAI-compatible endpoint, including one on this machine."
                ) {
                    TextField("https://api.yourprovider.com/v1", text: baseURLBinding)
                        .textFieldStyle(.plain)
                        .basicsMono(12)
                        .modifier(AIFieldChrome(width: 300))
                }

                AIHairline()
            }

            AISettingRow(
                title: "API key",
                helper: isCustom
                    ? "Optional for a local endpoint that does not check one."
                    : "Stored in your macOS Keychain, never in the app's own files."
            ) {
                HStack(spacing: 12) {
                    SecureField("Enter API key", text: apiKeyBinding)
                        .textFieldStyle(.plain)
                        .basicsMono(12)
                        .modifier(AIFieldChrome(width: 300))
                        .onTapGesture {
                            _ = self.viewModel.ensureKeychainAccessForAPIKeyEdit()
                        }

                    self.providerWebsiteLink(for: item.id)
                }
            }

            AIHairline()

            AISettingRow(
                title: "Model",
                helper: "Refresh pulls the live catalogue once a key is in."
            ) {
                HStack(spacing: 8) {
                    SearchableModelPicker(
                        models: models,
                        selectedModel: self.modelBinding(for: item.id),
                        selectionEnabled: hasModels,
                        controlWidth: 220,
                        controlHeight: AISettingsLayout.controlHeight
                    )

                    self.companionIconButton(
                        isRefreshing: isRefreshing,
                        disabled: isRefreshing || !canFetchModels,
                        opacity: canFetchModels ? 1 : 0.45,
                        help: "Refresh model list"
                    ) {
                        self.activateProvider(item.id)
                        Task { await self.viewModel.fetchModelsForCurrentProvider() }
                    }

                    self.reasoningButton(for: item.id)
                }
            }

            if self.viewModel.showingReasoningConfig, self.viewModel.selectedProviderID == item.id {
                AIHairline()

                self.reasoningConfigSection
                    .padding(.vertical, 14)
            }

            if let error = self.viewModel.fetchModelsError, !error.isEmpty {
                AIInlineNotice(
                    text: error,
                    systemImage: "exclamationmark.circle",
                    tone: BasicsTokens.Semantic.danger
                )
                .padding(.top, 14)
                .padding(.bottom, 4)
            }

            if self.viewModel.connectionStatus(for: item.id) == .failed,
               !self.viewModel.connectionErrorMessage(for: item.id).isEmpty
            {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(BasicsTokens.Semantic.danger)
                            .frame(width: 6, height: 6)
                        Text("Connection failed")
                            .basicsLabel(12)
                            .foregroundStyle(BasicsTokens.Semantic.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AIErrorLog(message: self.viewModel.connectionErrorMessage(for: item.id), lineLimit: 8)
                }
                .padding(.top, 14)
            }

            HStack(spacing: 16) {
                if canVerify {
                    Button {
                        Task { await self.viewModel.testAPIConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            if self.viewModel.isTestingConnection {
                                ProgressView()
                                    .controlSize(.mini)
                                    .fixedSize()
                            }
                            Text(self.viewModel.isTestingConnection ? "Verifying…" : "Verify connection")
                        }
                    }
                    .fluidButton(.accent, size: .small)
                    .disabled(self.viewModel.isTestingConnection)

                    Text("Sends one throwaway request to confirm the key and model actually answer.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AIInlineNotice(
                        text: hasModels
                            ? "Select a model to enable verification"
                            : "Refresh models to enable verification"
                    )
                }

                Spacer(minLength: 8)

                if isCustom {
                    Button(role: .destructive) {
                        self.viewModel.deleteCurrentProvider()
                        self.expandedProviderID = nil
                    } label: {
                        Text("Delete provider")
                    }
                    .fluidCompactButton(
                        size: .small,
                        foreground: BasicsTokens.Semantic.danger,
                        borderColor: BasicsTokens.Semantic.danger.opacity(0.5)
                    )
                }
            }
            .padding(.top, 16)
        })
    }

    /// "Get API key" / "Setup guide" — the provider's own page, when we know it.
    @ViewBuilder
    private func providerWebsiteLink(for providerID: String) -> some View {
        if let websiteInfo = ModelRepository.shared.providerWebsiteURL(for: providerID),
           let url = URL(string: websiteInfo.url)
        {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text(websiteInfo.label)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(PlainLinkButtonStyle(size: .small))
        }
    }

    private func startCustomProvider() {
        let name = self.uniqueCustomProviderName()
        if let providerID = self.viewModel.createDraftProvider(named: name) {
            self.expandedProviderID = providerID
        }
    }

    private func uniqueCustomProviderName() -> String {
        let base = "Custom Provider"
        let existing = Set(self.viewModel.savedProviders.map { $0.name.lowercased() })
        if !existing.contains(base.lowercased()) { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func providerBaseURL(for item: ProviderItem) -> String {
        if item.id == self.viewModel.selectedProviderID {
            return self.viewModel.openAIBaseURL
        }
        if let saved = self.viewModel.savedProviders.first(where: { $0.id == item.id }) {
            return saved.baseURL
        }
        if ModelRepository.shared.isBuiltIn(item.id) {
            return ModelRepository.shared.defaultBaseURL(for: item.id)
        }
        return ""
    }

    func selectProvider(_ providerID: String) {
        self.viewModel.selectProvider(providerID)
    }

    private func activateProvider(_ providerID: String) {
        self.viewModel.selectedProviderID = providerID
        self.viewModel.handleProviderChange(providerID)
        self.viewModel.connectionStatus = self.viewModel.connectionStatus(for: providerID)
    }

    private func modelBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: {
                let key = self.viewModel.providerKey(for: providerID)
                return self.viewModel.selectedModelByProvider[key] ?? ""
            },
            set: { newValue in
                self.viewModel.selectModel(newValue, for: providerID)
            }
        )
    }

    private func reasoningButton(for providerID: String) -> some View {
        let hasEnabledConfig = self.viewModel.isReasoningEnabled(for: providerID)

        return Button {
            self.activateProvider(providerID)
            self.viewModel.openReasoningConfig()
        } label: {
            Image(systemName: hasEnabledConfig ? "brain.fill" : "brain")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(SquareIconButtonStyle(
            foreground: hasEnabledConfig ? self.theme.palette.accent : nil,
            borderColor: hasEnabledConfig ? self.theme.palette.accent.opacity(0.5) : nil
        ))
        .help("Configure reasoning parameters")
    }

    // MARK: - Advanced prompts tab

    var promptsStepContent: some View {
        self.advancedSettingsCard
    }

    // MARK: - Edit provider panels

    func privateAIEditProviderSection(
        model: PrivateAIRegisteredModel,
        isInstalled: Bool,
        isBusy: Bool,
        isVerified: Bool
    ) -> some View {
        let canDelete = isInstalled && PrivateAIIntegrationService.canRemoveInstalledModel(model)

        return VStack(alignment: .leading, spacing: 0) {
            Text("Edit provider")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)
                .padding(.bottom, 4)

            AISettingRow(title: "Model", isDimmed: isBusy) {
                SearchableModelPicker(
                    models: PrivateAIModelRegistry.modelIDs(),
                    selectedModel: self.privateAIModelBinding,
                    selectionEnabled: !isBusy,
                    controlWidth: 260,
                    controlHeight: AISettingsLayout.controlHeight
                )
            }

            AIHairline()

            AISettingRow(title: "Backend", isDimmed: isBusy) {
                self.privateAIBackendPicker(isBusy: isBusy)
                    .frame(width: 260)
            }

            AIHairline()

            AISettingRow(
                title: "Dictation window",
                helper: "\(self.privateAIContextCueText). Higher values help long transcripts but use more RAM.",
                isDimmed: isBusy
            ) {
                self.privateAIContextControl(isBusy: isBusy)
            }

            AIHairline()

            AISettingRow(
                title: "Faster first result",
                helper: "Keeps Fluid-1 ready so your first dictation finishes sooner."
            ) {
                Toggle("", isOn: self.privateAIPrefixCacheBinding)
                    .toggleStyle(GlassToggleStyle())
                    .labelsHidden()
                    .disabled(isBusy)
                    .accessibilityLabel("Faster first result")
            }

            if self.privateAIShowsBoostRow {
                AIHairline()

                AISettingRow(
                    title: "Faster results",
                    helper: "Finishes dictation up to 15% faster. Uses about 100 MB more memory."
                ) {
                    Toggle("", isOn: self.privateAIBoostBinding)
                        .toggleStyle(GlassToggleStyle())
                        .labelsHidden()
                        .disabled(isBusy)
                        .accessibilityLabel("Faster results")
                }
            }

            HStack(spacing: 10) {
                if isVerified {
                    Button {
                        self.resetPrivateAIVerification(for: model)
                        self.viewModel.clearEditProviderDraft()
                    } label: {
                        Text("Reset verification")
                    }
                    .fluidCompactButton(size: .small)
                }

                if canDelete {
                    Button(role: .destructive) {
                        self.deletePrivateAIModel(model)
                        self.viewModel.clearEditProviderDraft()
                    } label: {
                        Text("Delete model")
                    }
                    .fluidCompactButton(
                        size: .small,
                        foreground: BasicsTokens.Semantic.danger,
                        borderColor: BasicsTokens.Semantic.danger.opacity(0.5)
                    )
                    .disabled(isBusy)
                }

                Spacer(minLength: 0)

                Button {
                    self.viewModel.clearEditProviderDraft()
                } label: {
                    Text("Done")
                }
                .fluidButton(.accent, size: .small)
            }
            .padding(.top, 16)
        }
        .opacity(isBusy ? 0.5 : 1)
        .disabled(isBusy)
    }

    private func privateAIContextControl(isBusy: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        return HStack(spacing: 10) {
            Text(self.settings.privateAIContextTokenLimit.formatted())
                .basicsMono(13)
                .foregroundStyle(self.theme.palette.primaryText)
            Text("tokens")
                .basicsProse(12)
                .foregroundStyle(self.theme.palette.secondaryText)

            HStack(spacing: 0) {
                Button {
                    self.decreasePrivateAIContextTokenLimit()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: AISettingsLayout.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || self.settings.privateAIContextTokenLimit <= SettingsStore.privateAIContextTokenLimitRange.lowerBound)

                Rectangle()
                    .fill(self.theme.palette.cardBorder)
                    .frame(width: 1, height: AISettingsLayout.controlHeight)

                Button {
                    self.increasePrivateAIContextTokenLimit()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: AISettingsLayout.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || self.settings.privateAIContextTokenLimit >= SettingsStore.privateAIContextTokenLimitRange.upperBound)
            }
            .foregroundStyle(self.theme.palette.primaryText)
            .background(shape.fill(self.theme.palette.cardBackground))
            .overlay(shape.stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1))
            .clipShape(shape)
            .fixedSize()
        }
        .help("How much raw dictation Fluid-1 can clean at once. Higher values help long transcripts but use more RAM and can slow first response.")
    }

    private func decreasePrivateAIContextTokenLimit() {
        self.privateAIContextTokenLimitBinding.wrappedValue = self.settings.privateAIContextTokenLimit - SettingsStore.privateAIContextTokenLimitStep
    }

    private func increasePrivateAIContextTokenLimit() {
        self.privateAIContextTokenLimitBinding.wrappedValue = self.settings.privateAIContextTokenLimit + SettingsStore.privateAIContextTokenLimitStep
    }

    private var privateAIContextCueText: String {
        let estimatedWords = SettingsStore.estimatedPrivateAIDictationWords(for: self.settings.privateAIContextTokenLimit)
        let estimatedMinutes = max(1, Int((Double(estimatedWords) / 150.0).rounded()))
        let minuteText = estimatedMinutes == 1 ? "1 minute" : "\(estimatedMinutes) minutes"
        return "Good for about \(estimatedWords.formatted()) words or \(minuteText) of dictation"
    }

    /// Board 04b · states — "Panel · Edit provider". Opens inline under a
    /// verified row; built-in shows the key only, custom adds name and base URL.
    var editProviderSection: some View {
        let isBuiltIn = ModelRepository.shared.isBuiltIn(self.viewModel.selectedProviderID)
        let apiKeyBinding = Binding(
            get: { self.viewModel.editProviderApiKey },
            set: { self.viewModel.editProviderApiKey = $0 }
        )
        let isVerified = self.viewModel.connectionStatus(for: self.viewModel.selectedProviderID) == .success
        let isSaveDisabled = !isBuiltIn &&
            (self.viewModel.editProviderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                self.viewModel.editProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        return VStack(alignment: .leading, spacing: 0) {
            Text("Edit provider")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)
                .padding(.bottom, 4)

            if !isBuiltIn {
                AISettingRow(title: "Name") {
                    TextField("Provider name", text: self.$viewModel.editProviderName)
                        .textFieldStyle(.plain)
                        .basicsProse(13)
                        .modifier(AIFieldChrome(width: 300))
                }

                AIHairline()

                AISettingRow(title: "Base URL") {
                    TextField("e.g., http://localhost:11434/v1", text: self.$viewModel.editProviderBaseURL)
                        .textFieldStyle(.plain)
                        .basicsMono(12)
                        .modifier(AIFieldChrome(width: 300))
                }

                AIHairline()
            }

            AISettingRow(title: "API key") {
                HStack(spacing: 12) {
                    SecureField("Enter API key", text: apiKeyBinding)
                        .textFieldStyle(.plain)
                        .basicsMono(12)
                        .modifier(AIFieldChrome(width: 300))
                        .onTapGesture {
                            _ = self.viewModel.ensureKeychainAccessForAPIKeyEdit()
                        }

                    self.providerWebsiteLink(for: self.viewModel.selectedProviderID)
                }
            }

            HStack(spacing: 10) {
                Button {
                    guard self.viewModel.saveEditedProviderAPIKey() else { return }
                    if !isBuiltIn {
                        self.viewModel.saveEditedProvider()
                    } else {
                        self.viewModel.clearEditProviderDraft()
                    }
                } label: {
                    Text("Save")
                }
                .fluidButton(.accent, size: .small)
                .disabled(isSaveDisabled)

                Button {
                    self.viewModel.clearEditProviderDraft()
                } label: {
                    Text("Cancel")
                }
                .fluidCompactButton(size: .small)

                Spacer(minLength: 8)

                if isVerified {
                    Button {
                        self.viewModel.resetVerification(for: self.viewModel.selectedProviderID)
                        self.viewModel.clearEditProviderDraft()
                    } label: {
                        Text("Reset verification")
                    }
                    .fluidCompactButton(size: .small)
                }

                if !isBuiltIn {
                    Button(role: .destructive) {
                        self.viewModel.deleteCurrentProvider()
                        self.viewModel.clearEditProviderDraft()
                        self.expandedProviderID = nil
                    } label: {
                        Text("Delete provider")
                    }
                    .fluidCompactButton(
                        size: .small,
                        foreground: BasicsTokens.Semantic.danger,
                        borderColor: BasicsTokens.Semantic.danger.opacity(0.5)
                    )
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Reasoning (board 04d · popover · reasoning for a model)

    var reasoningConfigSection: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
        let parameterBinding = Binding(
            get: { () -> String in
                if self.viewModel.editingReasoningParamName == "reasoning_effort" {
                    return "reasoning_effort"
                } else if self.viewModel.editingReasoningParamName == "enable_thinking" {
                    return "enable_thinking"
                } else {
                    return "custom"
                }
            },
            set: { newValue in
                if newValue == "custom" {
                    if self.viewModel.editingReasoningParamName == "reasoning_effort" ||
                        self.viewModel.editingReasoningParamName == "enable_thinking"
                    {
                        self.viewModel.editingReasoningParamName = ""
                    }
                } else {
                    self.viewModel.editingReasoningParamName = newValue
                    if newValue == "reasoning_effort",
                       !["none", "minimal", "low", "medium", "high"].contains(self.viewModel.editingReasoningParamValue)
                    {
                        self.viewModel.editingReasoningParamValue = "low"
                    } else if newValue == "enable_thinking",
                              !["true", "false"].contains(self.viewModel.editingReasoningParamValue)
                    {
                        self.viewModel.editingReasoningParamValue = "true"
                    }
                }
            }
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Reasoning for \(self.viewModel.selectedModel)")
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Button {
                    self.viewModel.showingReasoningConfig = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            HStack(spacing: 12) {
                Text(self.viewModel.editingReasoningEnabled ? "Enabled" : "Disabled")
                    .basicsLabel(13)
                    .foregroundStyle(self.viewModel.editingReasoningEnabled
                        ? self.theme.palette.accent
                        : self.theme.palette.secondaryText)

                Spacer(minLength: 8)

                Toggle("", isOn: self.$viewModel.editingReasoningEnabled)
                    .toggleStyle(GlassToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel("Reasoning enabled")
            }

            if self.viewModel.editingReasoningEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parameter")
                            .basicsMicroLabel(11)
                            .foregroundStyle(self.theme.palette.secondaryText)

                        Picker("", selection: parameterBinding) {
                            Text("reasoning_effort").tag("reasoning_effort")
                            Text("enable_thinking").tag("enable_thinking")
                            Text("Custom…").tag("custom")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    if self.viewModel.editingReasoningParamName != "reasoning_effort",
                       self.viewModel.editingReasoningParamName != "enable_thinking"
                    {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .basicsMicroLabel(11)
                                .foregroundStyle(self.theme.palette.secondaryText)

                            TextField("e.g., thinking_budget", text: self.$viewModel.editingReasoningParamName)
                                .textFieldStyle(.plain)
                                .basicsMono(12)
                                .modifier(AIFieldChrome(width: 240))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Value")
                            .basicsMicroLabel(11)
                            .foregroundStyle(self.theme.palette.secondaryText)

                        if self.viewModel.editingReasoningParamName == "reasoning_effort" {
                            Picker("", selection: self.$viewModel.editingReasoningParamValue) {
                                Text("none").tag("none")
                                Text("minimal").tag("minimal")
                                Text("low").tag("low")
                                Text("medium").tag("medium")
                                Text("high").tag("high")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 240)

                            Text("none · minimal · low · medium · high")
                                .basicsMono(11)
                                .foregroundStyle(self.theme.palette.tertiaryText)
                        } else if self.viewModel.editingReasoningParamName == "enable_thinking" {
                            Picker("", selection: self.$viewModel.editingReasoningParamValue) {
                                Text("true").tag("true")
                                Text("false").tag("false")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 240)

                            Text("true · false")
                                .basicsMono(11)
                                .foregroundStyle(self.theme.palette.tertiaryText)
                        } else {
                            TextField("value", text: self.$viewModel.editingReasoningParamValue)
                                .textFieldStyle(.plain)
                                .basicsMono(12)
                                .modifier(AIFieldChrome(width: 240))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button {
                    self.viewModel.showingReasoningConfig = false
                } label: {
                    Text("Cancel")
                }
                .fluidCompactButton(size: .small)

                Button {
                    self.saveReasoningConfig()
                } label: {
                    Text("Save")
                }
                .fluidButton(.accent, size: .small)
            }
        }
        .padding(16)
        .frame(maxWidth: 380, alignment: .leading)
        .background(shape.fill(self.theme.palette.cardBackground))
        .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
        .basicsShadows([
            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.04), radius: 1, y: 1),
            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 12, y: 8),
        ])
        .transition(.opacity)
    }

    func saveReasoningConfig() {
        self.viewModel.saveReasoningConfig()
    }
}

// MARK: - Field chrome

/// The plain text/secure field as the board draws it: white, one hairline,
/// radius 6, 32 tall. Not `.roundedBorder` — that is an AppKit bezel.
struct AIFieldChrome: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let width: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        content
            .foregroundStyle(self.theme.palette.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: self.width == nil ? .infinity : nil, alignment: .leading)
            .frame(width: self.width, height: 32)
            .background(shape.fill(self.theme.palette.cardBackground))
            .overlay(shape.stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1))
    }
}
