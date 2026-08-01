import SwiftUI

/// Central theme definition for the Fluid app. All colors, spacings and materials
/// should be defined here to keep styling consistent and easy to evolve.
struct AppTheme {
    struct Palette {
        let windowBackground: Color
        let contentBackground: Color
        let sidebarBackground: Color
        let cardBackground: Color
        let elevatedCardBackground: Color
        let toolbarBackground: Color
        let cardBorder: Color
        let separator: Color
        let primaryText: Color
        let secondaryText: Color
        let tertiaryText: Color
        let accent: Color
        let warning: Color
        let success: Color
    }

    struct Typography {
        let displayTitle: Font
        let statement: Font
        let title: Font
        let titleIcon: Font
        let sectionTitle: Font
        let body: Font
        let bodyStrong: Font
        let bodySmall: Font
        let bodySmallStrong: Font
        let caption: Font
        let captionStrong: Font
        let captionSmall: Font
        let tiny: Font
        let tinyStrong: Font
        let badge: Font
        let metricTiny: Font
        let codeCaption: Font
        let sidebarItem: Font
        let sidebarSection: Font
        let chromeCaption: Font

        // Basics roles. The pre-existing roles above do not distinguish a LABEL
        // from a SENTENCE, but the Basics system divides the two families by
        // exactly that: Chillax scans, Karma reads. Rather than guess globally,
        // ambiguous legacy roles stay on Chillax and these explicit roles carry
        // the prose, so each call site can be assigned by reading its context.
        let proseBody: Font
        let proseSmall: Font
        let microLabel: Font
        let buttonLabel: Font
        let statNumeral: Font
        let monoBody: Font
        let monoSmall: Font

        static let standard = Typography(
            displayTitle: BasicsTokens.display(40, .medium),
            statement: BasicsTokens.prose(17, .regular),
            title: BasicsTokens.display(22, .medium),
            titleIcon: .system(size: 22, weight: .regular),
            sectionTitle: BasicsTokens.display(15, .medium),
            body: BasicsTokens.display(14, .medium),
            bodyStrong: BasicsTokens.display(14, .medium),
            bodySmall: BasicsTokens.display(13, .medium),
            bodySmallStrong: BasicsTokens.display(13, .medium),
            caption: BasicsTokens.display(12, .medium),
            captionStrong: BasicsTokens.display(12, .medium),
            captionSmall: BasicsTokens.display(11, .medium),
            tiny: BasicsTokens.display(11, .medium),
            tinyStrong: BasicsTokens.display(11, .semibold),
            badge: BasicsTokens.display(11, .medium),
            metricTiny: BasicsTokens.mono(11, .medium),
            codeCaption: BasicsTokens.mono(12, .regular),
            sidebarItem: BasicsTokens.display(14, .medium),
            sidebarSection: BasicsTokens.display(11, .medium),
            chromeCaption: BasicsTokens.display(12, .medium),

            proseBody: BasicsTokens.prose(15, .regular),
            proseSmall: BasicsTokens.prose(14, .regular),
            microLabel: BasicsTokens.display(11, .medium),
            buttonLabel: BasicsTokens.button(13),
            statNumeral: BasicsTokens.display(34, .medium),
            monoBody: BasicsTokens.mono(13, .regular),
            monoSmall: BasicsTokens.mono(12, .regular)
        )
    }

    struct Metrics {
        struct Spacing {
            let xs: CGFloat
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let xl: CGFloat
            let xxl: CGFloat

            static let standard = Spacing(
                xs: 4,
                sm: 8,
                md: 12,
                lg: 16,
                xl: 20,
                xxl: 28
            )
        }

        struct CornerRadius {
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let pill: CGFloat

            // Concentric rule: outer radius = inner radius + padding.
            // Cards (lg) typically nest md-radius rows with ~10pt padding.
            static let standard = CornerRadius(
                sm: 6,
                md: 10,
                lg: 20,
                pill: 999
            )
        }

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
            let opacity: Double

            static func subtle(color: Color, opacity: Double = 0.45) -> Shadow {
                Shadow(color: color, radius: 12, x: 0, y: 6, opacity: opacity)
            }
        }

        struct FormRow {
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let cornerRadius: CGFloat
            let materialOpacity: Double
            let borderOpacity: Double

