import AppKit
import SwiftUI

// MARK: - Shared interaction + control metrics

enum FluidInteractionVisuals {
    static let hoverScale: CGFloat = 1.01
    /// 0.96 exactly — the tactile sweet spot; below 0.95 reads as exaggerated.
    static let pressedScale: CGFloat = 0.96
    static let hoverAnimation: Animation = .spring(response: 0.18, dampingFraction: 0.78)
    static let pressedAnimation: Animation = .spring(response: 0.2, dampingFraction: 0.8)

    static func scale(isPressed: Bool, isHovered: Bool) -> CGFloat {
        if isPressed { return self.pressedScale }
        return isHovered ? self.hoverScale : 1
    }
}

/// Board "15 — Components" § Buttons and § Focus.
enum BasicsControl {
    /// Fields, selects, icon buttons and nav rows. Between `Radius.sm` and
    /// `Radius.md`, and the board draws it at every one of those four places.
    static let radius: CGFloat = 8

    /// The keyboard focus ring: a 2px gap in the ground colour, then a 2px brand
    /// ring at 45%. Keyboard only — a mouse click never draws it.
    static let ringGap: CGFloat = 2
    static let ringWidth: CGFloat = 2
    static var ringColor: Color { BasicsTokens.Semantic.brand.opacity(0.45) }
}

private struct BasicsFocusRing: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let inset = BasicsControl.ringGap + BasicsControl.ringWidth / 2

        content.overlay {
            if self.isFocused {
                RoundedRectangle(cornerRadius: self.cornerRadius + inset, style: .continuous)
                    .stroke(BasicsControl.ringColor, lineWidth: BasicsControl.ringWidth)
                    .padding(-inset)
            }
        }
    }
}

extension View {
    /// The one focus ring every control uses.
    func basicsFocusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(BasicsFocusRing(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

enum FluidButtonRole {
    case primary
    case secondary
    case glass
    case compact
    case accent
    case destructive
    case inline
    /// Navigation inside a section header — Show all, Learn more, Reset.
    case link
}

enum FluidButtonSize: Equatable {
    case compact
    case small
    case medium
    case large

    /// Board sizes strip: 24 · 28 · 34 · 40.
    var controlHeight: CGFloat {
        switch self {
        case .compact: return 24
        case .small: return 28
        case .medium: return 34
        case .large: return 40
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 10
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        }
    }

    var labelSize: CGFloat {
        switch self {
        case .compact: return 11
        case .small: return 12
        case .medium: return 13
        case .large: return 15
        }
    }

    var accentCompact: Bool {
        self == .small || self == .compact
    }

    static func nearest(to height: CGFloat) -> FluidButtonSize {
        let all: [FluidButtonSize] = [.compact, .small, .medium, .large]
        return all.min(by: { abs($0.controlHeight - height) < abs($1.controlHeight - height) }) ?? .medium
    }
}

extension View {
    func fluidControlSurface(
        isSelected: Bool,
        isHovered: Bool,
        tone: Color,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(FluidControlSurfaceModifier(
            isSelected: isSelected,
            isHovered: isHovered,
            tone: tone,
            cornerRadius: cornerRadius
        ))
    }

    @ViewBuilder
    func fluidButton(
        _ role: FluidButtonRole,
        size: FluidButtonSize = .medium,
        isRecording: Bool = false
    ) -> some View {
        // Our own ring replaces the system one, so the two never double up.
        let button = self.focusEffectDisabled()

        switch role {
        case .primary:
            button.buttonStyle(PremiumButtonStyle(isRecording: isRecording, height: size.controlHeight))
        case .secondary:
            button.buttonStyle(SecondaryButtonStyle(height: size.controlHeight))
        case .glass:
            button.buttonStyle(GlassButtonStyle(height: size.controlHeight))
        case .compact:
            button.buttonStyle(CompactButtonStyle(height: size.controlHeight))
        case .accent:
            button.buttonStyle(AccentButtonStyle(compact: size.accentCompact))
        case .destructive:
            button.buttonStyle(AccentButtonStyle(
                compact: size.accentCompact,
                tone: BasicsTokens.Semantic.danger
            ))
        case .inline:
            button.buttonStyle(InlineButtonStyle())
        case .link:
            button.buttonStyle(PlainLinkButtonStyle(size: size))
        }
    }

    func fluidCompactButton(
        size: FluidButtonSize = .compact,
        isReady: Bool = false,
        foreground: Color? = nil,
        borderColor: Color? = nil
    ) -> some View {
        self.focusEffectDisabled()
            .buttonStyle(CompactButtonStyle(
                isReady: isReady,
                foreground: foreground,
                borderColor: borderColor,
                height: size.controlHeight
            ))
    }
}

// MARK: - List and nav row surface

/// Board § Focus · list and nav rows. Selection is a brandSoft fill with brand
/// text; focus is the ring on top of it. A row can be both at once. Rows do not
/// lift, glow or scale — that reading is reserved for cards and buttons.
private struct FluidControlSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let isSelected: Bool
    let isHovered: Bool
    let tone: Color
    let cornerRadius: CGFloat

    private var fill: Color {
        if self.isSelected { return self.tone.opacity(0.10) }
        if self.isHovered { return self.theme.palette.sidebarBackground }
        return .clear
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)

        content
            .background(shape.fill(self.fill))
            .animation(FluidInteractionVisuals.hoverAnimation, value: self.isSelected)
            .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
    }
}

// MARK: - Filled pill (primary / accent / destructive)

/// One filled button per region. Rest brand, hover green600, pressed green700.
private struct BasicsFilledPill: View {
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let configuration: ButtonStyle.Configuration
    let size: FluidButtonSize
    let tone: Color

