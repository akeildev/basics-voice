import AppKit
import SwiftUI

// MARK: - Shared "mode page" primitives
//
// Boards `03 — Send to Instinct` and `14 — Tasks` share one page skeleton:
// eyebrow + title + prose lede, a shortcut hero card, then hairline-separated
// setting rows on the surface. These primitives are the skeleton; both pages
// use them so the two screens cannot drift apart.

/// Eyebrow (brand micro-label) + title + prose lede.
struct ModePageHeader: View {
    @Environment(\.theme) private var theme

    let eyebrow: String
    let title: String
    let lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.eyebrow)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text(self.title)
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Text(self.lede)
                .basicsProse(15)
                .lineSpacing(15 * 0.6)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 700, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 78×78 key tile from both boards — a mono glyph on a raised card.
struct ModeKeyTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let glyph: String
    /// Recording capture paints the tile brand-soft; a conflict paints it danger.
    var tone: Tone = .rest

    enum Tone {
        case rest
        case capturing
        case conflict
    }

    private var fill: Color {
        switch self.tone {
        case .rest: return self.theme.palette.cardBackground
        case .capturing: return BasicsTokens.Semantic.brandSoft
        case .conflict: return self.theme.palette.cardBackground
        }
    }

    private var border: Color {
        switch self.tone {
        case .rest: return BasicsBorder.strong(self.theme, self.colorScheme)
        case .capturing: return self.theme.palette.accent.opacity(0.45)
        case .conflict: return BasicsTokens.Semantic.danger.opacity(0.55)
        }
    }

    private var ink: Color {
        switch self.tone {
        case .rest: return self.theme.palette.primaryText
        case .capturing: return self.theme.palette.accent
        case .conflict: return BasicsTokens.Semantic.danger
        }
    }

    /// The board sets 34pt for a single character and 28pt for a chord; long
    /// chords ("Right ⌥ + Space") have to come down further or they clip.
    private var glyphSize: CGFloat {
        switch self.glyph.count {
        case 0 ... 1: return 32
        case 2 ... 3: return 26
        case 4 ... 6: return 18
        default: return 13
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(self.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(self.border, lineWidth: 1)
            )
            .basicsShadows([BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.08), radius: 7, y: 4)])
            .frame(width: 78, height: 78)
            .overlay {
                Text(self.glyph)
                    .basicsMono(self.glyphSize, weight: .medium)
                    .foregroundStyle(self.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(6)
            }
    }
}

/// Board § shortcut hero — key tile, eyebrow/value/helper stack, trailing lane.
struct ModeShortcutHero<Trailing: View>: View {
    @Environment(\.theme) private var theme

    let eyebrow: String
    let value: String
    let helper: String
    let tone: ModeKeyTile.Tone
    let glyph: String
    private let trailing: Trailing

    init(
        eyebrow: String,
        glyph: String,
        value: String,
        helper: String,
        tone: ModeKeyTile.Tone = .rest,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.glyph = glyph
        self.value = value
        self.helper = helper
        self.tone = tone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            ModeKeyTile(glyph: self.glyph, tone: self.tone)

            VStack(alignment: .leading, spacing: 6) {
                Text(self.eyebrow)
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                Text(self.value)
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text(self.helper)
                    .basicsProse(14)
                    .lineSpacing(14 * 0.6)
                    .foregroundStyle(
                        self.tone == .conflict
                            ? BasicsTokens.Semantic.danger
                            : self.theme.palette.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.trailing
                .layoutPriority(1)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(self.theme.palette.contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(self.theme.palette.separator, lineWidth: 1)
                )
        )
    }
}

/// A 1px hairline in the page separator colour.
struct ModeHairline: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(self.theme.palette.separator)
            .frame(height: 1)
    }
}

/// Micro-label eyebrow with an optional trailing chip, then content.
struct ModeSection<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let chip: String?
    private let trailingMono: String?
    private let content: Content

    init(
        title: String,
        chip: String? = nil,
        trailingMono: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.chip = chip
        self.trailingMono = trailingMono
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(self.title)
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)

                if let chip = self.chip {
                    Text(chip)
                        .basicsMicroLabel(10)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 19)
                        .background(Capsule().fill(BasicsTokens.Surface.muted))
                }

                Spacer(minLength: 12)

                if let trailingMono = self.trailingMono {
                    Text(trailingMono)
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label lane (title + optional status chip + helper) plus a control lane,
/// with the row's own top hairline. The board's ordinary setting row.
struct ModeSettingRow<Control: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let helper: String?
    private let chip: ModeStatusChip.Model?
    private let control: Control

    init(
        title: String,
        helper: String? = nil,
        chip: ModeStatusChip.Model? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.helper = helper
        self.chip = chip
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(self.title)
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if let chip = self.chip {
                        ModeStatusChip(model: chip)
                    }
                }
                if let helper = self.helper {
                    Text(helper)
                        .basicsProse(14)
                        .lineSpacing(14 * 0.6)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.control
                .layoutPriority(1)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { ModeHairline() }
    }
}

