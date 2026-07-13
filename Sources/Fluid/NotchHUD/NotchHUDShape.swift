import SwiftUI

/// The notch-hugging outline: flush with the screen's top edge, concave fillets
/// where it meets the menu bar, convex rounded corners at the bottom.
///
/// Clean-room implementation — shape approach inspired by boring.notch
/// (TheBoredTeam, GPLv3); no code copied.
struct NotchHUDShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(self.topCornerRadius, self.bottomCornerRadius) }
        set {
            self.topCornerRadius = newValue.first
            self.bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(self.topCornerRadius, rect.height / 2)
        let b = min(self.bottomCornerRadius, rect.height / 2)
        var p = Path()

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave fillet flowing from the screen top edge into the left side
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // Convex bottom-left corner
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // Convex bottom-right corner
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Concave fillet back up to the screen top edge
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
