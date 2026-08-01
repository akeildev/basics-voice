import SwiftUI

/// Board `16 — Onboarding · 5 Try it out` (+ `· listening`, `· transcript
/// captured`, `· change shortcut`).
///
/// The keycap hero, the example prompt, and the editor the real transcript
/// lands in. Everything here is bound to the live dictation state — the keycap
/// glows because `asr.isRunning` is true, not on a timer.
struct OnboardingTryoutStepView: View {
    @Binding var finalText: String

    let language: VoiceEngineLanguage
    let shortcutDisplay: String
    let isReady: Bool
    let isRunning: Bool
    let isRecordingShortcut: Bool
    let shortcutRecordingMessage: String?
    let footerHint: String?
    let onToggleShortcut: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isEditorFocused: Bool
    @State private var isShortcutKeyPressed = false
    @State private var isShortcutGlowActive = false
    @State private var shortcutAnimationRevision = 0

    init(
        finalText: Binding<String>,
        language: VoiceEngineLanguage,
        shortcutDisplay: String,
        isReady: Bool,
        isRunning: Bool,
        isRecordingShortcut: Bool,
        shortcutRecordingMessage: String?,
        footerHint: String? = nil,
        onToggleShortcut: @escaping () -> Void
    ) {
        self._finalText = finalText
        self.language = language
        self.shortcutDisplay = shortcutDisplay
        self.isReady = isReady
        self.isRunning = isRunning
        self.isRecordingShortcut = isRecordingShortcut
        self.shortcutRecordingMessage = shortcutRecordingMessage
        self.footerHint = footerHint
        self.onToggleShortcut = onToggleShortcut
    }

    private static let cardWidth: CGFloat = 700
    private static let cardPadding: CGFloat = 24
    private static var innerWidth: CGFloat { Self.cardWidth - (Self.cardPadding * 2) }

    private static let languageExamples: [String: [String]] = [
        "ar": [
            "ذكرني أن أرسل الملاحظات قبل الخامسة.",
            "اكتب رسالة قصيرة عن اجتماع اليوم.",
        ],
        "de": [
            "Erinnere mich daran, die Notizen vor fünf zu senden.",
            "Schreib eine kurze Nachricht über das heutige Treffen.",
        ],
        "en": [
            "Remind me to send the notes before five.",
            "Write a short update about today's meeting.",
        ],
        "es": [
            "Recuérdame enviar las notas antes de las cinco.",
            "Escribe una breve actualización sobre la reunión de hoy.",
        ],
        "fr": [
            "Rappelle-moi d'envoyer les notes avant cinq heures.",
            "Écris un court message sur la réunion d'aujourd'hui.",
        ],
        "hi": [
            "मुझे पाँच बजे से पहले नोट्स भेजने की याद दिलाना।",
            "आज की मीटिंग के बारे में एक छोटा अपडेट लिखो।",
        ],
        "it": [
            "Ricordami di inviare gli appunti prima delle cinque.",
            "Scrivi un breve aggiornamento sulla riunione di oggi.",
        ],
        "ja": [
            "5時前にメモを送るようにリマインドして。",
            "今日の会議について短い更新を書いて。",
        ],
        "ko": [
            "다섯 시 전에 메모를 보내라고 알려줘.",
            "오늘 회의에 대한 짧은 업데이트를 써줘.",
        ],
        "nl": [
            "Herinner me eraan om de notities voor vijf uur te sturen.",
            "Schrijf een korte update over de vergadering van vandaag.",
        ],
        "pl": [
            "Przypomnij mi, żeby wysłać notatki przed piątą.",
            "Napisz krótką aktualizację o dzisiejszym spotkaniu.",
        ],
        "pt": [
            "Lembre-me de enviar as notas antes das cinco.",
            "Escreva uma breve atualização sobre a reunião de hoje.",
        ],
        "ru": [
            "Напомни мне отправить заметки до пяти.",
            "Напиши короткое обновление о сегодняшней встрече.",
        ],
        "ta": [
            "ஐந்து மணிக்கு முன் குறிப்புகளை அனுப்ப நினைவூட்டு.",
            "இன்றைய கூட்டத்தைப் பற்றி ஒரு குறுகிய புதுப்பிப்பு எழுது.",
        ],
        "uk": [
            "Нагадай мені надіслати нотатки до п'ятої.",
            "Напиши коротке оновлення про сьогоднішню зустріч.",
        ],
        "vi": [
            "Nhắc tôi gửi ghi chú trước năm giờ.",
            "Viết một cập nhật ngắn về cuộc họp hôm nay.",
        ],
        "zh": [
            "提醒我五点前发送笔记。",
            "写一段关于今天会议的简短更新。",
        ],
    ]

