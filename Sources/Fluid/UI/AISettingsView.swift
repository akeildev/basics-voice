//
//  AISettingsView.swift
//  fluid
//
//  Extracted from ContentView.swift to reduce monolithic architecture.
//  Created: 2025-12-14
//

import SwiftUI

// MARK: - Connection Status Enum

enum AIConnectionStatus {
    case unknown, testing, success, failed
}

enum PromptEditorMode: Identifiable, Equatable {
    case defaultPrompt(mode: SettingsStore.PromptMode)
    case newPrompt(prefillMode: SettingsStore.PromptMode)
    case edit(promptID: String)
    case privateAI

    var id: String {
        switch self {
        case let .defaultPrompt(mode): return "default:\(mode.rawValue)"
        case let .newPrompt(prefillMode): return "new:\(prefillMode.rawValue)"
        case let .edit(promptID): return "edit:\(promptID)"
        case .privateAI: return "privateAI"
        }
    }

    var isDefault: Bool {
        if case .defaultPrompt = self { return true }
        return false
    }

    var isPrivateAI: Bool {
        if case .privateAI = self { return true }
        return false
    }

    var editingPromptID: String? {
        if case let .edit(promptID) = self { return promptID }
        return nil
    }

    var isNewPrompt: Bool {
        if case .newPrompt = self { return true }
        return false
    }

    var mode: SettingsStore.PromptMode? {
        switch self {
        case let .defaultPrompt(mode): return mode
        case let .newPrompt(prefillMode): return prefillMode
        case .edit: return nil
        case .privateAI: return .dictate
        }
    }
}

enum ModelSortOption: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case accuracy = "Accuracy"
    case speed = "Speed"

    var id: String { self.rawValue }
}

enum SpeechProviderFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case nvidia = "NVIDIA"
    case apple = "Apple"
    case cohere = "Cohere"
    case openai = "OpenAI"

    var id: String { self.rawValue }
}

/// Board "04b/04c/04d — AI enhancements". Every number here is read off the
/// boards rather than guessed: rows are 62 tall, list rows 46, controls 30, and
/// the settings rows inside an expanded provider breathe at 18 above and below.
enum AISettingsLayout {
    static let labelWidth: CGFloat = 110
    static let pickerWidth: CGFloat = 220
    /// Every inline control on the board — pickers, icon buttons, menus.
    static let controlHeight: CGFloat = 30
    static let providerRowControlHeight: CGFloat = 30
    static let actionMinWidth: CGFloat = 120
    static let compactActionMinWidth: CGFloat = 96
    static let wideActionMinWidth: CGFloat = 140
    static let primaryActionMinWidth: CGFloat = 150
    static let promptActionMinWidth: CGFloat = 90
    static let promptModeMinHeight: CGFloat = 260
    static let promptInlinePickerWidth: CGFloat = 145
    static let promptInlineModelWidth: CGFloat = 180
    static let promptEditorLabelColumnWidth: CGFloat = 200
    static let promptEditorControlColumnWidth: CGFloat = 270
    static let rowLeadingIndent: CGFloat = labelWidth + 12

    /// The lane the status reading occupies on every collapsed provider row, so
    /// "Connection not tested" and "Connection failed" start at the same x.
    static let providerStatusLaneWidth: CGFloat = 180
    /// Card interior gutter — list rows, expanded panels and empty states share it.
    static let cardGutter: CGFloat = 16
    /// Vertical breathing room around one settings row inside an expanded card.
    static let settingRowPadding: CGFloat = 18
    /// Gap between a row's label block and its control lane.
    static let settingRowGap: CGFloat = 20
    static let rowHeight: CGFloat = 62
    static let listRowHeight: CGFloat = 46
    static let promptCardHeight: CGFloat = 74
}

// MARK: - Basics building blocks (board 04b/04c/04d)

/// The uppercase eyebrow that opens every section, with the live count in mono
/// beside it and an optional action pinned to the right.
struct AISectionHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let count: Int?
    let trailing: () -> Trailing

    init(title: String, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(self.title)
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.secondaryText)

                if let count = self.count {
                    Text("(\(count))")
                        .basicsMono(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }

            Spacer(minLength: 12)

            self.trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AISectionHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count, trailing: { EmptyView() })
    }
}

/// The 1px hairline that does all the separating inside a card.
struct AIHairline: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(self.theme.palette.cardBorder)
            .frame(height: 1)
    }
}

/// White card, 1px hairline, radius 10, clipped so hairline-divided rows meet
/// the edge cleanly. The container for every list on these boards.
struct AIListCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let isEmphasized: Bool
    let content: () -> Content

    init(isEmphasized: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.isEmphasized = isEmphasized
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        VStack(spacing: 0) {
            self.content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(self.theme.palette.cardBackground))
        .overlay(
            shape.stroke(
                self.isEmphasized ? self.theme.palette.accent : self.theme.palette.cardBorder,
                lineWidth: self.isEmphasized ? 2 : 1
            )
        )
        .clipShape(shape)
    }
}

/// A dashed empty-state well — first run, no search matches, no overrides yet.
struct AIEmptyWell<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)

        VStack(spacing: 4) {
            self.content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, AISettingsLayout.cardGutter)
        .background(
            shape.strokeBorder(
                BasicsBorder.strong(self.theme, self.colorScheme),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
        )
    }
}