    private var fill: Color {
        guard self.isEnabled else { return self.theme.palette.sidebarBackground }
        if self.configuration.isPressed { return self.tone.blended(withBlack: 0.28) }
        if self.isHovered { return self.tone.blended(withBlack: 0.14) }
        return self.tone
    }

    private var labelColor: Color {
        self.isEnabled ? .white : self.theme.palette.tertiaryText
    }

    var body: some View {
        self.configuration.label
            .basicsButtonLabel(self.size.labelSize)
            .foregroundStyle(self.labelColor)
            .padding(.horizontal, self.size.horizontalPadding)
            .frame(height: self.size.controlHeight)
            .background(Capsule().fill(self.fill))
            .overlay {
                if !self.isEnabled {
                    Capsule().stroke(self.theme.palette.cardBorder, lineWidth: 1)
                }
            }
            .basicsFocusRing(self.isFocused, cornerRadius: self.size.controlHeight / 2)
            .scaleEffect(FluidInteractionVisuals.scale(
                isPressed: self.configuration.isPressed,
                isHovered: self.isHovered && self.isEnabled
            ))
            .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
            .animation(FluidInteractionVisuals.pressedAnimation, value: self.configuration.isPressed)
            .onHover { self.isHovered = $0 }
    }
}

// MARK: - Outlined pill (secondary / glass / compact)

/// Everything reversible — Change, Import, Export, Choose file.
private struct BasicsOutlinedPill: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let configuration: ButtonStyle.Configuration
    let size: FluidButtonSize
    /// A brand outline instead of a neutral one — the "this is the next thing to
    /// press" state the pickers already track.
    let isBrandOutlined: Bool
    let foreground: Color?
    let borderColor: Color?

    private var fill: Color {
        if !self.isEnabled { return self.theme.palette.sidebarBackground }
        if self.configuration.isPressed { return self.theme.palette.cardBorder }
        if self.isHovered { return self.theme.palette.sidebarBackground }
        return self.theme.palette.cardBackground
    }

    private var border: Color {
        if let borderColor = self.borderColor { return borderColor }
        if !self.isEnabled { return self.theme.palette.cardBorder }
        if self.isBrandOutlined { return self.theme.palette.accent.opacity(0.45) }
        return BasicsBorder.strong(self.theme, self.colorScheme)
    }

    private var labelColor: Color {
        if !self.isEnabled { return self.theme.palette.tertiaryText }
        if let foreground = self.foreground { return foreground }
        if self.isBrandOutlined { return self.theme.palette.accent }
        return self.theme.palette.primaryText
    }