/// Board § chip — a dot plus an uppercase micro-label in brandSoft or muted.
struct ModeStatusChip: View {
    @Environment(\.theme) private var theme

    struct Model {
        let text: String
        let tone: Tone
    }

    enum Tone {
        case brand
        case muted
        case warning
    }

    let model: Model

    private var ink: Color {
        switch self.model.tone {
        case .brand: return self.theme.palette.accent
        case .muted: return self.theme.palette.secondaryText
        case .warning: return self.theme.palette.warning
        }
    }

    private var fill: Color {
        switch self.model.tone {
        case .brand: return BasicsTokens.Semantic.brandSoft
        case .muted: return BasicsTokens.Surface.muted
        case .warning: return self.theme.palette.warning.opacity(0.12)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(self.ink)
                .frame(width: 5, height: 5)
            Text(self.model.text)
                .basicsMicroLabel(10)
                .foregroundStyle(self.ink)
        }
        .padding(.horizontal, 8)
        .frame(height: 19)
        .background(Capsule().fill(self.fill))
    }
}

/// A read-only mono value chip — the board's value lane for ids and endpoints.
struct ModeValueChip: View {
    @Environment(\.theme) private var theme

    let text: String
    var isMuted: Bool = false

    var body: some View {
        Text(self.text)
            .basicsMono(12)
            .foregroundStyle(self.isMuted ? self.theme.palette.tertiaryText : self.theme.palette.primaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BasicsTokens.Surface.muted)
            )
            .frame(maxWidth: 320, alignment: .trailing)
    }
}

/// Board § toggle. 44 × 26 pill, brand when on, borderStrong when off.
struct ModeToggle: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            self.isOn.toggle()
        } label: {
            Capsule()
                .fill(
                    self.isOn
                        ? self.theme.palette.accent
                        : BasicsBorder.strong(self.theme, self.colorScheme)
                )
                .frame(width: 44, height: 26)
                .overlay(alignment: self.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .opacity(self.isEnabled ? 1 : 0.45)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.isOn ? "On" : "Off")
        .animation(.easeOut(duration: 0.16), value: self.isOn)
    }
}

// MARK: - Shortcut hero state

/// The four hero variants board `14b — Tasks · states` enumerates, derived from
/// the real capture state rather than a local flag.
enum ModeShortcutHeroState {
    case notSet
    case listening
    case conflict(String)
    case set(HotkeyShortcut, enabled: Bool)

    var tone: ModeKeyTile.Tone {
        switch self {
        case .listening: return .capturing
        case .conflict: return .conflict
        case .notSet, .set: return .rest
        }
    }

    /// Glyph for the key tile. Modifier symbols only, so a long chord still fits.
    var glyph: String {
        switch self {
        case .notSet: return "—"
        case .listening, .conflict: return "⌘⇧"
        case let .set(shortcut, _):
            return Self.tileGlyph(for: shortcut)
        }
    }

    var value: String {
        switch self {
        case .notSet: return "Not set"
        case .listening, .conflict: return "Press keys…"
        case let .set(shortcut, _): return shortcut.displayString
        }
    }

    static func tileGlyph(for shortcut: HotkeyShortcut) -> String {
        let display = shortcut.displayString
        let compact = display
            .replacingOccurrences(of: " + ", with: "")
            .replacingOccurrences(of: "Right ", with: "")
            .replacingOccurrences(of: "Left ", with: "")
        return compact.isEmpty ? display : compact
    }
}

// MARK: - Send to Instinct

