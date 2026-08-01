import SwiftUI

enum ThemedCardStyle {
    case standard
    case prominent
    case subtle
}

/// `borderStrong` is a light-ramp token. On the dark theme the equivalent step —
/// "one stronger than a hairline" — is the theme's own separator (white @10% vs
/// the white @7% hairline), so hover never paints a light-grey line on a dark card.
enum BasicsBorder {
    static func strong(_ theme: AppTheme, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? theme.palette.separator : BasicsTokens.Surface.borderStrong
    }
}

/// A soft shadow as the board specifies it: CSS `x y blur` where the SwiftUI
/// radius is half the CSS blur.
struct BasicsShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

extension View {
    func basicsShadows(_ shadows: [BasicsShadow]) -> some View {
        shadows.reduce(AnyView(self)) { view, shadow in
            AnyView(view.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y))
        }
    }
}

/// Board "15 — Components" § Card.
///
/// Three shells, no materials. White on snow with a 1px hairline and two soft
/// shadows is the default container; cards are for hero and grouped-emphasis
/// moments only — ordinary settings sit on the surface, separated by hairlines.
struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private let style: ThemedCardStyle
    private let hoverEffect: Bool
    private let padding: CGFloat?
    private let content: Content

    init(
        style: ThemedCardStyle = .standard,
        padding: CGFloat? = nil,
        hoverEffect: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.hoverEffect = hoverEffect
        self.content = content()
    }

    private var isActive: Bool { self.isHovered && self.hoverEffect }

    var body: some View {
        let configuration = CardConfiguration(
            style: self.style,
            theme: self.theme,
            colorScheme: self.colorScheme
        )
        let shape = RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)

        self.content
            .padding(self.resolvedInsets(configuration))
            .background(
                shape
                    .fill(configuration.background)
                    .overlay(
                        shape.stroke(
                            self.isActive ? configuration.hoverBorder : configuration.border,
                            lineWidth: 1
                        )
                    )
                    .basicsShadows(self.isActive ? configuration.hoverShadows : configuration.shadows)
            )
            .scaleEffect(self.isActive ? 1.01 : 1.0)
            .onHover { hovering in
                guard self.hoverEffect else { return }
                self.isHovered = hovering
            }
            .animation(.easeOut(duration: 0.18), value: self.isHovered)
    }

    private func resolvedInsets(_ configuration: CardConfiguration) -> EdgeInsets {
        guard let padding = self.padding else { return configuration.insets }
        return EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
    }
}

// MARK: - Configuration

private extension ThemedCard {
    struct CardConfiguration {
        let background: Color
        let border: Color
        let hoverBorder: Color
        let cornerRadius: CGFloat
        let insets: EdgeInsets
        let shadows: [BasicsShadow]
        let hoverShadows: [BasicsShadow]

        init(style: ThemedCardStyle, theme: AppTheme, colorScheme: ColorScheme) {
            let ink = BasicsTokens.Ink.foreground
            let brand = BasicsTokens.Semantic.brand
            let strong = BasicsBorder.strong(theme, colorScheme)

            // Board: standard rest `0 1px 2px` + `0 8px 24px` at ink 4%;
            // hover `0 2px 3px` at 5% + `0 14px 34px` at 8%.
            let restShadows = [
                BasicsShadow(color: ink.opacity(0.04), radius: 1, y: 1),
                BasicsShadow(color: ink.opacity(0.04), radius: 12, y: 8),
            ]
            let raisedShadows = [
                BasicsShadow(color: ink.opacity(0.05), radius: 1.5, y: 2),
                BasicsShadow(color: ink.opacity(0.08), radius: 17, y: 14),
            ]

            switch style {
            case .standard:
                self.background = theme.palette.cardBackground
                self.border = theme.palette.cardBorder
                self.hoverBorder = strong
                self.cornerRadius = BasicsTokens.Radius.lg
                self.insets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
                self.shadows = restShadows
                self.hoverShadows = raisedShadows

            case .prominent:
                self.background = theme.palette.elevatedCardBackground
                self.border = brand.opacity(0.40)
                self.hoverBorder = brand.opacity(0.55)
                self.cornerRadius = BasicsTokens.Radius.lg
                self.insets = EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)
                self.shadows = [
                    BasicsShadow(color: brand.opacity(0.06), radius: 2, y: 2),
                    BasicsShadow(color: brand.opacity(0.10), radius: 16, y: 12),
                ]
                self.hoverShadows = [
                    BasicsShadow(color: brand.opacity(0.08), radius: 2, y: 2),
                    BasicsShadow(color: brand.opacity(0.16), radius: 18, y: 14),
                ]

            case .subtle:
                // An inset well on the muted ground. No shadow — it sits *into*
                // the surface, it does not rise off it.
                self.background = theme.palette.sidebarBackground
                self.border = theme.palette.cardBorder
                self.hoverBorder = strong
                self.cornerRadius = BasicsTokens.Radius.md
                self.insets = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
                self.shadows = []
                self.hoverShadows = []
            }
        }
    }
}
