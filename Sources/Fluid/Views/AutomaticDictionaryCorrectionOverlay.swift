import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class DictionaryCorrectionOverlayController {
    static let shared = DictionaryCorrectionOverlayController()

    private static let displayDurationNanoseconds: UInt64 = 5_000_000_000
    private static let successDurationNanoseconds: UInt64 = 1_400_000_000
    private static let presentationDuration: TimeInterval = 0.05
    private static let dismissalDuration: TimeInterval = 0.05

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AutomaticDictionaryCorrectionOverlayView>?
    private var session: AutomaticDictionaryTrainingSession?
    private var sessionCancellable: AnyCancellable?
    private var dismissTask: Task<Void, Never>?
    private var outcomeHandler: ((AutomaticDictionarySuggestionOutcome) -> Void)?
    private var generation: UInt64 = 0

    private init() {}

    var isPresented: Bool {
        self.panel?.isVisible == true
    }

    func show(
        candidate: AutomaticDictionaryCorrectionCandidate,
        onOutcome: @escaping (AutomaticDictionarySuggestionOutcome) -> Void
    ) {
        self.generation &+= 1
        let currentGeneration = self.generation
        self.dismissTask?.cancel()
        self.session?.cancel()
        self.outcomeHandler = onOutcome

        let session = AutomaticDictionaryTrainingSession(
            candidate: candidate,
            asr: AppServices.shared.asr
        )
        session.onInteraction = { [weak self] in
            self?.keepVisible()
        }
        session.onSuccess = { [weak self] in
            self?.reportOutcome(.accepted)
            self?.scheduleSuccessDismissal()
        }
        self.session = session

        let rootView = AutomaticDictionaryCorrectionOverlayView(
            session: session,
            displayDuration: Double(Self.displayDurationNanoseconds) / 1_000_000_000,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        if let hostingView = self.hostingView {
            hostingView.rootView = rootView
        } else {
            self.createPanel(rootView: rootView)
        }

        self.sessionCancellable = session.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resizeAndPositionPanel(animated: true)
                }
            }

        guard let panel = self.panel else { return }
        self.resizeAndPositionPanel(animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.presentationDuration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        self.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.displayDurationNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.generation == currentGeneration,
                  self.session?.screen == .choice
            else {
                return
            }
            self.reportOutcome(.timedOut)
            self.hide()
        }
    }

    func hide() {
        self.generation &+= 1
        let hideGeneration = self.generation
        self.dismissTask?.cancel()
        self.dismissTask = nil
        self.session?.cancel()
        guard let panel, panel.isVisible else {
            self.clearSession()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dismissalDuration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == hideGeneration else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
                self.clearSession()
            }
        }
    }

    func dismiss() {
        self.reportOutcome(.dismissed)
        self.hide()
    }

    private func keepVisible() {
        self.dismissTask?.cancel()
        self.dismissTask = nil
    }

    private func scheduleSuccessDismissal() {
        self.keepVisible()
        let successGeneration = self.generation
        self.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.successDurationNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.generation == successGeneration
            else {
                return
            }
            self.hide()
        }
    }

    private func clearSession() {
        self.sessionCancellable?.cancel()
        self.sessionCancellable = nil
        self.session = nil
        self.outcomeHandler = nil
    }

    private func reportOutcome(_ outcome: AutomaticDictionarySuggestionOutcome) {
        guard let outcomeHandler = self.outcomeHandler else { return }
        self.outcomeHandler = nil
        outcomeHandler(outcome)
    }

    private func createPanel(rootView: AutomaticDictionaryCorrectionOverlayView) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // SwiftUI draws the shadow now (the view reserves a 10pt ring for it), so
        // AppKit must not add a second, square one behind the rounded panel.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func resizeAndPositionPanel(animated: Bool) {
        guard let panel, let hostingView,
              let screen = OverlayScreenResolver.screenForCurrentPointer() ?? NSScreen.main
        else {
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let size = NSSize(width: ceil(fittingSize.width), height: ceil(fittingSize.height))
        guard size.width > 0, size.height > 0 else { return }
        hostingView.frame = NSRect(origin: .zero, size: size)

        let visibleFrame = screen.visibleFrame
        let requestedY = visibleFrame.minY + CGFloat(SettingsStore.shared.overlayBottomOffset)
        let y = max(visibleFrame.minY + 10, min(requestedY, visibleFrame.maxY - size.height - 40))
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: y,
            width: size.width,
            height: size.height
        )

        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

// MARK: - Correction overlay (board 18)

private struct AutomaticDictionaryCorrectionOverlayView: View {
    @ObservedObject var session: AutomaticDictionaryTrainingSession
    @ObservedObject private var settings = SettingsStore.shared