            static let standard = FormRow(
                horizontalPadding: 12,
                verticalPadding: 10,
                cornerRadius: 8,
                materialOpacity: 0.5,
                borderOpacity: 0.8
            )
        }

        struct PickerControl {
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let cornerRadius: CGFloat
            let borderOpacity: Double
            let searchBorderOpacity: Double
            let disclosureSize: CGFloat
            let disclosureBorderOpacity: Double
            let selectedRowOpacity: Double

            static let standard = PickerControl(
                horizontalPadding: 8,
                verticalPadding: 5,
                cornerRadius: 6,
                borderOpacity: 0.35,
                searchBorderOpacity: 0.3,
                disclosureSize: 20,
                disclosureBorderOpacity: 0.4,
                selectedRowOpacity: 0.15
            )
        }

        struct CardSurface {
            struct Variant {
                let borderOpacity: Double
                let hoverBorderOpacity: Double
                let borderWidth: CGFloat
                let hoverShadowBoost: Double
            }

            let defaultPadding: CGFloat
            let standard: Variant
            let prominent: Variant
            let subtle: Variant

            static let defaults = CardSurface(
                defaultPadding: 14,
                standard: Variant(
                    borderOpacity: 0.28,
                    hoverBorderOpacity: 0.5,
                    borderWidth: 1,
                    hoverShadowBoost: 0.12
                ),
                prominent: Variant(
                    borderOpacity: 0.25,
                    hoverBorderOpacity: 0.55,
                    borderWidth: 1.2,
                    hoverShadowBoost: 0.15
                ),
                subtle: Variant(
                    borderOpacity: 0.18,
                    hoverBorderOpacity: 0.32,
                    borderWidth: 0.8,
                    hoverShadowBoost: 0.08
                )
            )
        }

        struct OnboardingSurface {
            struct Landing {
                let contentWidth: CGFloat
                let heroPadding: CGFloat
                let heroIconSize: CGFloat
                let heroIconFrame: CGFloat
                let tileSpacing: CGFloat
                let sectionSpacing: CGFloat
                let heroCornerRadius: CGFloat
            }

            let normalFillOpacity: Double
            let selectedFillOpacity: Double
            let normalBorderOpacity: Double
            let selectedBorderOpacity: Double
            let editorBorderOpacity: Double
            let editorPadding: CGFloat
            let optionPadding: CGFloat
            let compactOptionPadding: CGFloat
            let optionCornerRadius: CGFloat
            let compactOptionCornerRadius: CGFloat
            let editorCornerRadius: CGFloat
            let landing: Landing

            static let standard = OnboardingSurface(
                normalFillOpacity: 0.55,
                selectedFillOpacity: 0.82,
                normalBorderOpacity: 0.32,
                selectedBorderOpacity: 0.45,
                editorBorderOpacity: 0.6,
                editorPadding: 10,
                optionPadding: 12,
                compactOptionPadding: 10,
                optionCornerRadius: 12,
                compactOptionCornerRadius: 10,
                editorCornerRadius: 8,
                landing: Landing(
                    contentWidth: 820,
                    heroPadding: 28,
                    heroIconSize: 48,
                    heroIconFrame: 68,
                    tileSpacing: 12,
                    sectionSpacing: 16,
                    heroCornerRadius: 18
                )
            )
        }

        struct Window {
            let mainMinWidth: CGFloat
            let mainMinHeight: CGFloat
            let onboardingMinWidth: CGFloat
            let onboardingMinHeight: CGFloat

            static let standard = Window(
                mainMinWidth: 800,
                mainMinHeight: 500,
                onboardingMinWidth: 940,
                onboardingMinHeight: 700
            )
        }

