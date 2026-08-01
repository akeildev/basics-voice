//
//  OnboardingComponents.swift
//  fluid
//
//  Board "16 — Onboarding". The shared chrome and controls every onboarding
//  step is built from: the ground, the step rail, the fixed shell, the footer
//  bar, and the button / card / chip / meter vocabulary.
//
//  The old cinematic dark-blue treatment is gone. Onboarding is now the same
//  alpine snow ground as the rest of the app, with exactly one green moment
//  per region.
//

import AppKit
import SwiftUI

// MARK: - Ground

/// Board `16 — Onboarding · 1 Landing`.
///
/// A single soft brand wash plus the concentric "voice rings" that quote the
/// app mark. Deliberately static: the board draws the default and
/// reduce-motion states as the same still frame, so there is nothing here that
/// follows the pointer or animates.
struct FluidOnboardingLandingBackdrop: View {
    var body: some View {
        ZStack {
            BasicsTokens.Surface.bg

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: BasicsTokens.Semantic.brand.opacity(0.09), location: 0),
                    .init(color: BasicsTokens.Semantic.brand.opacity(0.03), location: 0.42),
                    .init(color: .clear, location: 0.72),
                ]),
                center: UnitPoint(x: 0.5, y: 0.14),
                startRadius: 0,
                endRadius: 900
            )

            OnboardingVoiceRings()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The four rings, struck from a point below the fold so only their tops show.
private struct OnboardingVoiceRings: View {
    /// Radius in points, stroke opacity — read off the board's SVG.
    private static let rings: [(radius: CGFloat, opacity: Double)] = [
        (150, 0.100),
        (255, 0.070),
        (365, 0.050),
        (470, 0.035),
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.7)

