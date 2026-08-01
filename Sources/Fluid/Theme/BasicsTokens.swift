import SwiftUI
import AppKit
import CoreText

/// Basics design system tokens.
///
/// Ported from `~/basics-brand/tokens.css`. Every value here is derived from the
/// Basics logo tile green `#2F7A53` = `oklch(0.522 0.097 157.6)`. The whole ramp
/// holds hue 157.6 at a constant 79% of each step's max sRGB chroma, so it never
/// drifts toward teal or olive. Neutrals carry the same hue at chroma 0.002-0.010,
/// which is what gives the greys their faint spruce cast.
///
/// The hex values below were produced by converting the oklch source values, not
/// by eye — `green500` round-trips to exactly `#2F7A53`.
enum BasicsTokens {

    // MARK: - Surfaces

    enum Surface {
        /// App ground — snow, faintly spruce-tinted.
        static let bg = Color(hex: "#F9FAF9")!
        /// Raised surface / detail pane.
        static let card = Color.white
        /// Sidebar ground, and the fill for inset wells.
        static let sidebar = Color(hex: "#F1F4F2")!
        static let muted = Color(hex: "#F1F4F2")!
        /// The 1px hairline that does most of the separating in this app.
        static let border = Color(hex: "#E0E4E1")!
        /// Control outlines and field borders — one step stronger than a hairline.
        static let borderStrong = Color(hex: "#CDD3CF")!
    }

    // MARK: - Text

    enum Ink {
        static let foreground = Color(hex: "#0E120F")!
        static let muted = Color(hex: "#6D736F")!
        /// Uppercase micro-labels and placeholders only — too light for body copy.
        static let faint = Color(hex: "#949A96")!
    }

    // MARK: - Evergreen ramp

    enum Green {
        static let g50 = Color(hex: "#E5FCED")!
        static let g100 = Color(hex: "#CCF3DB")!
        static let g200 = Color(hex: "#ABE4C1")!
        static let g300 = Color(hex: "#88CCA4")!
        static let g400 = Color(hex: "#5BA47B")!
        /// The logo green.
        static let g500 = Color(hex: "#2F7A53")!
        static let g600 = Color(hex: "#266645")!
        static let g700 = Color(hex: "#1E5438")!
        static let g800 = Color(hex: "#153F29")!
        static let g900 = Color(hex: "#0C2B1B")!
        static let g950 = Color(hex: "#051B0F")!
    }

    enum Semantic {
        static let brand = Green.g500
        static let brandHover = Green.g600
        /// Selected nav row, active chip fill.
        static let brandSoft = Green.g500.opacity(0.10)
        static let warning = Color(hex: "#EA9602")!
        /// Destructive rows only.
        static let danger = Color(hex: "#DF202E")!
    }

