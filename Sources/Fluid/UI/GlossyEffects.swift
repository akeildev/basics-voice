import SwiftUI

// MARK: - Hoverable Card

/// Board "15 — Components" § Card · interactive.
///
/// Formerly a glossy card: a translucent material with a white shine gradient on
/// top. The Basics surfaces are flat — white on snow, one hairline, two soft
/// shadows — so the gloss is gone and only the hover behaviour is kept: border
/// steps to borderStrong, the shadow deepens, the card scales 1.01 over 180ms.
struct HoverableGlossyCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private let content: Content
    private let excludeInteractiveElements: Bool

    init(excludeInteractiveElements: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.excludeInteractiveElements = excludeInteractiveElements
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
        let ink = BasicsTokens.Ink.foreground
        let border = self.isHovered
            ? BasicsBorder.strong(self.theme, self.colorScheme)
            : self.theme.palette.cardBorder
        let shadows = self.isHovered
            ? [
                BasicsShadow(color: ink.opacity(0.05), radius: 1.5, y: 2),
                BasicsShadow(color: ink.opacity(0.08), radius: 17, y: 14),
            ]
            : [
                BasicsShadow(color: ink.opacity(0.04), radius: 1, y: 1),
                BasicsShadow(color: ink.opacity(0.04), radius: 12, y: 8),
            ]

        return self.content
            .background {
                shape
                    .fill(self.theme.palette.cardBackground)
                    .overlay(shape.stroke(border, lineWidth: 1))
                    .basicsShadows(shadows)
            }
            .scaleEffect(self.isHovered && !self.excludeInteractiveElements ? 1.01 : 1.0)
            .onHover { hovering in
                self.isHovered = hovering
            }
            .animation(.easeOut(duration: 0.18), value: self.isHovered)
    }
}

// MARK: - Button Hover Extension

extension View {
    func buttonHoverEffect() -> some View {
        modifier(ButtonHoverModifier())
    }
}

/// The lift a bare (unstyled) control gets on hover. The accent glow it used to
/// throw is not on any board — one green moment per region, and it belongs to the
/// control's own fill, not to a halo around it.
struct ButtonHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(self.isHovered ? FluidInteractionVisuals.hoverScale : 1.0)
            .onHover { hovering in
                self.isHovered = hovering
            }
            .animation(FluidInteractionVisuals.hoverAnimation, value: self.isHovered)
    }
}