            for ring in Self.rings {
                let rect = CGRect(
                    x: center.x - ring.radius,
                    y: center.y - ring.radius,
                    width: ring.radius * 2,
                    height: ring.radius * 2
                )
                context.stroke(
                    Circle().path(in: rect),
                    with: .color(BasicsTokens.Semantic.brand.opacity(ring.opacity)),
                    lineWidth: 1.5
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - App mark

/// The Basics tile on an onboarding hero — the shared `BasicsMark` under the
/// board's soft brand cast.
struct FluidOnboardingAppMark: View {
    let size: CGFloat

    init(size: CGFloat = 104) {
        self.size = size
    }

    var body: some View {
        BasicsMark(size: self.size)
            .shadow(color: BasicsTokens.Semantic.brand.opacity(0.18), radius: 20, x: 0, y: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - Step rail

/// Board 16 — the uppercase micro-label plus the six-segment rail that replaces
/// the old continuous progress bar. Landing has no rail, matching the board.
struct OnboardingStepRail: View {
    /// 1-based.
    let step: Int
    let stepCount: Int
    let name: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Step \(self.step) of \(self.stepCount) · \(self.name)")
                .basicsMicroLabel()
                .foregroundStyle(BasicsTokens.Ink.faint)

            HStack(spacing: 6) {
                ForEach(1...max(self.stepCount, 1), id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= self.step
                                ? BasicsTokens.Semantic.brand
                                : BasicsTokens.Surface.borderStrong
                        )
                        .frame(width: 44, height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(self.step) of \(self.stepCount), \(self.name)")
    }
}

// MARK: - Shell

/// Board 16 — the fixed onboarding chrome. Rail at the top, the content column
/// centred in the space that is left, and the hairline footer bar. Every
/// numbered step shares it, so it is one implementable component.
struct OnboardingStepShell<Content: View, Footer: View>: View {
    /// 1-based; `nil` on the landing screen, which has no rail.
    let railStep: Int?
    let stepCount: Int
    let railName: String
    var showsScrollIndicators: Bool = false

    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            if let railStep = self.railStep {
                OnboardingStepRail(step: railStep, stepCount: self.stepCount, name: self.railName)
                    .padding(.top, 28)
                    .padding(.bottom, 8)
            }

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: self.showsScrollIndicators) {
                    VStack(spacing: 0) {
                        self.content()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
            }

            self.footer()
        }
        .background(BasicsTokens.Surface.bg.ignoresSafeArea())
    }
}

/// Board 16 — the footer bar: a hairline, Back on the left, and whatever the
/// step puts on the right (Skip is inserted on steps 5 and 6).
struct OnboardingFooterBar<Trailing: View>: View {
    let canGoBack: Bool
    let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            OnboardingActionButton(
                title: "Back",
                tone: .secondary,
                labelColor: BasicsTokens.Ink.muted,
                action: self.onBack
            )
            .disabled(!self.canGoBack)
            .keyboardShortcut(.cancelAction)

            Spacer(minLength: 12)

            self.trailing()
        }
        .padding(.horizontal, 56)
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BasicsTokens.Surface.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Buttons

enum OnboardingButtonTone {
    /// The one filled green moment in a region.
    case primary
    /// Everything reversible — white, hairline outline.
    case secondary
    /// A brandSoft fill with brand ink. Used for "Active now" / "Using", which
    /// state a fact rather than offer an action, and so ship disabled.
    case soft
    /// Delete. Neutral outline, danger ink.
    case destructive
    /// No fill, no outline — "Show other models".
    case quiet
}

/// Board 16 — every onboarding button. Capsule by default; the model and AI
/// cards pass `cornerRadius: 10` for their full-width action slot.
struct OnboardingActionButton: View {
    let title: String
    var systemImage: String?
    var tone: OnboardingButtonTone = .secondary
    var height: CGFloat = 44
    var horizontalPadding: CGFloat = 24
    var labelSize: CGFloat = 15
    var iconSize: CGFloat = 13
    var width: CGFloat?
    var expands: Bool = false
    /// Overrides the tone's default ink — Back and Skip read muted on the board
    /// while the other outlined buttons read at full strength.
    var labelColor: Color?
    var cornerRadius: CGFloat?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var shape: AnyShape {
        if let cornerRadius = self.cornerRadius {
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        return AnyShape(Capsule())
    }

    private var fill: Color {
        switch self.tone {
        case .primary:
            guard self.isEnabled else { return BasicsTokens.Surface.muted }
            return self.isHovered ? BasicsTokens.Green.g600 : BasicsTokens.Semantic.brand
        case .soft:
            return BasicsTokens.Semantic.brandSoft
        case .secondary, .destructive:
            guard self.isEnabled else { return BasicsTokens.Surface.muted }
            return self.isHovered ? BasicsTokens.Surface.muted : BasicsTokens.Surface.card
        case .quiet:
            return self.isHovered && self.isEnabled ? BasicsTokens.Surface.muted : .clear
        }
    }

    private var stroke: Color {
        switch self.tone {
        case .primary:
            return self.isEnabled ? .clear : BasicsTokens.Surface.border
        case .soft, .quiet:
            return .clear
        case .secondary, .destructive:
            guard self.isEnabled else { return BasicsTokens.Surface.border }
            return BasicsTokens.Surface.borderStrong
        }
    }

    private var ink: Color {
        guard self.isEnabled else {
            return self.tone == .soft ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.faint
        }
        if let labelColor = self.labelColor { return labelColor }
        switch self.tone {
        case .primary: return .white
        case .soft: return BasicsTokens.Semantic.brand
        case .destructive: return BasicsTokens.Semantic.danger
        case .secondary: return BasicsTokens.Ink.foreground
        case .quiet: return BasicsTokens.Ink.muted
        }
    }

    private var shadowOpacity: Double {
        guard self.tone == .primary, self.isEnabled else { return 0 }
        return self.isHovered ? 0.28 : 0.20
    }

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: self.systemImage == nil ? 0 : 8) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: self.iconSize, weight: .semibold))
                }

                Text(self.title)
                    .basicsButtonLabel(self.labelSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(self.ink)
            .padding(.horizontal, self.horizontalPadding)
            .frame(width: self.width, height: self.height)
            .frame(maxWidth: self.expands ? .infinity : nil)
            .background(self.shape.fill(self.fill))
            .overlay(self.shape.stroke(self.stroke, lineWidth: 1))
            .shadow(
                color: BasicsTokens.Semantic.brand.opacity(self.shadowOpacity),
                radius: self.isHovered ? 14 : 10,
                x: 0,
                y: self.isHovered ? 8 : 5
            )
            .contentShape(self.shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.14), value: self.isHovered)
        .onHover { self.isHovered = $0 && self.isEnabled }
        .accessibilityLabel(self.title)
    }
}

// MARK: - Card

/// Board 16 — the white card the onboarding steps group things into: model
/// routes, the permission list, the try-it panel, the AI provider card.
struct OnboardingCard<Content: View>: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = BasicsTokens.Radius.xl
    var padding: CGFloat = 20
    var shadow: BasicsShadow = BasicsShadow(
        color: BasicsTokens.Ink.foreground.opacity(0.04),
        radius: 1,
        y: 1
    )
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)

        return self.content()
            .padding(self.padding)
            .background(shape.fill(BasicsTokens.Surface.card))
            .overlay(
                shape.stroke(
                    self.isSelected ? BasicsTokens.Semantic.brand : BasicsTokens.Surface.border,
                    lineWidth: self.isSelected ? 2 : 1
                )
            )
            .basicsShadows([
                self.isSelected
                    ? BasicsShadow(color: BasicsTokens.Semantic.brand.opacity(0.10), radius: 15, y: 10)
                    : self.shadow,
            ])
    }
}

