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
        /// App ground — snow, a full step below the cards so white reads as
        /// raised. Contrast in this app comes from TONE + SHADOW, not lines
        /// (Akeil: cards were white-on-white and the app leaned on hairlines).
        static let bg = Color(hex: "#EEF1EF")!
        /// Raised surface. Pure white against the deeper ground.
        static let card = Color.white
        /// Sidebar ground — one step deeper again.
        static let sidebar = Color(hex: "#E8ECEA")!
        /// Inset wells on white cards.
        static let muted = Color(hex: "#EAEEEB")!
        /// Hairlines are a whisper now — tone does the separating. Kept only
        /// where two same-tone regions genuinely touch.
        static let border = Color.black.opacity(0.05)
        /// Control outlines (fields, segmented) — still quiet.
        static let borderStrong = Color.black.opacity(0.10)
    }

    /// The card shadow pair — soft and diffuse, never a hard drop. Ambient +
    /// key, tuned for the #EEF1EF ground.
    enum Elevation {
        static let cardAmbient = Color.black.opacity(0.05)
        static let cardKey = Color.black.opacity(0.08)
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

// MARK: - Dark ramp (floating overlays only)

/// The overlays — the dictation panel, its three menus, and the dictionary
/// correction panel — are the only surfaces in the app that are always dark.
/// They float over whatever the user is actually doing, so they never follow the
/// light page palette and never follow the theme preference.
///
/// `green500` is the logo green and is correct on paper; on a `#0E120F` ground it
/// drops under 3:1, so the dark ramp steps up to `g400` and uses `g300` for the
/// text that sits inside an accent-tinted fill. Every value below is read off the
/// Paper boards `17 — Dictation overlay · dark` and `18 — Correction overlays · dark`.
extension BasicsTokens {
    enum Dark {
        // MARK: Surfaces

        /// The board ground. Also the ink colour for text sitting ON the accent.
        static let ground = Color(hex: "#0E120F")!
        /// The dictation panel at small / medium / large.
        static let card = Color(hex: "#151A17")!
        /// The pill, and the correction panel — one step below `card` so the
        /// 1px gradient rim reads at 100pt wide.
        static let panel = Color(hex: "#0B0E0C")!
        /// Menu popovers, which sit ABOVE a panel and so have to lift off it.
        static let menu = Color(hex: "#1A201C")!

        // MARK: Lines

        /// The 1px rim around every dark panel.
        static let border = Color.white.opacity(0.10)
        /// Separators inside a panel.
        static let hairline = Color.white.opacity(0.06)

        // MARK: Ink

        static let ink = Color(hex: "#F1F4F2")!
        /// Chip labels and secondary values.
        static let inkSubtle = Color(hex: "#DCE2DE")!
        static let muted = Color(hex: "#949A96")!
        /// Micro-labels, mono annotations, helper sentences.
        static let faint = Color(hex: "#8A918C")!

        // MARK: Accent

        static let accent = Green.g400
        /// Accent text on an accent-tinted fill (`g300`, lifted for contrast).
        static let accentInk = Color(hex: "#8FD0AC")!
        static let accentSoft = Green.g400.opacity(0.14)
        static let accentStrong = Green.g400.opacity(0.16)
        static let accentBorder = Green.g400.opacity(0.32)

        // MARK: Semantic

        /// Warning on dark — the light-page `#EA9602` goes muddy here.
        static let warning = Color(hex: "#EAB146")!
        static let danger = Color(hex: "#E0645F")!

        // MARK: Chips

        static let chipFill = Color.white.opacity(0.07)
        static let chipFillHover = Color.white.opacity(0.12)
        static let chipBorder = Color.white.opacity(0.09)
        static let chipBorderHover = Color.white.opacity(0.16)
        /// Menu row at rest / hovered.
        static let rowHover = Color.white.opacity(0.08)
        /// Round icon buttons (retry, dismiss, back).
        static let iconButton = Color.white.opacity(0.12)

        // MARK: Mode colours

        /// Re-mapped onto the Basics ramp: the old overlay blues and reds were
        /// off-brand. Dictate is the one green moment on this surface.
        static let modeDictate = Green.g400
        static let modeDictateInk = Color(hex: "#8FD0AC")!
        static let modeEdit = Color(hex: "#7C9CE8")!
        static let modeEditInk = Color(hex: "#A9C0F2")!
        static let modeCommand = Color(hex: "#E0645F")!
        static let modeCommandInk = Color(hex: "#F0A29E")!

        // MARK: Waveform

        /// Live bars in the pill, which has no mode label to carry the colour.
        static let barPill = Color.white.opacity(0.88)
        /// Bars while an AI pass is in flight.
        static let barProcessing = Color.white.opacity(0.55)
        /// Bars while the engine is still warming up.
        static let barInert = Color.white.opacity(0.18)
    }
}