    let displayDuration: TimeInterval
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDismissHovered = false
    @State private var isBackHovered = false
    @State private var progress: CGFloat = 1

    /// The user's accent, stepped up for this dark ground. `green500` is the
    /// value on every light page but drops under 3:1 on `#0B0E0C`, so the Basics
    /// default resolves to `g400`; a deliberately-picked custom accent is left
    /// exactly as the user set it in Preferences.
    private var accent: Color {
        self.settings.accentColorOption == .basics
            ? BasicsTokens.Dark.accent
            : self.settings.accentColor
    }

    /// Accent-coloured TEXT, which needs one more step of lift than a fill.
    private var accentInk: Color {
        self.settings.accentColorOption == .basics
            ? BasicsTokens.Dark.accentInk
            : self.settings.accentColor
    }

    var body: some View {
        Group {
            switch self.session.screen {
            case .choice:
                self.choiceContent
            case .training:
                self.trainingContent
            case .success:
                self.successContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(width: 460)
        .background(self.overlayBackground)
        .overlay(alignment: .bottomLeading) {
            if self.session.screen == .choice {
                GeometryReader { proxy in
                    Capsule()
                        .fill(BasicsTokens.Dark.ink.opacity(0.7))
                        .frame(width: proxy.size.width * self.progress, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        .padding(10) // shadow room inside the borderless panel
        .preferredColorScheme(.dark)
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.16), value: self.session.screen)
        .onAppear {
            self.startProgressAnimation()
        }
    }

    // MARK: Choice

    private var choiceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header(title: "Correction noticed", allowsBack: false)

            self.correctionPair(size: 20)

            Text("Save just this correction, or teach Basics Voice how you say it.")
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Dark.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                CorrectionOverlayActionButton(
                    title: "Train by voice",
                    systemImage: "mic.fill",
                    style: .secondary,
                    accent: self.accent,
                    action: self.session.beginTraining
                )

                CorrectionOverlayActionButton(
                    title: "Add this correction",
                    systemImage: "plus",
                    style: .accent,
                    accent: self.accent,
                    action: self.session.addOnlyCorrection
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: Training

    private var trainingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header(title: "Train by voice", allowsBack: true)

            self.correctionPair(size: 17)

            self.trainingPanel

            self.finalOutputRow

            if !self.session.variants.isEmpty {
                self.capturedVariantsRow
            }

            if self.session.capturePhase == .idle, self.session.hasError, !self.session.statusMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BasicsTokens.Dark.danger)
                    Text(self.session.statusMessage)
                        .basicsProse(13)
                        .foregroundStyle(BasicsTokens.Dark.danger)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                CorrectionOverlayRecordButton(
                    title: self.session.recordButtonTitle,
                    isStop: self.session.recordButtonIsStop,
                    isChecking: self.session.capturePhase == .processing,
                    isEnabled: self.session.canUseRecordButton,
                    action: self.session.toggleCapture
                )

                CorrectionOverlayActionButton(
                    title: "Add replacement",
                    systemImage: self.session.isReady ? "sparkles" : "plus",
                    style: .accent,
                    accent: self.accent,
                    isEnabled: self.session.canSave,
                    isReady: self.session.isReady,
                    action: self.session.addTrainedReplacement
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var trainingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Teach Basics Voice how you say it")
                .basicsLabel(13)
                .foregroundStyle(BasicsTokens.Dark.ink)

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    if self.session.isReady {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(self.accent)
                            Text("Basics Voice got it right \(CustomDictionaryTrainingMerge.readyCoveredCount) times in a row.")
                                .basicsProse(13)
                                .foregroundStyle(self.accentInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        self.trainingInstruction(number: 1, text: "Press Start once.")
                        self.trainingInstruction(
                            number: 2,
                            text: "Say the word, then pause. It captures and listens again."
                        )
                        self.trainingInstruction(
                            number: 3,
                            text: "Repeat naturally until the circle reaches \(CustomDictionaryTrainingMerge.readyCoveredCount) of \(CustomDictionaryTrainingMerge.readyCoveredCount)."
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CorrectionOverlayReadinessRing(
                    progress: self.session.readinessProgress,
                    total: CustomDictionaryTrainingMerge.readyCoveredCount,
                    isReady: self.session.isReady,
                    accent: self.accent,
                    accentInk: self.accentInk
                )
            }

            Text(self.overlayReadinessCaption)
                .basicsProse(12.5)
                .foregroundStyle(self.session.isReady ? self.accentInk : BasicsTokens.Dark.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelSurface)
    }

    private var overlayReadinessCaption: String {
        if self.session.isReady {
            return "Ready. Add replacement is unlocked."
        }
        let remaining = max(
            0,
            CustomDictionaryTrainingMerge.readyCoveredCount - self.session.readinessProgress
        )
        return "\(remaining) correct \(remaining == 1 ? "try" : "tries") to unlock Add replacement."
    }

    private func trainingInstruction(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .basicsMono(12)
                .foregroundStyle(self.accent)
                .frame(width: 14, alignment: .leading)

            Text(text)
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Success

    private var successContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(self.accent.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(self.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(self.session.successTitle)
                    .basicsLabel(15)
                    .foregroundStyle(BasicsTokens.Dark.ink)
                Text("“\(self.session.candidate.heardText)” will become “\(self.session.candidate.correctedText)”.")
                    .basicsProse(13)
                    .foregroundStyle(BasicsTokens.Dark.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    // MARK: Shared rows

    private func header(title: String, allowsBack: Bool) -> some View {
        HStack(spacing: 12) {
            if allowsBack {
                Button(action: self.session.returnToChoice) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(
                                self.isBackHovered
                                    ? BasicsTokens.Dark.iconButton
                                    : BasicsTokens.Dark.chipFill
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(self.session.capturePhase != .idle)
                .opacity(self.session.capturePhase == .idle ? 1 : 0.35)
                .onHover { self.isBackHovered = $0 }
                .help("Back")
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(self.accent.opacity(0.16)))
            }

            Text(title)
                .basicsLabel(13)
                .foregroundStyle(BasicsTokens.Dark.inkSubtle)

            Spacer(minLength: 8)

            Button(action: self.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(
                            self.isDismissHovered
                                ? BasicsTokens.Dark.iconButton
                                : BasicsTokens.Dark.chipFill
                        )
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { self.isDismissHovered = $0 }
            .help("Dismiss")
        }
    }

    private func correctionPair(size: CGFloat) -> some View {
        HStack(spacing: 14) {
            Text(self.session.candidate.heardText)
                .basicsLabel(size)
                .foregroundStyle(BasicsTokens.Dark.muted)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.accent)

            Text(self.session.candidate.correctedText)
                .basicsLabel(size)
                .foregroundStyle(BasicsTokens.Dark.ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An uppercase micro-label in a fixed lane so "Final output" and "Captured"
    /// share one left edge.
    private func rowCaption(_ text: String) -> some View {
        Text(text)
            .basicsMicroLabel(11)
            .foregroundStyle(BasicsTokens.Dark.faint)
            .frame(width: 96, alignment: .leading)
    }

    private var finalOutputRow: some View {
        HStack(spacing: 14) {
            self.rowCaption("Final output")

            Text(self.session.finalOutputText)
                .basicsLabel(13)
                .foregroundStyle(
                    self.session.lastOutput.isEmpty
                        ? BasicsTokens.Dark.muted
                        : BasicsTokens.Dark.ink
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if self.session.isReady {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Ready")
                        .basicsLabel(12)
                }
                .foregroundStyle(self.accentInk)
            }
        }
    }

    private var capturedVariantsRow: some View {
        HStack(spacing: 14) {
            self.rowCaption("Captured")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(self.session.variants, id: \.self) { variant in
                        CorrectionOverlayVariantChip(variant: variant) {
                            self.session.removeVariant(variant)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 24)
    }

    private func startProgressAnimation() {
        self.progress = 1
        guard !self.reduceMotion else { return }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: self.displayDuration)) {
                self.progress = 0
            }
        }
    }

    // MARK: Chrome

    private var panelSurface: some View {
        RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .strokeBorder(BasicsTokens.Dark.hairline, lineWidth: 1)
            )
    }

    private var overlayBackground: some View {
        RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous)
            .fill(BasicsTokens.Dark.panel)
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.26),
                                Color.white.opacity(0.07),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 20)
    }
}

// MARK: - Readiness ring

private struct CorrectionOverlayReadinessRing: View {
    let progress: Int
    let total: Int
    let isReady: Bool
    let accent: Color
    let accentInk: Color

    private var fraction: Double {
        guard self.total > 0 else { return 0 }
        return min(max(Double(self.progress) / Double(self.total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 5)

            Circle()
                .trim(from: 0, to: self.fraction)
                .stroke(
                    self.accent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(self.progress)/\(self.total)")
                    .basicsLabel(18)
                    .foregroundStyle(self.isReady ? self.accentInk : BasicsTokens.Dark.ink)
                    .monospacedDigit()

                Text(self.isReady ? "Ready" : "Correct")
                    .basicsMicroLabel(10)
                    .foregroundStyle(self.isReady ? self.accent : BasicsTokens.Dark.faint)
            }
        }
        .frame(width: 76, height: 76)
        .shadow(color: self.isReady ? self.accent.opacity(0.22) : .clear, radius: 9)
        .animation(.easeOut(duration: 0.24), value: self.progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training progress")
        .accessibilityValue("\(self.progress) of \(self.total) correct")
    }
}

// MARK: - Buttons

private struct CorrectionOverlayActionButton: View {
    enum Style {
        case accent
        case secondary
    }

    let title: String
    let systemImage: String
    let style: Style
    let accent: Color
    var isEnabled = true
    var isReady = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isGlowExpanded = false

    private var shouldPulse: Bool {
        self.isReady && self.isEnabled && !self.isHovered && !self.reduceMotion
    }

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(self.title)
                    .basicsButtonLabel(13)
            }
            .foregroundStyle(self.labelColor)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(self.background)
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .onHover { self.isHovered = $0 }
        .onAppear { self.updateGlow() }
        .onChange(of: self.shouldPulse) { _, _ in
            self.updateGlow()
        }
    }

    private var labelColor: Color {
        guard self.isEnabled else { return BasicsTokens.Dark.muted }
        switch self.style {
        case .accent: return BasicsTokens.Dark.panel
        case .secondary: return BasicsTokens.Dark.ink
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
            .fill(self.fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .strokeBorder(self.borderColor, lineWidth: self.isReady ? 1.5 : 1)
            )
            .shadow(
                color: self.isReady ? self.accent.opacity(self.isGlowExpanded ? 0.45 : 0.18) : .clear,
                radius: self.isReady ? (self.isGlowExpanded ? 22 : 9) : 0,
                y: 3
            )
    }

    private var fillColor: Color {
        guard self.isEnabled else {
            return Color.white.opacity(0.04)
        }
        switch self.style {
        case .accent:
            return self.isHovered ? self.accent : self.accent.opacity(0.92)
        case .secondary:
            return self.isHovered ? BasicsTokens.Dark.chipFillHover : BasicsTokens.Dark.chipFill
        }
    }

    private var borderColor: Color {
        guard self.isEnabled else {
            return BasicsTokens.Dark.hairline
        }
        if self.isReady {
            return self.accent.opacity(0.78)
        }
        switch self.style {
        case .accent:
            return Color.white.opacity(0.18)
        case .secondary:
            return self.isHovered ? BasicsTokens.Dark.chipBorderHover : BasicsTokens.Dark.border
        }
    }

    private func updateGlow() {
        guard self.shouldPulse else {
            withAnimation(.easeOut(duration: 0.16)) {
                self.isGlowExpanded = false
            }
            return
        }

        self.isGlowExpanded = false
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            self.isGlowExpanded = true
        }
    }
}

private struct CorrectionOverlayRecordButton: View {
    let title: String
    let isStop: Bool
    let isChecking: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                if self.isChecking {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: self.isStop ? "stop.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(self.title)
                    .basicsButtonLabel(13)
            }
            .foregroundStyle(self.labelColor)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(self.fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                            .strokeBorder(self.borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .onHover { self.isHovered = $0 }
    }

    private var labelColor: Color {
        self.isEnabled ? BasicsTokens.Dark.ink : BasicsTokens.Dark.muted
    }

    private var fillColor: Color {
        guard self.isEnabled else { return Color.white.opacity(0.04) }
        if self.isStop {
            return BasicsTokens.Dark.danger.opacity(self.isHovered ? 1 : 0.9)
        }
        return self.isHovered ? BasicsTokens.Dark.chipFillHover : Color.white.opacity(0.10)
    }

    private var borderColor: Color {
        guard self.isEnabled else { return BasicsTokens.Dark.hairline }
        return self.isStop ? Color.white.opacity(0.18) : BasicsTokens.Dark.border
    }
}

// MARK: - Captured chip

private struct CorrectionOverlayVariantChip: View {
    let variant: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.onRemove) {
            HStack(spacing: 6) {
                Text(self.variant)
                    .basicsLabel(12)
                    .foregroundStyle(BasicsTokens.Dark.inkSubtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        self.isHovered ? BasicsTokens.Dark.ink : BasicsTokens.Dark.faint
                    )
            }
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(
                Capsule()
                    .fill(self.isHovered ? BasicsTokens.Dark.chipFillHover : BasicsTokens.Dark.chipFill)
                    .overlay(
                        Capsule().strokeBorder(BasicsTokens.Dark.chipBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 120)
        .onHover { self.isHovered = $0 }
        .help("Remove \(self.variant)")
    }
}