    private var exampleTexts: [String] {
        Self.languageExamples[self.language.id] ?? []
    }

    private var promptText: String {
        if self.exampleTexts.isEmpty {
            return "Say anything you'd want to dictate in \(self.language.displayName)."
        }
        return "Try this, or say anything you'd want to dictate."
    }

    private var exampleText: String {
        self.exampleTexts.first ?? "Say anything in \(self.language.displayName)."
    }

    private var appDisplayName: String {
        Bundle.main.fluidAppDisplayName
    }

    private var hasText: Bool {
        !self.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowPlaceholder: Bool {
        !self.hasText && !self.isEditorFocused
    }

    private var placeholderText: String {
        if self.isRunning {
            return "Listening..."
        }
        if self.isReady {
            return "Click here to test \(self.appDisplayName)"
        }
        return "Your dictation will appear here..."
    }

    private var keycapText: String {
        self.isRecordingShortcut ? "•••" : self.shortcutDisplay
    }

    private var trimmedRecordingMessage: String? {
        guard self.isRecordingShortcut,
              let message = self.shortcutRecordingMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return nil
        }
        return message
    }

    var body: some View {
        self.keyboardCard
            .frame(width: Self.cardWidth)
            .onAppear {
                self.isShortcutGlowActive = self.isRunning
            }
            .onChange(of: self.isRunning) { _, newValue in
                self.animateShortcutKeyToggle(to: newValue)
            }
    }