    var body: some View {
        self.configuration.label
            .basicsButtonLabel(self.size.labelSize)
            .foregroundStyle(self.labelColor)
            .padding(.horizontal, self.size.horizontalPadding)
            .frame(height: self.size.controlHeight)
            .background(Capsule().fill(self.fill))
            .overlay(Capsule().stroke(self.border, lineWidth: 1))
            .basicsFocusRing(self.isFocused, cornerRadius: self.size.controlHeight / 2)
            .scaleEffect(FluidInteractionVisuals.scale(
                isPressed: self.configuration.isPressed,
                isHovered: self.isHovered && self.isEnabled
            ))
            .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
            .animation(FluidInteractionVisuals.pressedAnimation, value: self.configuration.isPressed)
            .onHover { self.isHovered = $0 }
    }
}

// MARK: - Primary

struct PremiumButtonStyle: ButtonStyle {
    var isRecording: Bool = false
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration, isRecording: self.isRecording, height: self.height)
    }

    private struct PrimaryButton: View {
        @Environment(\.theme) private var theme
        let configuration: ButtonStyle.Configuration
        let isRecording: Bool
        let height: CGFloat

        var body: some View {
            BasicsFilledPill(
                configuration: self.configuration,
                size: .nearest(to: self.height),
                // Recording is a stop-this state: it takes danger, not brand.
                tone: self.isRecording ? BasicsTokens.Semantic.danger : self.theme.palette.accent
            )
        }
    }
}

// MARK: - Secondary

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        BasicsOutlinedPill(
            configuration: configuration,
            size: .nearest(to: self.height),
            isBrandOutlined: false,
            foreground: nil,
            borderColor: nil
        )
    }
}

/// Was a translucent "glass" button. There is no glass in the Basics system — it
/// resolves to the same outlined pill as Secondary so the two can never drift.
struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        BasicsOutlinedPill(
            configuration: configuration,
            size: .nearest(to: self.height ?? 34),
            isBrandOutlined: false,
            foreground: nil,
            borderColor: nil
        )
    }
}

// MARK: - Compact

struct CompactButtonStyle: ButtonStyle {
    var isReady: Bool = false
    var foreground: Color? = nil
    var borderColor: Color? = nil
    var height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        BasicsOutlinedPill(
            configuration: configuration,
            size: .nearest(to: self.height),
            isBrandOutlined: self.isReady,
            foreground: self.foreground,
            borderColor: self.borderColor
        )
    }
}

// MARK: - Accent / destructive filled

struct AccentButtonStyle: ButtonStyle {
    var compact: Bool = false
    var tone: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        AccentButton(configuration: configuration, compact: self.compact, tone: self.tone)
    }

    private struct AccentButton: View {
        @Environment(\.theme) private var theme
        let configuration: ButtonStyle.Configuration
        let compact: Bool
        let tone: Color?

        var body: some View {
            BasicsFilledPill(
                configuration: self.configuration,
                size: self.compact ? .small : .medium,
                tone: self.tone ?? self.theme.palette.accent
            )
        }
    }
}

// MARK: - Soft (inline invitation)

/// Board § Buttons · Soft. Inline invitations inside a row — Configure, Grant,
/// Try it. brandSoft ground, brand label, 28 tall.
struct InlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration)
    }

    private struct SoftButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        let configuration: ButtonStyle.Configuration

        private var fill: Color {
            let accent = self.theme.palette.accent
            if !self.isEnabled { return self.theme.palette.sidebarBackground }
            if self.configuration.isPressed { return accent.opacity(0.26) }
            if self.isHovered { return accent.opacity(0.18) }
            return accent.opacity(0.10)
        }

        private var labelColor: Color {
            if !self.isEnabled { return self.theme.palette.tertiaryText }
            if self.configuration.isPressed { return BasicsTokens.Green.g700 }
            if self.isHovered { return BasicsTokens.Green.g600 }
            return self.theme.palette.accent
        }

        var body: some View {
            self.configuration.label
                .basicsButtonLabel(12)
                .foregroundStyle(self.labelColor)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(self.fill))
                .overlay {
                    if !self.isEnabled {
                        Capsule().stroke(self.theme.palette.cardBorder, lineWidth: 1)
                    }
                }
                .basicsFocusRing(self.isFocused, cornerRadius: 14)
                .scaleEffect(FluidInteractionVisuals.scale(
                    isPressed: self.configuration.isPressed,
                    isHovered: self.isHovered && self.isEnabled
                ))
                .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
                .animation(FluidInteractionVisuals.pressedAnimation, value: self.configuration.isPressed)
                .onHover { self.isHovered = $0 }
        }
    }
}

// MARK: - Plain link

