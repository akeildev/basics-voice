import AppKit

/// The Basics mark as it is drawn in the macOS menu bar.
///
/// State is carried by SHAPE, never by colour. The status item is a template
/// image, so macOS — not this app — decides whether the single ink is black or
/// white, and a brand fill would simply be thrown away. Recording and refining
/// therefore keep the tile and grow a trailing glyph instead: a four-bar level
/// meter while audio is coming in, a three-dot trail while the transcript is
/// being refined. The meter is the same waveform the notch draws, at 18pt.
///
/// Every number below is the logo's own geometry, transcribed from the Paper
/// board `19 — Chrome` (`S1 · Menu bar mark`): a 972×972 tile with corner
/// radius 216 and the "1" knocked out of it under the even-odd rule.
enum MenuBarIconGenerator {

    /// What the mark is saying. Driven by `MenuBarManager`, never guessed.
    enum State {
        /// Nothing is running — the bare tile.
        case idle
        /// Audio is being captured — tile plus the level meter.
        case recording
        /// Capture finished, an AI pass is still in flight — tile plus dots.
        case refining
    }

    // MARK: - Metrics

    /// Menu-bar glyphs get an 18pt square; the tile sits well inside it. Small
    /// and constant is the whole point — the mark is an identity, not a status
    /// light, and the bar has enough moving parts already.
    private static let tileSide: CGFloat = 15

    /// The logo is authored on a 972-unit square.
    private static let logoUnits: CGFloat = 972
    private static let logoCornerRadius: CGFloat = 216

    // MARK: - Public

    /// The template image for a state. Cached: the menu bar asks for this on
    /// every recording transition and the geometry never changes.
    static func image(for state: State) -> NSImage {
        if let cached = self.cache[state] { return cached }
        let image = self.render(state)
        self.cache[state] = image
        return image
    }

    private static var cache: [State: NSImage] = [:]

    // MARK: - Rendering

    private static func render(_ state: State) -> NSImage {
        // Every state draws the same mark. It used to grow a level meter while
        // recording and a trail while refining, which made the status item
        // resize and shove the rest of the menu bar sideways on every dictation.
        // The recording tab already shows the level, live.
        let size = NSSize(width: self.tileSide, height: self.tileSide)

        // `flipped: true` puts the origin top-left with y growing downward, which
        // is the space the logo path and the board's SVG are both authored in.
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            self.tilePath().fill()
            return true
        }

        // Template: macOS owns the ink colour and the menu-bar vibrancy.
        image.isTemplate = true
        return image
    }

    /// The tile with the "1" knocked out of it — one path, even-odd filled, so
    /// the numeral is a hole rather than a second colour.
    private static func tilePath() -> NSBezierPath {
        let path = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: self.logoUnits, height: self.logoUnits),
            xRadius: self.logoCornerRadius,
            yRadius: self.logoCornerRadius
        )
        path.append(self.numeralOnePath())
        path.windingRule = .evenOdd

        // Scale the 972-unit drawing down onto the 18pt tile. The numeral runs
        // past the tile's bottom edge in the source geometry; the image bounds
        // clip it, exactly as the SVG viewBox does on the board.
        path.transform(using: AffineTransform(scale: self.tileSide / self.logoUnits))
        return path
    }

    /// The "1", in logo units, y-down.
    private static func numeralOnePath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 552.5, y: 1010))
        path.line(to: NSPoint(x: 552.5, y: 350.3))
        path.curve(
            to: NSPoint(x: 481.5, y: 270.0),
            controlPoint1: NSPoint(x: 552.5, y: 298.8),
            controlPoint2: NSPoint(x: 524.7, y: 270.0)
        )
        path.curve(
            to: NSPoint(x: 400.2, y: 295.7),
            controlPoint1: NSPoint(x: 454.7, y: 270.0),
            controlPoint2: NSPoint(x: 426.9, y: 280.3)
        )
        path.line(to: NSPoint(x: 223.1, y: 393.5))
        path.line(to: NSPoint(x: 270.5, y: 492.3))
        path.line(to: NSPoint(x: 429.0, y: 402.8))
        path.curve(
            to: NSPoint(x: 442.4, y: 396.6),
            controlPoint1: NSPoint(x: 433.1, y: 399.7),
            controlPoint2: NSPoint(x: 437.2, y: 396.6)
        )
        path.curve(
            to: NSPoint(x: 447.5, y: 403.8),
            controlPoint1: NSPoint(x: 446.5, y: 396.6),
            controlPoint2: NSPoint(x: 447.5, y: 399.7)
        )
        path.line(to: NSPoint(x: 447.5, y: 1010))
        path.close()
        return path
    }

}