    private var keyboardCard: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous)
        let isListening = self.isShortcutGlowActive

        return VStack(spacing: 0) {
            self.shortcutVisual
                .padding(.top, 14)

            self.hintRow
                .padding(.top, 14)

            Text(self.promptText)
                .basicsLabel(13)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, 22)

            OnboardingChip(
                text: self.exampleTexts.isEmpty ? self.exampleText : "\u{201C}\(self.exampleText)\u{201D}",
                height: 34,
                horizontalPadding: 16,
                usesProse: true,
                size: 15
            )
            .padding(.top, 10)

            self.editorPanel
                .padding(.top, 10)

            Text(self.footerHint ?? "Feels slow or inaccurate? Go back and try another model for \(self.language.displayName).")
                .basicsProse(13)
                .foregroundStyle(BasicsTokens.Ink.faint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 16)
        }
        .frame(width: Self.innerWidth)
        .padding(Self.cardPadding)
        .background(shape.fill(BasicsTokens.Surface.card))
        .overlay(
            shape.stroke(
                isListening ? BasicsTokens.Semantic.brand.opacity(0.45) : BasicsTokens.Surface.border,
                lineWidth: isListening ? 1.5 : 1
            )
        )
        .basicsShadows([
            BasicsShadow(color: BasicsTokens.Ink.foreground.opacity(0.06), radius: 16, y: 10),
        ])
        .overlay(alignment: .topTrailing) {
            self.changeShortcutButton
                .padding(.top, 20)
                .padding(.trailing, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation shortcut \(self.shortcutDisplay). Press once to start. Press again to stop.")
    }

    // MARK: - Change / cancel

    private var changeShortcutButton: some View {
        OnboardingActionButton(
            title: self.isRecordingShortcut ? "Cancel" : "Change",
            tone: self.isRecordingShortcut ? .soft : .secondary,
            height: 32,
            horizontalPadding: 12,
            labelSize: 13,
            width: 72,
            action: self.onToggleShortcut
        )
        .disabled(self.isRunning)
    }

    // MARK: - Keycaps

    private var shortcutVisual: some View {
        HStack(alignment: .bottom, spacing: 12) {
            self.sideKeyBox("ctrl")
            self.shortcutKeycap(self.keycapText)
            self.sideKeyBox("opt")
        }
    }

    private func sideKeyBox(_ label: String) -> some View {
        Text(label)
            .basicsMono(13)
            .foregroundStyle(BasicsTokens.Ink.faint)
            .frame(width: 74, height: 58)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(BasicsTokens.Surface.muted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .stroke(BasicsTokens.Surface.border, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private func shortcutKeycap(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
        let isPressed = self.isShortcutKeyPressed
        let isListening = self.isShortcutGlowActive

        return Text(text)
            .basicsMono(20, weight: .medium)
            .foregroundStyle(BasicsTokens.Semantic.brand)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 12)
            .frame(width: 112, height: 74)
            .background(
                shape.fill(isListening ? BasicsTokens.Semantic.brandSoft : BasicsTokens.Surface.card)
            )
            .overlay(shape.stroke(BasicsTokens.Semantic.brand, lineWidth: 2))
            .shadow(
                color: BasicsTokens.Semantic.brand.opacity(isListening ? 0.30 : 0.18),
                radius: isListening ? 14 : 12,
                x: 0,
                y: isPressed ? 4 : 10
            )
            .scaleEffect(isPressed ? 0.965 : 1)
            .offset(y: isPressed ? 4 : 0)
            .accessibilityLabel("Current shortcut \(self.shortcutDisplay)")
    }

    // MARK: - Hint

    @ViewBuilder
    private var hintRow: some View {
        if let message = self.trimmedRecordingMessage {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BasicsTokens.Semantic.warning)

                Text(message)
                    .basicsProse(15)
                    .foregroundStyle(BasicsTokens.Ink.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        } else {
            Text("Press once to start. Press again to stop.")
                .basicsProse(15)
                .foregroundStyle(BasicsTokens.Ink.muted)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    // MARK: - Editor

    private var editorPanel: some View {
        let shape = RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
        let isListening = self.isRunning

        return ZStack(alignment: .topLeading) {
            TextEditor(text: self.$finalText)
                .basicsProse(16)
                .foregroundStyle(BasicsTokens.Ink.foreground)
                .scrollContentBackground(.hidden)
                .focused(self.$isEditorFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(height: 108)

            if self.shouldShowPlaceholder {
                Text(self.placeholderText)
                    .basicsProse(16)
                    .foregroundStyle(
                        isListening ? BasicsTokens.Semantic.brand : BasicsTokens.Ink.faint
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.innerWidth, height: 108)
        .background(
            shape.fill(isListening ? BasicsTokens.Semantic.brandSoft : BasicsTokens.Surface.bg)
        )
        .overlay(
            shape.stroke(
                isListening ? BasicsTokens.Semantic.brand : BasicsTokens.Surface.border,
                lineWidth: isListening ? 1.5 : 1
            )
        )
    }

    // MARK: - Motion

    private func animateShortcutKeyToggle(to isListening: Bool) {
        self.shortcutAnimationRevision += 1
        let revision = self.shortcutAnimationRevision

        if self.reduceMotion {
            self.isShortcutKeyPressed = false
            self.isShortcutGlowActive = isListening
            return
        }

        withAnimation(.easeOut(duration: 0.055)) {
            self.isShortcutKeyPressed = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            guard self.shortcutAnimationRevision == revision else {
                return
            }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72, blendDuration: 0.02)) {
                self.isShortcutKeyPressed = false
                self.isShortcutGlowActive = isListening
            }
        }
    }
}