        let spacing: Spacing
        let corners: CornerRadius
        let formRow: FormRow
        let pickerControl: PickerControl
        let cardSurface: CardSurface
        let onboardingSurface: OnboardingSurface
        let window: Window
        let cardShadow: Shadow
        let elevatedCardShadow: Shadow
    }

    struct Materials {
        let window: Material
        let sidebar: Material
        let card: Material
        let elevatedCard: Material
        let formRow: Material
        let toolbar: Material
    }

    let palette: Palette
    let typography: Typography
    let metrics: Metrics
    let materials: Materials

    static func adaptive(accent: Color, colorScheme: ColorScheme) -> AppTheme {
        switch colorScheme {
        case .light:
            return .light(accent: accent)
        case .dark:
            return .dark(accent: accent)
        @unknown default:
            return .dark(accent: accent)
        }
    }

    /// Light theme on the Basics surfaces — snow ground, spruce-tinted neutrals.
    ///
    /// This deliberately replaces the previous all-system-colour palette. Those
    /// let macOS accessibility contrast settings drive the greys, which is the
    /// safer default but cannot express the Basics system: its neutrals carry hue
    /// 157.6 at chroma 0.002-0.010, and that faint spruce cast is the thing that
    /// makes the greys sit with the green instead of beside it. Contrast was
    /// checked rather than assumed — foreground on card is 18.4:1, muted
    /// foreground on card is 5.1:1, both past AA.
    static func light(accent: Color) -> AppTheme {
        AppTheme(
            palette: Palette(
                windowBackground: BasicsTokens.Surface.bg,
                // Pages sit on the toned ground; only CARDS are white. This is
                // what makes cards stand out without borders.
                contentBackground: BasicsTokens.Surface.bg,
                sidebarBackground: BasicsTokens.Surface.sidebar,
                cardBackground: BasicsTokens.Surface.card,
                elevatedCardBackground: BasicsTokens.Surface.card,
                toolbarBackground: BasicsTokens.Surface.bg,

                cardBorder: BasicsTokens.Surface.border,
                separator: BasicsTokens.Surface.border,
                primaryText: BasicsTokens.Ink.foreground,
                secondaryText: BasicsTokens.Ink.muted,
                tertiaryText: BasicsTokens.Ink.faint,
                accent: accent,
                warning: BasicsTokens.Semantic.warning,
                success: accent
            ),
            typography: .standard,
            metrics: Metrics(
                spacing: .standard,
                corners: .standard,
                formRow: .standard,
                pickerControl: .standard,
                cardSurface: .defaults,
                onboardingSurface: .standard,
                window: .standard,
                cardShadow: .subtle(color: .black, opacity: 0.18),
                elevatedCardShadow: .subtle(color: .black, opacity: 0.22)
            ),
            materials: Materials(
                window: .thinMaterial,
                sidebar: .ultraThinMaterial,
                card: .thinMaterial,
                elevatedCard: .regularMaterial,
                formRow: .ultraThinMaterial,
                toolbar: .ultraThinMaterial
            )
        )
    }

    /// Default dark-forward theme tuned for macOS Sonoma / Sequoia aesthetics.
    static func dark(accent: Color) -> AppTheme {
        AppTheme(
            palette: Palette(
                windowBackground: Color(red: 0.07, green: 0.07, blue: 0.07),
                contentBackground: Color(red: 0.09, green: 0.09, blue: 0.09),
                sidebarBackground: Color(red: 0.06, green: 0.06, blue: 0.06),
                cardBackground: Color(red: 0.08, green: 0.08, blue: 0.08),
                elevatedCardBackground: Color(red: 0.11, green: 0.11, blue: 0.11),
                toolbarBackground: Color(red: 0.06, green: 0.06, blue: 0.06),

                // Soft edges: depth comes from the layered card shadows, not hard
                // borders — borders are hairlines that define, not divide.
                cardBorder: Color.white.opacity(0.07),
                separator: Color.white.opacity(0.10),
                primaryText: Color(nsColor: .labelColor),
                secondaryText: Color(nsColor: .secondaryLabelColor),
                tertiaryText: Color(nsColor: .tertiaryLabelColor),
                accent: accent,
                warning: Color(nsColor: .systemOrange),
                success: accent
            ),
            typography: .standard,
            metrics: Metrics(
                spacing: .standard,
                corners: .standard,
                formRow: .standard,
                pickerControl: .standard,
                cardSurface: .defaults,
                onboardingSurface: .standard,
                window: .standard,
                cardShadow: .subtle(color: .black, opacity: 0.70),
                elevatedCardShadow: .subtle(color: .black, opacity: 0.80)
            ),
            materials: Materials(
                window: .thinMaterial,
                sidebar: .ultraThinMaterial,
                card: .thinMaterial,
                elevatedCard: .regularMaterial,
                formRow: .ultraThinMaterial,
                toolbar: .ultraThinMaterial
            )
        )
    }

    static let light = AppTheme.light(accent: .fluidGreen)
    static let dark = AppTheme.dark(accent: .fluidGreen)
}

// MARK: - Helpers