    // MARK: - Shape and rhythm

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let full: CGFloat = 999
    }

    // MARK: - Typography

    /// Chillax carries every UI LABEL — nav items, section titles, setting labels,
    /// buttons, stat numerals. Karma carries PROSE ONLY: the sentences someone
    /// actually reads. JetBrains Mono carries keys, ids, sizes and durations.
    ///
    /// The test Akeil uses: read it in Karma, scan it in Chillax.
    enum FontName {
        static let displayRegular = "Chillax-Regular"
        static let displayMedium = "Chillax-Medium"
        static let displaySemibold = "Chillax-Semibold"
        /// The variable family, needed for weights between the static steps.
        static let displayVariable = "ChillaxVariable-Bold"

        static let proseRegular = "Karma-Regular"
        static let proseMedium = "Karma-Medium"
        static let proseSemibold = "Karma-SemiBold"

        static let monoRegular = "JetBrainsMono-Regular"
        static let monoMedium = "JetBrainsMono-Regular_Medium"
    }

    /// Chillax reads unset without negative tracking. -5% is non-optional and
    /// applies to ALL Chillax — except uppercase micro-labels, which need opening
    /// up instead and take a positive value.
    enum Tracking {
        static let display: CGFloat = -0.05
        static let wide: CGFloat = 0.08

        /// SwiftUI's `.tracking()` takes points, not ems, so it has to be resolved
        /// against the size it is used at.
        static func display(at size: CGFloat) -> CGFloat { size * Self.display }
        static func wide(at size: CGFloat) -> CGFloat { size * Self.wide }
    }

    // MARK: - Font construction

    /// Chillax at a static weight. Falls back to the system font if the family is
    /// missing, so a font-uninstall degrades instead of crashing.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .regular: name = FontName.displayRegular
        case .semibold, .bold: name = FontName.displaySemibold
        default: name = FontName.displayMedium
        }
        guard NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, size: size)
    }

    /// Chillax at an arbitrary variable weight. Buttons sit at 450 — a half-step
    /// between Regular and Medium that the static family cannot express (it snaps
    /// to 400). Verified to genuinely interpolate by measuring ink mass, so this is
    /// worth the CoreText detour rather than rounding to 400 or 500.
    static func displayVariable(_ size: CGFloat, wght: CGFloat) -> Font {
        // 'wght' as a FourCharCode.
        let wghtAxis: CFNumber = NSNumber(value: 0x77676874)
        let attrs: [CFString: Any] = [
            kCTFontNameAttribute: FontName.displayVariable as CFString,
            kCTFontVariationAttribute: [wghtAxis: NSNumber(value: Double(wght))] as CFDictionary,
        ]
        guard NSFont(name: FontName.displayVariable, size: size) != nil else {
            return Self.display(size, wght >= 500 ? .medium : .regular)
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }

    /// The button weight — 450.
    static func button(_ size: CGFloat) -> Font {
        Self.displayVariable(size, wght: 450)
    }

    /// Karma. Prose only.
    static func prose(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold: name = FontName.proseSemibold
        case .medium: name = FontName.proseMedium
        default: name = FontName.proseRegular
        }
        guard NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return .custom(name, size: size)
    }

    /// JetBrains Mono. Keys, model ids, byte sizes, durations, timestamps.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = (weight == .regular) ? FontName.monoRegular : FontName.monoMedium
        guard NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(name, size: size)
    }

    /// True when the brand families resolved. Used by the startup log so a missing
    /// font shows up in the log rather than as silently system-rendered text.
    static var brandFontsAvailable: Bool {
        NSFont(name: FontName.displayMedium, size: 13) != nil
            && NSFont(name: FontName.proseRegular, size: 13) != nil
    }
}

// MARK: - Text style modifiers

/// Font and tracking travel together — applying `BasicsTokens.display()` without
/// the matching tracking is the single easiest way to make Chillax look wrong, so
/// these modifiers bind the two.
extension View {
    /// A UI label: Chillax Medium at -5%.
    func basicsLabel(_ size: CGFloat, weight: Font.Weight = .medium) -> some View {
        self.font(BasicsTokens.display(size, weight))
            .tracking(BasicsTokens.Tracking.display(at: size))
    }

    /// An uppercase micro-label: Chillax Medium at +8%, caps applied by the caller.
    func basicsMicroLabel(_ size: CGFloat = 11) -> some View {
        self.font(BasicsTokens.display(size, .medium))
            .tracking(BasicsTokens.Tracking.wide(at: size))
            .textCase(.uppercase)
    }

    /// A button label: variable Chillax at 450, -5%.
    func basicsButtonLabel(_ size: CGFloat = 13) -> some View {
        self.font(BasicsTokens.button(size))
            .tracking(BasicsTokens.Tracking.display(at: size))
    }

    /// Prose: Karma, no tracking adjustment.
    func basicsProse(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(BasicsTokens.prose(size, weight))
    }

    /// Technical values: JetBrains Mono, no tracking adjustment.
    func basicsMono(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(BasicsTokens.mono(size, weight))
    }
}
