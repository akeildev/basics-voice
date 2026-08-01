//
//  SetupComponents.swift
//  fluid
//
//  Board "15 — Components" § Setup step and § Instruction step.
//

import AppKit
import SwiftUI

// MARK: - Setup Step View

/// The rows a new user works through on Home. The whole row is the target until
/// it is done; a completed or informational row stops being a button.
struct SetupStepView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let step: Int
    let title: String
    let description: String
    let status: SetupStatus
    let action: () -> Void
    var actionButtonTitle: String = "Configure"
    var showActionButton: Bool = true

    enum SetupStatus {
        case pending, completed, inProgress
    }

    private var isTarget: Bool {
        self.status == .pending && self.showActionButton
    }

    private var isRaised: Bool {
        self.isTarget && self.isHovered
    }

    var body: some View {
        // Only a pending row is a button. A completed or informational row is
        // rendered bare rather than as a `.disabled` button — SwiftUI dims a
        // disabled plain button, and the board draws these at full strength.
        Group {
            if self.isTarget {
                Button(action: self.action) { self.row }
                    .buttonStyle(.plain)
                    .onHover { self.isHovered = $0 }
            } else {
                self.row
            }
        }
        .animation(.easeOut(duration: 0.18), value: self.isHovered)
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 14) {
            self.disc
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(self.description)
                    .basicsProse(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The trailing lane is always 28 tall and always present, so an
            // informational row still lines its text column up with the rest.
            self.trailing
                .frame(height: 28)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(self.rowSurface)
        .contentShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous))
    }

    // MARK: Row surface

    @ViewBuilder
    private var rowSurface: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
        let accent = self.theme.palette.accent

        switch self.status {
        case .completed:
            shape
                .fill(accent.opacity(0.06))
                .overlay(shape.stroke(accent.opacity(0.22), lineWidth: 1))

        case .inProgress:
            shape
                .fill(self.theme.palette.cardBackground)
                .overlay(shape.stroke(accent.opacity(0.35), lineWidth: 1))
                .shadow(color: accent.opacity(0.05), radius: 1, x: 0, y: 1)

        case .pending:
            shape
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    shape.stroke(
                        self.isRaised
                            ? BasicsBorder.strong(self.theme, self.colorScheme)
                            : self.theme.palette.cardBorder,
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: BasicsTokens.Ink.foreground.opacity(self.isRaised ? 0.06 : 0),
                    radius: self.isRaised ? 3 : 0,
                    x: 0,
                    y: self.isRaised ? 2 : 0
                )
        }
    }

    // MARK: Leading disc

    @ViewBuilder
    private var disc: some View {
        let accent = self.theme.palette.accent

        switch self.status {
        case .completed:
            ZStack {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }

        case .inProgress:
            ZStack {
                Circle().fill(accent.opacity(0.10))
                // Drawn rather than a system ProgressView: the board specifies a
                // brand ring on a 25% track, and macOS's circular spinner does not
                // reliably take a tint.
                SetupSpinner(color: accent)
                    .frame(width: 16, height: 16)
            }

        case .pending:
            ZStack {
                Circle().fill(self.theme.palette.sidebarBackground)
                Circle().stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                Text("\(self.step)")
                    .basicsLabel(12)
                    .foregroundStyle(
                        self.isRaised ? self.theme.palette.primaryText : self.theme.palette.secondaryText
                    )
            }
        }
    }

    // MARK: Trailing chip

    @ViewBuilder
    private var trailing: some View {
        let accent = self.theme.palette.accent

        switch self.status {
        case .completed:
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Done")
                    .basicsButtonLabel(12)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(accent, in: Capsule())

        case .inProgress:
            Text("Working")
                .basicsButtonLabel(12)
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(accent.opacity(0.10), in: Capsule())

        case .pending:
            if self.showActionButton {
                HStack(spacing: 6) {
                    Text(self.actionButtonTitle)
                        .basicsButtonLabel(12)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(self.isHovered ? BasicsTokens.Green.g600 : accent)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(accent.opacity(self.isHovered ? 0.18 : 0.10), in: Capsule())
            } else {
                // Held empty on purpose — see the comment at the call site above.
                Color.clear.frame(width: 28)
            }
        }
    }
}

// MARK: - In-progress ring

/// A 2px brand quarter-arc turning on a 25% track — the board's in-progress disc.
private struct SetupSpinner: View {
    let color: Color
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(self.color.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(self.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(self.spinning ? 360 : 0))
        }
        .padding(1)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                self.spinning = true
            }
        }
    }
}

// MARK: - Instruction Step

/// Read-only instructions — a permission walkthrough, a how-to. Never a target,
/// so it never gets a border or a hover. The caller decides whether the rows sit
/// in a muted well (a permission the user must leave the app for) or straight on
/// the surface (an in-app how-to).
struct InstructionStep: View {
    @Environment(\.theme) private var theme
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.10))

                Text("\(self.number)")
                    .basicsLabel(11)
                    .foregroundStyle(self.theme.palette.accent)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(self.description)
                    .basicsProse(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