/// Board `03 — Send to Instinct`.
///
/// Every value here is read from the real store or service: the shortcut is
/// `SettingsStore.pokeHotkeyShortcut` (captured through the shell's own
/// `ShortcutRecordingTarget.poke` monitor), the on/off pill is
/// `SettingsStore.pokeShortcutEnabled`, and the delivery rows report what
/// `PokeService` would actually do with the next transcript — the iMessage
/// chat id in `UserDefaults[PokeIMessageChatID]` and whether an API key exists.
///
/// The board's "Notify when sent" toggle is NOT rendered: `NotificationService`
/// posts the Instinct result banner unconditionally and no defaults key gates
/// it, so a switch here would be a dead control. See the cluster report.
struct InstinctSettingsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    @Binding var shortcut: HotkeyShortcut?
    @Binding var shortcutEnabled: Bool
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?

    /// Read once per appearance — the Keychain lookup is not free and the
    /// answer only changes when the user edits the Keychain outside the app.
    @State private var hasAPIKey = false

    /// Spelled out because the synthesized memberwise initialiser would inherit
    /// the private access level of the environment and state properties above.
    init(
        shortcut: Binding<HotkeyShortcut?>,
        shortcutEnabled: Binding<Bool>,
        activeShortcutRecordingTarget: Binding<ShortcutRecordingTarget?>,
        shortcutRecordingMessage: Binding<String?>
    ) {
        self._shortcut = shortcut
        self._shortcutEnabled = shortcutEnabled
        self._activeShortcutRecordingTarget = activeShortcutRecordingTarget
        self._shortcutRecordingMessage = shortcutRecordingMessage
    }

    private var isCapturing: Bool {
        self.activeShortcutRecordingTarget == .poke
    }

    private var isRecordingAnything: Bool {
        self.activeShortcutRecordingTarget != nil
    }

    private var chatID: String? {
        let value = UserDefaults.standard.string(forKey: PokeService.iMessageChatIDDefaultsKey)
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private var heroState: ModeShortcutHeroState {
        if self.isCapturing {
            if let message = self.shortcutRecordingMessage, !message.isEmpty {
                return .conflict(message)
            }
            return .listening
        }
        guard let shortcut = self.shortcut else { return .notSet }
        return .set(shortcut, enabled: self.shortcutEnabled)
    }

    private var heroHelper: String {
        switch self.heroState {
        case .notSet:
            return "Pick a chord first — the switch cannot come on without one."
        case .listening:
            return "Escape cancels. A modifier-only chord commits when you let it go."
        case let .conflict(message):
            return message
        case let .set(_, enabled):
            return enabled
                ? "Hold, speak, release. The transcript goes to Instinct instead of being typed."
                : "The chord is kept. Nothing listens for it until this comes back on."
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                ModePageHeader(
                    eyebrow: "Modes",
                    title: "Send to Instinct",
                    lede: "Hold the key, say the thing, let go. The transcript goes straight into your Instinct thread in Messages instead of being typed where the cursor is."
                )

                ModeShortcutHero(
                    eyebrow: "Shortcut · hold to talk",
                    glyph: self.heroState.glyph,
                    value: self.heroState.value,
                    helper: self.heroHelper,
                    tone: self.heroState.tone
                ) {
                    HStack(spacing: 14) {
                        if self.shortcut != nil, !self.isCapturing {
                            Button("Remove") { self.removeShortcut() }
                                .buttonStyle(.plain)
                                .basicsButtonLabel(13)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .disabled(self.isRecordingAnything)
                        }

                        LibraryPagePill(
                            title: self.captureButtonTitle,
                            tone: .outline,
                            height: 36,
                            labelSize: 14
                        ) {
                            self.toggleCapture()
                        }
                        .disabled(!self.isCapturing && self.isRecordingAnything)

                        ModeToggle(isOn: self.enabledBinding, label: "Send to Instinct shortcut")
                            .disabled(self.shortcut == nil || self.isRecordingAnything)
                    }
                }

                ModeSection(title: "Delivery") {
                    VStack(spacing: 0) {
                        ModeSettingRow(
                            title: "Route",
                            helper: self.routeHelper,
                            chip: self.routeChip
                        ) {
                            ModeValueChip(text: self.routeName, isMuted: self.routeChip.tone != .brand)
                        }

                        ModeSettingRow(
                            title: "Thread",
                            helper: self.chatID == nil
                                ? "No Messages chat id is stored, so a send falls back to the inbound web API."
                                : "Found automatically from Messages. Confirm it before you trust it."
                        ) {
                            ModeValueChip(
                                text: self.chatID ?? "Not set",
                                isMuted: self.chatID == nil
                            )
                        }

                        ModeSettingRow(
                            title: "API key",
                            helper: self.hasAPIKey
                                ? "A Poke key is in the Keychain. It is only used when no chat id is stored."
                                : "No Poke key in the Keychain, so the web-API fallback is unavailable."
                        ) {
                            ModeValueChip(
                                text: self.hasAPIKey ? "In Keychain" : "Not found",
                                isMuted: !self.hasAPIKey
                            )
                        }
                        .overlay(alignment: .bottom) { ModeHairline() }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.contentBackground)
        .task {
            self.hasAPIKey = PokeService.shared.hasAPIKey()
        }
    }

    // MARK: - Derived delivery state

    private var routeName: String {
        if self.chatID != nil { return "iMessage" }
        return self.hasAPIKey ? "Inbound API" : "Unconfigured"
    }

    private var routeChip: ModeStatusChip.Model {
        if self.chatID != nil {
            return .init(text: "iMessage", tone: .brand)
        }
        if self.hasAPIKey {
            return .init(text: "Fallback", tone: .warning)
        }
        return .init(text: "Not set up", tone: .muted)
    }

    private var routeHelper: String {
        if self.chatID != nil {
            return "iMessage into the real thread. The inbound web API delivers to whichever account owns the key, which is not this one — so it silently vanishes."
        }
        if self.hasAPIKey {
            return "Falling back to the inbound web API, which delivers to whichever account owns the key — not necessarily the account behind your thread."
        }
        return "Nothing to send through. Add a Messages chat id or a Poke API key in the Keychain."
    }

    // MARK: - Actions

    private var captureButtonTitle: String {
        if self.isCapturing { return "Cancel" }
        return self.shortcut == nil ? "Set shortcut" : "Change"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.shortcutEnabled && self.shortcut != nil },
            set: { newValue in
                guard self.shortcut != nil else { return }
                self.shortcutEnabled = newValue
            }
        )
    }

    private func toggleCapture() {
        if self.isCapturing {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = nil
        } else {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = .poke
        }
    }

    private func removeShortcut() {
        if self.isCapturing {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = nil
        }
        self.shortcut = nil
        self.shortcutEnabled = false
    }
}