/// One settings row inside an expanded provider card: label + prose helper on
/// the left, controls right-aligned in their own lane.
struct AISettingRow<Control: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let helper: String?
    let isDimmed: Bool
    let control: () -> Control

    init(
        title: String,
        helper: String? = nil,
        isDimmed: Bool = false,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.helper = helper
        self.isDimmed = isDimmed
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: AISettingsLayout.settingRowGap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)

                if let helper = self.helper, !helper.isEmpty {
                    Text(helper)
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.control()
                .fixedSize(horizontal: true, vertical: false)
        }
        .opacity(self.isDimmed ? 0.5 : 1)
        .padding(.vertical, AISettingsLayout.settingRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum AIChipTone {
    /// Brand fill, white ink — the one green moment on a row.
    case brand
    /// Muted fill, muted ink — the neutral metadata chip.
    case neutral
    /// brandSoft fill, brand ink — a live shortcut.
    case soft
    /// Dashed outline, faint ink — an unfilled slot.
    case ghost
}

/// 19px pill. Board § chips.
struct AIChip: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var systemImage: String? = nil
    var tone: AIChipTone = .neutral
    var isMono: Bool = false
    var isUppercase: Bool = false

    private var ink: Color {
        switch self.tone {
        case .brand: return .white
        case .neutral: return self.theme.palette.secondaryText
        case .soft: return self.theme.palette.accent
        case .ghost: return self.theme.palette.tertiaryText
        }
    }

    private var fill: Color {
        switch self.tone {
        case .brand: return self.theme.palette.accent
        case .neutral: return self.theme.palette.sidebarBackground
        case .soft: return self.theme.palette.accent.opacity(0.10)
        case .ghost: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }

            Group {
                if self.isUppercase {
                    Text(self.text).basicsMicroLabel(10)
                } else if self.isMono {
                    Text(self.text).basicsMono(11)
                } else {
                    Text(self.text).basicsLabel(11)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .foregroundStyle(self.ink)
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Capsule(style: .continuous).fill(self.fill))
        .overlay {
            if self.tone == .ghost {
                Capsule(style: .continuous)
                    .strokeBorder(
                        BasicsBorder.strong(self.theme, self.colorScheme),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The connection reading on a provider row: a dot (or a spinner) plus a label
/// in the shared status lane, so every row's reading starts at the same x.
struct AIStatusReading: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let status: AIConnectionStatus

    private var text: String {
        switch self.status {
        case .success: return "Connection verified"
        case .failed: return "Connection failed"
        case .testing: return "Verifying…"
        case .unknown: return "Connection not tested"
        }
    }

    private var tone: Color {
        switch self.status {
        case .success: return self.theme.palette.accent
        case .failed: return BasicsTokens.Semantic.danger
        case .testing: return BasicsTokens.Semantic.warning
        case .unknown: return self.theme.palette.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            if self.status == .testing {
                ProgressView()
                    .controlSize(.mini)
                    .fixedSize()
            } else {
                Circle()
                    .fill(self.status == .unknown
                        ? BasicsBorder.strong(self.theme, self.colorScheme)
                        : self.tone)
                    .frame(width: 6, height: 6)
            }

            Text(self.text)
                .basicsLabel(12)
                .foregroundStyle(self.tone)
                .lineLimit(1)
        }
        .frame(width: AISettingsLayout.providerStatusLaneWidth, alignment: .trailing)
    }
}

/// A mono error block on the muted ground — the failed-connection log.
struct AIErrorLog: View {
    @Environment(\.theme) private var theme
    let message: String
    var lineLimit: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)

        Text(self.message)
            .basicsMono(11)
            .foregroundStyle(self.theme.palette.secondaryText)
            .lineSpacing(3)
            .lineLimit(self.lineLimit)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(shape.fill(self.theme.palette.sidebarBackground))
            .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
    }
}

/// A one-line inline notice: icon + sentence, tone-coloured.
struct AIInlineNotice: View {
    @Environment(\.theme) private var theme
    let text: String
    var systemImage: String = "info.circle"
    var tone: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: self.systemImage)
                .font(.system(size: 12, weight: .medium))
            Text(self.text)
                .basicsProse(13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(self.tone ?? self.theme.palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Masks a provider secret the way the board draws it — enough of the prefix to
/// recognise the vendor, the last four to recognise the key, dots between.
enum AIProviderSecretFormatter {
    static func masked(_ secret: String) -> String? {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > 8 else { return String(repeating: "•", count: trimmed.count) }
        let prefixLength = min(7, trimmed.count - 8)
        let prefix = String(trimmed.prefix(prefixLength))
        let suffix = String(trimmed.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}

struct AISettingsView: View {
    let appServices: AppServices
    let menuBarManager: MenuBarManager
    let theme: AppTheme

    @StateObject private var voiceViewModel: VoiceEngineSettingsViewModel
    @StateObject private var enhancementViewModel: AIEnhancementSettingsViewModel

    init(appServices: AppServices, menuBarManager: MenuBarManager, theme: AppTheme) {
        self.appServices = appServices
        self.menuBarManager = menuBarManager
        self.theme = theme
        _voiceViewModel = StateObject(wrappedValue: VoiceEngineSettingsViewModel(
            settings: SettingsStore.shared,
            appServices: appServices
        ))
        _enhancementViewModel = StateObject(wrappedValue: AIEnhancementSettingsViewModel(
            settings: SettingsStore.shared,
            menuBarManager: menuBarManager,
            promptTest: DictationPromptTestCoordinator.shared
        ))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VoiceEngineSettingsView(
                    viewModel: self.voiceViewModel,
                    settings: self.voiceViewModel.settings,
                    theme: self.theme
                )
                AIEnhancementSettingsView(
                    viewModel: self.enhancementViewModel,
                    settings: self.enhancementViewModel.settings,
                    promptTest: self.enhancementViewModel.promptTest,
                    theme: self.theme,
                    activeShortcutRecordingTarget: .constant(nil),
                    shortcutRecordingMessage: .constant(nil)
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.windowBackground)
    }
}