/// Board § Buttons · plain link. No chrome at all; the underline is the hover.
struct PlainLinkButtonStyle: ButtonStyle {
    var size: FluidButtonSize = .medium

    func makeBody(configuration: Configuration) -> some View {
        LinkButton(configuration: configuration, size: self.size)
    }

    private struct LinkButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        let configuration: ButtonStyle.Configuration
        let size: FluidButtonSize

        private var labelColor: Color {
            if !self.isEnabled { return self.theme.palette.tertiaryText }
            if self.configuration.isPressed { return BasicsTokens.Green.g700 }
            if self.isHovered { return BasicsTokens.Green.g600 }
            return self.theme.palette.accent
        }

        private var isUnderlined: Bool {
            self.isEnabled && (self.isHovered || self.configuration.isPressed)
        }

        var body: some View {
            self.configuration.label
                .basicsButtonLabel(self.size.labelSize)
                .foregroundStyle(self.labelColor)
                .underline(self.isUnderlined)
                .frame(height: self.size.controlHeight)
                .contentShape(Rectangle())
                .basicsFocusRing(self.isFocused, cornerRadius: BasicsControl.radius)
                .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
                .onHover { self.isHovered = $0 }
        }
    }
}

// MARK: - Toggle

/// Board § Focus · toggle. 44 × 26 pill, brand when on, borderStrong when off,
/// flat 20px white knob — no gradient, no inner shadow.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToggleBody(configuration: configuration)
    }

    private struct ToggleBody: View {
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @FocusState private var isFocused: Bool
        let configuration: ToggleStyle.Configuration

        var body: some View {
            HStack(spacing: 12) {
                self.configuration.label
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.primaryText)

                Spacer(minLength: 8)

                Button {
                    self.configuration.isOn.toggle()
                } label: {
                    Capsule()
                        .fill(
                            self.configuration.isOn
                                ? self.theme.palette.accent
                                : BasicsBorder.strong(self.theme, self.colorScheme)
                        )
                        .frame(width: 44, height: 26)
                        .overlay(alignment: self.configuration.isOn ? .trailing : .leading) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                                .padding(3)
                        }
                }
                .buttonStyle(.plain)
                .focusable(self.isEnabled)
                .focused(self.$isFocused)
                .focusEffectDisabled()
                .basicsFocusRing(self.isFocused, cornerRadius: 13)
                .opacity(self.isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.18), value: self.configuration.isOn)
                .accessibilityAddTraits(self.configuration.isOn ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Form row

/// A row that reads as a single field. Settings themselves sit directly on the
/// surface separated by hairlines — this is the grouped case.
struct FormRowStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let row = self.theme.metrics.formRow
        let shape = RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)

        content
            .padding(.horizontal, row.horizontalPadding)
            .padding(.vertical, row.verticalPadding)
            .background(
                shape
                    .fill(self.theme.palette.cardBackground)
                    .overlay(shape.stroke(self.theme.palette.cardBorder, lineWidth: 1))
            )
    }
}

// MARK: - Searchable picker chrome

/// Board § Focus · select. The chevron takes the brand colour while the menu is
/// reachable from the keyboard.
struct FluidPickerDisclosureIcon: View {
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused
    var backgroundOpacity: Double

    var body: some View {
        let picker = self.theme.metrics.pickerControl

        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
                self.isFocused ? self.theme.palette.accent : self.theme.palette.secondaryText
            )
            .frame(width: picker.disclosureSize, height: picker.disclosureSize)
            .background(
                Circle().fill(self.theme.palette.sidebarBackground.opacity(self.backgroundOpacity))
            )
    }
}

struct SearchablePickerControlChrome: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused
    let width: CGFloat?
    let height: CGFloat?
    /// The control floats over content rather than sitting in a row — it gets the
    /// card's soft shadow pair so it reads as raised.
    let usesMaterial: Bool
    let showsShadow: Bool

    private var shadows: [BasicsShadow] {
        let ink = BasicsTokens.Ink.foreground
        if self.usesMaterial {
            return [
                BasicsShadow(color: ink.opacity(0.04), radius: 1, y: 1),
                BasicsShadow(color: ink.opacity(0.04), radius: 12, y: 8),
            ]
        }
        if self.showsShadow {
            return [BasicsShadow(color: ink.opacity(0.05), radius: 1.5, y: 1)]
        }
        return []
    }

    func body(content: Content) -> some View {
        let picker = self.theme.metrics.pickerControl
        let shape = RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)

        content
            .frame(width: self.width, alignment: .leading)
            .frame(maxWidth: self.width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, picker.horizontalPadding)
            .padding(.vertical, picker.verticalPadding)
            .frame(height: self.height)
            .contentShape(Rectangle())
            .background(
                shape
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        shape.stroke(
                            self.isFocused
                                ? self.theme.palette.accent
                                : BasicsBorder.strong(self.theme, self.colorScheme),
                            lineWidth: 1
                        )
                    )
                    .basicsShadows(self.shadows)
            )
            .basicsFocusRing(self.isFocused, cornerRadius: BasicsControl.radius)
    }
}