// MARK: - Chips, pills and badges

/// The brandSoft capsule that names the chosen language on the voice-engine
/// step and quotes the example sentence on the try-it step.
struct OnboardingChip: View {
    let text: String
    var height: CGFloat = 24
    var horizontalPadding: CGFloat = 12
    var usesProse: Bool = false
    var size: CGFloat = 12

    var body: some View {
        Group {
            if self.usesProse {
                Text(self.text).basicsProse(self.size)
            } else {
                Text(self.text).basicsLabel(self.size)
            }
        }
        .foregroundStyle(BasicsTokens.Semantic.brand)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, self.horizontalPadding)
        .frame(height: self.height)
        .background(Capsule().fill(BasicsTokens.Semantic.brandSoft))
    }
}

/// READY / NEEDED / IN SETTINGS on the permissions step. Fixed 104pt wide so
/// the three lanes line up across rows.
struct OnboardingStatusPill: View {
    let text: String
    let isReady: Bool

    var body: some View {
        Text(self.text)
            .basicsMicroLabel()
            .foregroundStyle(self.isReady ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .frame(width: 104, height: 22)
            .background(
                Capsule().fill(
                    self.isReady ? BasicsTokens.Semantic.brandSoft : BasicsTokens.Surface.muted
                )
            )
    }
}

/// RECOMMENDED on the engine card, EXPERIMENTAL on the built-in AI card.
struct OnboardingBadge: View {
    enum Tone {
        case brand
        case warning
    }

    let text: String
    var tone: Tone = .brand
    var systemImage: String?

    private var ink: Color {
        switch self.tone {
        case .brand: return BasicsTokens.Semantic.brand
        case .warning: return BasicsTokens.Semantic.warning.onboardingDarkened(by: 0.28)
        }
    }

    private var fill: Color {
        switch self.tone {
        case .brand: return BasicsTokens.Semantic.brandSoft
        case .warning: return BasicsTokens.Semantic.warning.opacity(0.16)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }

            Text(self.text)
                .basicsMicroLabel(10)
                .lineLimit(1)
        }
        .foregroundStyle(self.ink)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(Capsule().fill(self.fill))
    }
}

// MARK: - Meters

/// Speed / Accuracy on an engine card. Fixed label and value lanes so the two
/// rows and the download-size row below them share one grid.
struct OnboardingMeterRow: View {
    let systemImage: String
    let label: String
    /// 0...1.
    let value: Double
    let isActive: Bool

    private var clamped: Double {
        min(max(self.value, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(self.isActive ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.faint)
                .frame(width: 14)

            Text(self.label)
                .basicsLabel(12)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(BasicsTokens.Surface.muted)

                    Capsule()
                        .fill(self.isActive ? BasicsTokens.Semantic.brand : BasicsTokens.Surface.borderStrong)
                        .frame(width: max(4, proxy.size.width * CGFloat(self.clamped)))
                }
            }
            .frame(height: 5)

            Text("\(Int((self.clamped * 100).rounded()))%")
                .basicsMono(11, weight: .medium)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .lineLimit(1)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(self.label) \(Int((self.clamped * 100).rounded())) percent")
    }
}

/// The determinate / indeterminate track the engine and AI cards share while a
/// model is downloading, optimizing, loading or being removed.
struct OnboardingProgressTrack: View {
    /// `nil` renders the indeterminate bar.
    let fraction: Double?

