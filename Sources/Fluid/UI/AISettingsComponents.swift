//
//  AISettingsComponents.swift
//  fluid
//
//  Shared primitives for the AI settings family. Rebuilt for the Basics redesign
//  (boards 02b / 02c — Voice engine): flat chips, hairline-separated rows, thin
//  brand meters on a muted track. The old glass LiquidBar / LiquidLayer meters
//  were deleted along with their only call site (the voice-engine stats panel).
//
//  Every colour resolves through `theme.palette` so the same components hold up
//  under the dark theme; only the tokens the palette has no slot for (danger,
//  borderStrong, radii) come straight from BasicsTokens.
//

import Combine
import SwiftUI

// MARK: - Chips

/// The chip registers the Basics boards use. Fill and text always travel
/// together, so callers pick a register rather than a colour.
enum VoiceEngineChipStyle {
    /// Brand fill, white text — the single "this one is live" moment in a row.
    case brandFilled
    /// Brand at 10%, brand text — a positive but secondary fact (NEW, Apple Silicon).
    case brandSoft
    /// Muted fill, muted text — the neutral default.
    case muted
    /// Card fill, muted text — a neutral chip sitting ON a tinted row.
    case card
    /// Card fill + hairline, muted text — a transient state (PREVIEWING).
    case outlined

    func fill(_ theme: AppTheme) -> Color {
        switch self {
        case .brandFilled: return theme.palette.accent
        case .brandSoft: return theme.palette.accent.opacity(0.10)
        case .muted: return theme.palette.sidebarBackground
        case .card, .outlined: return theme.palette.cardBackground
        }
    }

    func ink(_ theme: AppTheme) -> Color {
        switch self {
        case .brandFilled: return .white
        case .brandSoft: return theme.palette.accent
        case .muted, .card, .outlined: return theme.palette.secondaryText
        }
    }

    func stroke(_ theme: AppTheme) -> Color? {
        switch self {
        case .outlined: return theme.palette.cardBorder
        default: return nil
        }
    }
}

/// 19pt uppercase micro-chip — ACTIVE / ON DEVICE / BUILT IN / NEW / PREVIEWING.
struct VoiceEngineStatusChip: View {
    @Environment(\.theme) private var theme

    let text: String
    var style: VoiceEngineChipStyle = .muted

    var body: some View {
        Text(self.text)
            .basicsMicroLabel(10)
            .foregroundStyle(self.style.ink(self.theme))
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(
                Capsule()
                    .fill(self.style.fill(self.theme))
                    .overlay {
                        if let stroke = self.style.stroke(self.theme) {
                            Capsule().stroke(stroke, lineWidth: 1)
                        }
                    }
            )
    }
}

/// 22pt sentence-case chip used by the stats panel (size on disk, Apple Silicon,
/// language support). `mono` switches the label to JetBrains Mono for byte sizes.
struct VoiceEngineValueChip: View {
    @Environment(\.theme) private var theme

    let text: String
    var style: VoiceEngineChipStyle = .muted
    var mono: Bool = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(BasicsTokens.display(11, .medium))
            }
            if self.mono {
                Text(self.text).basicsMono(11)
            } else {
                Text(self.text).basicsLabel(11)
            }
        }
        .foregroundStyle(self.style.ink(self.theme))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(self.style.fill(self.theme)))
    }
}

// MARK: - Meters and progress

/// Speed / Accuracy meter: uppercase micro-label, mono percentage, then a 6pt
/// brand fill on a muted track. Re-animates when the model behind it changes.
struct VoiceEngineMeter: View {
    @Environment(\.theme) private var theme

    let label: String
    /// 0...1
    let value: Double
    /// Changing this re-animates the fill (pass the model id).
    var animationKey: String = ""

    @State private var animatedValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.label)
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int((self.value * 100).rounded()))%")
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(self.theme.palette.sidebarBackground)
                    Capsule()
                        .fill(self.theme.palette.accent)
                        .frame(width: max(0, min(1, self.animatedValue)) * geo.size.width)
                }
            }
            .frame(height: 6)
        }
        .onAppear { self.animatedValue = self.value }
        .onChange(of: self.value) { _, newValue in
            withAnimation(.easeOut(duration: 0.35)) { self.animatedValue = newValue }
        }
        .onChange(of: self.animationKey) { _, _ in
            withAnimation(.easeOut(duration: 0.35)) { self.animatedValue = self.value }
        }
    }
}