struct SearchablePickerSearchFieldChrome: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)

        content
            .padding(self.theme.metrics.spacing.sm)
            .background(
                shape
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        shape.stroke(
                            self.isFocused
                                ? self.theme.palette.accent
                                : BasicsBorder.strong(self.theme, self.colorScheme),
                            lineWidth: 1
                        )
                    )
            )
    }
}

extension View {
    func formRowStyle() -> some View {
        modifier(FormRowStyle())
    }

    func searchablePickerControlChrome(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        usesMaterial: Bool = false,
        showsShadow: Bool = false
    ) -> some View {
        modifier(SearchablePickerControlChrome(
            width: width,
            height: height,
            usesMaterial: usesMaterial,
            showsShadow: showsShadow
        ))
    }

    func searchablePickerSearchFieldChrome() -> some View {
        modifier(SearchablePickerSearchFieldChrome())
    }

    func searchablePickerSelectedRowBackground(isSelected: Bool) -> some View {
        modifier(SearchablePickerSelectedRowBackground(isSelected: isSelected))
    }
}

private struct SearchablePickerSelectedRowBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.background(
            self.isSelected ? self.theme.palette.accent.opacity(0.10) : Color.clear
        )
    }
}

// MARK: - Icon only

/// Board § Buttons · icon only. 28 × 28, radius 8. Copy and play on a history
/// row — they stay invisible until the row is hovered, which is the row's job.
struct SquareIconButtonStyle: ButtonStyle {
    var foreground: Color? = nil
    var borderColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        SquareIconButton(
            configuration: configuration,
            foreground: self.foreground,
            borderColor: self.borderColor
        )
    }

    private struct SquareIconButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        let configuration: ButtonStyle.Configuration
        let foreground: Color?
        let borderColor: Color?

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)
        }

        private var isActive: Bool { self.isHovered && self.isEnabled }

        private var labelColor: Color {
            if !self.isEnabled { return self.theme.palette.tertiaryText }
            if let foreground = self.foreground { return foreground }
            return self.isActive ? self.theme.palette.primaryText : self.theme.palette.secondaryText
        }

        var body: some View {
            let active = self.isActive
            let fill = active || self.configuration.isPressed
                ? self.theme.palette.sidebarBackground
                : self.theme.palette.cardBackground
            let border = self.borderColor
                ?? (active
                    ? BasicsBorder.strong(self.theme, self.colorScheme)
                    : self.theme.palette.cardBorder)

            self.configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.labelColor)
                .frame(width: 28, height: 28)
                .background(self.shape.fill(fill))
                .overlay(self.shape.stroke(border, lineWidth: 1))
                .basicsFocusRing(self.isFocused, cornerRadius: BasicsControl.radius)
                .scaleEffect(FluidInteractionVisuals.scale(
                    isPressed: self.configuration.isPressed,
                    isHovered: active
                ))
                .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
                .animation(FluidInteractionVisuals.pressedAnimation, value: self.configuration.isPressed)
                .onHover { self.isHovered = $0 }
        }
    }
}

// MARK: - Colour helpers

private extension Color {
    /// The hover / pressed steps on a filled pill: brand → green600 → green700 is
    /// a straight 14% / 28% walk toward black, so a custom tone (danger, or a
    /// user-chosen accent) darkens by exactly the same amount.
    func blended(withBlack amount: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return Color(
            red: Double(base.redComponent) * (1 - amount),
            green: Double(base.greenComponent) * (1 - amount),
            blue: Double(base.blueComponent) * (1 - amount),
            opacity: Double(base.alphaComponent)
        )
    }
}