    var body: some View {
        Group {
            if let fraction = self.fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BasicsTokens.Surface.muted)

                        Capsule()
                            .fill(BasicsTokens.Semantic.brand)
                            .frame(width: max(4, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
                    }
                }
                .frame(height: 4)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(BasicsTokens.Semantic.brand)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Landing hero

/// Board `16 — Onboarding · 1 Landing`. The mark, the two-line headline whose
/// second line is the region's one green moment, two prose lines, and the
/// primary action.
struct FluidOnboardingLandingHero<Actions: View>: View {
    let title: String
    let accentTitle: String
    let firstDetail: String
    let secondDetail: String
    let actions: Actions

    init(
        title: String,
        accentTitle: String,
        firstDetail: String,
        secondDetail: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.accentTitle = accentTitle
        self.firstDetail = firstDetail
        self.secondDetail = secondDetail
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            FluidOnboardingAppMark(size: 104)
                .padding(.bottom, 44)

            VStack(spacing: 0) {
                Text(self.title)
                    .basicsLabel(68)
                    .foregroundStyle(BasicsTokens.Ink.foreground)

                Text(self.accentTitle)
                    .basicsLabel(68)
                    .foregroundStyle(BasicsTokens.Semantic.brand)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.bottom, 26)

            VStack(spacing: 6) {
                Text(self.firstDetail)
                    .basicsProse(18)
                    .foregroundStyle(BasicsTokens.Ink.foreground)

                Text(self.secondDetail)
                    .basicsProse(16)
                    .foregroundStyle(BasicsTokens.Ink.muted)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.bottom, 40)

            self.actions
        }
        .padding(.horizontal, 200)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Landing primary button (AppKit)

/// The landing "Next" stays an `NSButton` so it keeps the return-key equivalent
/// and the AppKit hit-testing the rest of the landing relies on. Restyled to the
/// Basics primary pill: brand fill, white Chillax Variable 450 at 16, capsule,
/// soft brand cast.
struct FluidOnboardingLandingPrimaryButton: NSViewRepresentable {
    static let size = CGSize(width: 168, height: 48)

    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: self.action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = LandingPrimaryNSButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.wantsLayer = true
        button.focusRingType = .none
        button.keyEquivalent = "\r"
        button.keyEquivalentModifierMask = []
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.setAccessibilityLabel(self.title)
        button.update(title: self.title)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = self.action
        button.setAccessibilityLabel(self.title)

        guard let button = button as? LandingPrimaryNSButton else {
            button.title = self.title
            return
        }

        button.update(title: self.title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            self.action()
        }
    }
}

private final class LandingPrimaryNSButton: NSButton {
    private static let restColor = NSColor(BasicsTokens.Semantic.brand)
    private static let hoverColor = NSColor(BasicsTokens.Green.g600)
    private static let pressedColor = NSColor(BasicsTokens.Green.g700)

    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    override var isHighlighted: Bool {
        didSet { self.applyBackground() }
    }

    override var intrinsicContentSize: NSSize {
        FluidOnboardingLandingPrimaryButton.size
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.isEnabled, !self.isHidden, self.alphaValue > 0, self.bounds.contains(point) else {
            return nil
        }
        return self
    }

    override func layout() {
        super.layout()
        self.layer?.cornerRadius = self.bounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            self.removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self)
        self.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.isHovering = true
        self.applyBackground()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.isHovering = false
        self.applyBackground()
    }

    func update(title: String) {
        self.title = title
        self.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: OnboardingAppKitFont.buttonLabel(size: 16),
                .foregroundColor: NSColor.white,
                .kern: BasicsTokens.Tracking.display(at: 16),
            ]
        )
        self.image = Self.arrowImage
        self.alignment = .center
        self.layer?.masksToBounds = false
        self.layer?.cornerRadius = self.bounds.height > 0 ? self.bounds.height / 2 : 24
        self.layer?.shadowColor = Self.restColor.withAlphaComponent(0.22).cgColor
        self.applyBackground()
    }

    private static let arrowImage: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image?.tinted(with: .white)
    }()

    private func applyBackground() {
        let color: NSColor
        if self.isHighlighted {
            color = Self.pressedColor
        } else {
            color = self.isHovering ? Self.hoverColor : Self.restColor
        }

        self.layer?.backgroundColor = color.cgColor
        self.layer?.shadowOpacity = self.isHighlighted ? 0.14 : 0.22
        self.layer?.shadowRadius = self.isHighlighted ? 6 : 12
        self.layer?.shadowOffset = NSSize(width: 0, height: self.isHighlighted ? 3 : 6)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: self.size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Chillax Variable at the button weight, as an `NSFont` — the AppKit landing
/// button cannot take the SwiftUI `BasicsTokens.button()` face directly.
private enum OnboardingAppKitFont {
    static func buttonLabel(size: CGFloat) -> NSFont {
        let variationKey = NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String)
        // 'wght' as a FourCharCode, matching `BasicsTokens.displayVariable`.
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: BasicsTokens.FontName.displayVariable,
            variationKey: [NSNumber(value: 0x7767_6874): NSNumber(value: 450.0)],
        ])

        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return NSFont(name: BasicsTokens.FontName.displayMedium, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }
}

// MARK: - Colour helpers

extension Color {
    /// Walks a token toward black. The board's EXPERIMENTAL ink is the warning
    /// amber darkened until it reads on its own 16% fill, rather than a second
    /// hand-picked hex.
    func onboardingDarkened(by amount: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return Color(
            red: Double(base.redComponent) * (1 - amount),
            green: Double(base.greenComponent) * (1 - amount),
            blue: Double(base.blueComponent) * (1 - amount),
            opacity: Double(base.alphaComponent)
        )
    }
}

// MARK: - Legacy

/// Retired. The onboarding flow no longer has a blue; this survives only for
/// `ContentView`'s accessibility floating guide, which is another cluster's
/// file. Nothing in board 16 uses it.
enum FluidOnboardingLandingColors {
    static let blue = Color(red: 0.10, green: 0.46, blue: 1.0)
}
