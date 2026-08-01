//
//  SearchableModelPicker.swift
//  Fluid
//
//  A searchable picker for selecting AI models.
//  Uses a popover with search field for better UX.
//

import SwiftUI

struct SearchableModelPicker: View {
    @Environment(\.theme) private var theme
    let models: [String]
    @Binding var selectedModel: String
    var onRefresh: (() async -> Void)?
    var isRefreshing: Bool = false
    var refreshEnabled: Bool = true
    var selectionEnabled: Bool = true
    let controlWidth: CGFloat
    let controlHeight: CGFloat?

    init(
        models: [String],
        selectedModel: Binding<String>,
        onRefresh: (() async -> Void)? = nil,
        isRefreshing: Bool = false,
        refreshEnabled: Bool = true,
        selectionEnabled: Bool = true,
        controlWidth: CGFloat = 180,
        controlHeight: CGFloat? = nil
    ) {
        self.models = models
        self._selectedModel = selectedModel
        self.onRefresh = onRefresh
        self.isRefreshing = isRefreshing
        self.refreshEnabled = refreshEnabled
        self.selectionEnabled = selectionEnabled
        self.controlWidth = controlWidth
        self.controlHeight = controlHeight
    }

    @State private var searchText = ""
    @State private var isShowingPopover = false

    private var refreshButtonSize: CGFloat {
        self.controlHeight ?? 24
    }

    private var pickerControlWidth: CGFloat? {
        guard self.onRefresh != nil, self.controlHeight != nil else {
            return self.controlWidth
        }
        return max(self.controlWidth - self.refreshButtonSize - 8, 80)
    }

    private var filteredModels: [String] {
        if self.searchText.isEmpty {
            return self.models
        }
        return self.models.filter { $0.localizedCaseInsensitiveContains(self.searchText) }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Model button that opens popover
            Button(action: { self.isShowingPopover.toggle() }) {
                HStack(spacing: 10) {
                    Group {
                        if self.selectedModel.isEmpty {
                            Text("Select model")
                                .basicsProse(13)
                                .foregroundStyle(self.theme.palette.tertiaryText)
                        } else {
                            // A model id is an identifier, not prose — mono.
                            Text(self.selectedModel)
                                .basicsMono(12)
                                .foregroundStyle(self.theme.palette.primaryText)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)

                    Spacer(minLength: 6)
                    FluidPickerDisclosureIcon(backgroundOpacity: 0.6)
                }
                .searchablePickerControlChrome(
                    width: self.pickerControlWidth,
                    height: self.controlHeight,
                    usesMaterial: true,
                    showsShadow: true
                )
            }
            .buttonStyle(.plain)
            .disabled(!self.selectionEnabled)
            .opacity(self.selectionEnabled ? 1 : 0.55)
            .popover(isPresented: self.$isShowingPopover, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        TextField("Search models…", text: self.$searchText)
                            .textFieldStyle(.plain)
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.primaryText)

                        if self.isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                                .fixedSize()
                        }
                    }
                    .searchablePickerSearchFieldChrome()

                    Divider().hidden()

                    VStack(spacing: 0) {
                        if self.models.isEmpty {
                            VStack(spacing: 5) {
                                Text("No models")
                                    .basicsLabel(13)
                                    .foregroundStyle(self.theme.palette.secondaryText)
                                Text("Click refresh to fetch from API")
                                    .basicsProse(12)
                                    .foregroundStyle(self.theme.palette.tertiaryText)
                            }
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    if self.filteredModels.isEmpty {
                                        Text("No models match “\(self.searchText)”")
                                            .basicsProse(12)
                                            .foregroundStyle(self.theme.palette.secondaryText)
                                            .padding(14)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        ForEach(self.filteredModels.prefix(100), id: \.self) { model in
                                            Button(action: {
                                                self.selectedModel = model
                                                self.searchText = ""
                                                self.isShowingPopover = false
                                            }) {
                                                HStack(spacing: 8) {
                                                    if model == self.selectedModel {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .semibold))
                                                            .foregroundStyle(self.theme.palette.accent)
                                                            .frame(width: 12)
                                                    } else {
                                                        Color.clear.frame(width: 12, height: 1)
                                                    }

                                                    Text(model)
                                                        .basicsMono(12)
                                                        .foregroundStyle(self.theme.palette.primaryText)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)

                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .searchablePickerSelectedRowBackground(isSelected: model == self.selectedModel)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 250)

                            if self.filteredModels.count > 100 {
                                Divider().hidden()
                                Text("\(self.filteredModels.count - 100) more (use search)")
                                    .basicsProse(12)
                                    .foregroundStyle(self.theme.palette.tertiaryText)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .id(self.searchText.isEmpty)
                }
                .frame(width: 280)
            }

            // Refresh button
            if let onRefresh = onRefresh {
                if self.controlHeight == nil {
                    Button(action: {
                        Task { await onRefresh() }
                    }) {
                        if self.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(self.isRefreshing || !self.refreshEnabled)
                    .opacity(self.refreshEnabled ? 1 : 0.45)
                    .help("Refresh model list")
                } else {
                    Button(action: {
                        Task { await onRefresh() }
                    }) {
                        ZStack {
                            if self.isRefreshing {
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
                    .disabled(self.isRefreshing || !self.refreshEnabled)
                    .opacity(self.refreshEnabled ? 1 : 0.45)
                    .help("Refresh model list")
                }
            }
        }
    }
}

#Preview {
    SearchableModelPicker(
        models: ["gpt-4.1", "gpt-4o", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet"],
        selectedModel: .constant("gpt-4.1"),
        onRefresh: { try? await Task.sleep(nanoseconds: 1_000_000_000) },
        isRefreshing: false
    )
    .padding()
}
