import SwiftUI

// MARK: - Geometry

/// The Basics mark, transcribed from `~/basics-brand/Basics-logo.svg` — one
/// vector, drawn in a 972-unit square.
///
/// Two things must not be "tidied":
///
/// 1. The corner radius is **always** 216/972 = 0.222 of the tile, so the mark
///    never looks softer at 16pt than it does at 64pt.
/// 2. The glyph runs to y = 1010, past the tile edge at 972, and is clipped back.
///    Ending it at 972 instead would put two coincident edges on top of each
///    other; they antialias independently and leave a green hairline under the
///    stem. The overshoot is load-bearing.
enum BasicsMarkGeometry {
    static let canvas: CGFloat = 972
    /// 216 / 972.
    static let cornerRatio: CGFloat = 216.0 / 972.0

    static func tilePath(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Path(
            roundedRect: CGRect(x: rect.minX, y: rect.minY, width: side, height: side),
            cornerRadius: side * Self.cornerRatio,
            // Circular, not continuous. The brand asset's corner is an SVG
            // `rx=216` arc; Apple's continuous squircle runs further along the
            // edge and reads visibly rounder at the same radius. Rendered at
            // 384 against a rasterised `Basics-logo.svg` — circular matches.
            style: .circular
        )
    }

    /// The "1". Authored in design units, then scaled into `rect`.
    static func glyphPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 552.5, y: 1010))
        path.addLine(to: CGPoint(x: 552.5, y: 350.3))
        path.addCurve(
            to: CGPoint(x: 481.5, y: 270.0),
            control1: CGPoint(x: 552.5, y: 298.8),
            control2: CGPoint(x: 524.7, y: 270.0)
        )
        path.addCurve(
            to: CGPoint(x: 400.2, y: 295.7),
            control1: CGPoint(x: 454.7, y: 270.0),
            control2: CGPoint(x: 426.9, y: 280.3)
        )
        path.addLine(to: CGPoint(x: 223.1, y: 393.5))
        path.addLine(to: CGPoint(x: 270.5, y: 492.3))
        path.addLine(to: CGPoint(x: 429.0, y: 402.8))
        path.addCurve(
            to: CGPoint(x: 442.4, y: 396.6),
            control1: CGPoint(x: 433.1, y: 399.7),
            control2: CGPoint(x: 437.2, y: 396.6)
        )
        path.addCurve(
            to: CGPoint(x: 447.5, y: 403.8),
            control1: CGPoint(x: 446.5, y: 396.6),
            control2: CGPoint(x: 447.5, y: 399.7)
        )
        path.addLine(to: CGPoint(x: 447.5, y: 1010))
        path.closeSubpath()

        let scale = min(rect.width, rect.height) / Self.canvas
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}

// MARK: - The mark

/// Board "15 — Components" § In-app mark.
///
/// Everywhere the app draws itself inside its own window. Replaces the geometric
/// "Fluid F" that used to live here.
struct BasicsMark: View {
    enum Ink {
        /// Green tile, white glyph — the everyday mark.
        case brand
        /// One ink, the 1 knocked out as a hole. For the notch and dark overlays,
        /// where a second fill would read as a sticker.
        case knockout(Color)
    }

    let size: CGFloat
    let ink: Ink

    init(size: CGFloat = 24, ink: Ink = .brand) {
        self.size = size
        self.ink = ink
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let tile = BasicsMarkGeometry.tilePath(in: rect)
            let glyph = BasicsMarkGeometry.glyphPath(in: rect)

            switch self.ink {
            case .brand:
                context.fill(tile, with: .color(BasicsTokens.Semantic.brand))
                context.clip(to: tile)
                context.fill(glyph, with: .color(.white))

            case let .knockout(color):
                var combined = tile
                combined.addPath(glyph)
                // The tile clip both rounds the corners and removes the y=1010
                // overshoot, which under even-odd would otherwise fill as a stub.
                context.clip(to: tile)
                context.fill(combined, with: .color(color), style: FillStyle(eoFill: true))
            }
        }
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }
}

/// The name the app used for its in-window mark. Kept so no call site can fall
/// back to the retired Fluid F — it now resolves to the Basics tile.
typealias FluidIcon = BasicsMark

// MARK: - Preview

#Preview("Basics mark") {
    VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .bottom, spacing: 20) {
            BasicsMark(size: 64)
            BasicsMark(size: 32)
            BasicsMark(size: 16)
        }

        HStack(spacing: 12) {
            BasicsMark(size: 24)
            Text("basics voice")
                .basicsLabel(15)
        }

        HStack(spacing: 20) {
            BasicsMark(size: 32, ink: .knockout(BasicsTokens.Ink.foreground))
            BasicsMark(size: 16, ink: .knockout(.white))
                .padding(8)
                .background(BasicsTokens.Ink.foreground)
        }
    }
    .padding(32)
    .background(BasicsTokens.Surface.bg)
}
