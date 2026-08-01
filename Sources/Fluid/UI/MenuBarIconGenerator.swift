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

    /// Menu-bar glyphs live on an 18pt square; the tile fills it edge to edge.
    private static let tileSide: CGFloat = 18
    /// The breathing room between the tile and its trailing glyph.
    private static let glyphGap: CGFloat = 5
    /// The level meter's own box, centred vertically on the tile.
    private static let meterSize = NSSize(width: 14, height: 14)
    /// The refining trail's box, centred the same way.
    private static let dotsSize = NSSize(width: 11, height: 14)

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
        let size: NSSize
        switch state {
        case .idle:
            size = NSSize(width: self.tileSide, height: self.tileSide)
        case .recording:
            size = NSSize(
                width: self.tileSide + self.glyphGap + self.meterSize.width,
                height: self.tileSide
            )
        case .refining:
            size = NSSize(
                width: self.tileSide + self.glyphGap + self.dotsSize.width,
                height: self.tileSide
            )
        }

        // `flipped: true` puts the origin top-left with y growing downward, which
        // is the space the logo path and the board's SVG are both authored in.
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            self.tilePath().fill()

            switch state {
            case .idle:
                break
            case .recording:
                self.drawLevelMeter(originX: self.tileSide + self.glyphGap)
            case .refining:
                self.drawRefiningTrail(originX: self.tileSide + self.glyphGap)
            }
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

    /// Four bars, same silhouette as the notch waveform. Static: a menu-bar
    /// template image cannot animate, so the shape has to read at a glance.
    private static func drawLevelMeter(originX: CGFloat) {
        let top = (self.tileSide - self.meterSize.height) / 2
        // x, y, height — width is 2 and the ends are fully rounded.
        let bars: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 4, 6),
            (4, 1, 12),
            (8, 3, 8),
            (12, 5.5, 3),
        ]
        for (x, y, height) in bars {
            let rect = NSRect(x: originX + x, y: top + y, width: 2, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }

    /// Three dots fading out to the right — the refining pass, not a recording.
    private static func drawRefiningTrail(originX: CGFloat) {
        let centerY = (self.tileSide - self.dotsSize.height) / 2 + 7
        let dots: [(CGFloat, CGFloat)] = [(1, 1.0), (5, 0.55), (9, 0.3)]
        for (x, alpha) in dots {
            NSColor.black.withAlphaComponent(alpha).setFill()
            let rect = NSRect(x: originX + x - 1, y: centerY - 1, width: 2, height: 2)
            NSBezierPath(ovalIn: rect).fill()
        }
        NSColor.black.setFill()
    }
}