/// 4pt download track inside a model row.
struct VoiceEngineProgressTrack: View {
    @Environment(\.theme) private var theme

    /// nil = work is under way but the service has not reported a fraction yet.
    let progress: Double?
    var isDimmed: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(self.theme.palette.sidebarBackground)
                Capsule()
                    .fill(self.isDimmed ? BasicsTokens.Surface.borderStrong : self.theme.palette.accent)
                    .frame(width: max(0, min(1, self.progress ?? 0)) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Buttons

/// Pill action button. `.secondary` is the card-on-hairline default (Activate,
/// Download, Cancel, Retry); `.primary` is the one brand moment (Open dictionary).
struct VoiceEnginePillButton: View {
    @Environment(\.theme) private var theme

    enum Role { case primary, secondary }

    let title: String
    var role: Role = .secondary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .basicsButtonLabel(13)
                .foregroundStyle(self.role == .primary ? Color.white : self.theme.palette.primaryText)
                .padding(.horizontal, self.role == .primary ? 14 : 16)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(self.role == .primary ? self.theme.palette.accent : self.theme.palette.cardBackground)
                        .overlay {
                            if self.role == .secondary {
                                Capsule().stroke(BasicsTokens.Surface.borderStrong, lineWidth: 1)
                            }
                        }
                )
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.45)
    }
}

/// 28×28 square icon button — the row-trailing delete affordance.
struct VoiceEngineIconButton: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    var tint: Color?
    var isEnabled: Bool = true
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(BasicsTokens.display(13, .medium))
                .foregroundStyle(self.tint ?? self.theme.palette.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.45)
        .help(self.help)
    }
}

/// The chrome behind a Menu trigger (filter / sort).
struct VoiceEngineMenuTriggerLabel: View {
    @Environment(\.theme) private var theme

    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(self.title)
                .basicsLabel(12)
                .foregroundStyle(self.theme.palette.secondaryText)
            Image(systemName: "chevron.down")
                .font(BasicsTokens.display(9, .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Row indicator

/// 18pt selection indicator. Filled = the model currently doing the listening.
struct VoiceEngineRadio: View {
    @Environment(\.theme) private var theme

    var isFilled: Bool = false
    var isDashed: Bool = false

    var body: some View {
        ZStack {
            if self.isFilled {
                Circle().fill(self.theme.palette.accent)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            } else {
                Circle()
                    .strokeBorder(
                        BasicsTokens.Surface.borderStrong,
                        style: StrokeStyle(lineWidth: 1.5, dash: self.isDashed ? [3, 3] : [])
                    )
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Failure attribution

/// The ASR service reports download/activation failures through a single global
/// alert (`ASRService.showError` + `errorTitle` / `errorMessage`) and keeps no
/// record of WHICH model failed. Board 02b needs a per-row failed state with a
/// Retry, so this log remembers the model the user last acted on and attributes
/// the next raised error to it. Every value it stores comes from the service —
/// nothing here is synthesised. Only ever touched from SwiftUI view code, which
/// already runs on the main thread.
final class VoiceEngineActionLog: ObservableObject {
    enum Action: Equatable {
        case download
        case activate
    }

    struct Failure: Equatable {
        let action: Action
        let title: String
        let message: String
    }

    static let shared = VoiceEngineActionLog()

    @Published private(set) var failures: [String: Failure] = [:]

    private var pending: (modelID: String, action: Action)?

    private init() {}

    /// Call immediately before invoking the real download / activate on the model.
    func begin(_ action: Action, for modelID: String) {
        self.failures.removeValue(forKey: modelID)
        self.pending = (modelID, action)
    }

    /// Called when `ASRService.showError` flips true — attributes the real error
    /// text to the model the user actually acted on.
    func noteErrorRaised(title: String, message: String) {
        guard let pending = self.pending else { return }
        self.failures[pending.modelID] = Failure(action: pending.action, title: title, message: message)
        self.pending = nil
    }

    /// Called when the service reports the work finished without raising.
    func noteSettled() {
        self.pending = nil
    }

    func failure(for modelID: String) -> Failure? {
        self.failures[modelID]
    }

    func clearFailure(for modelID: String) {
        self.failures.removeValue(forKey: modelID)
    }
}
