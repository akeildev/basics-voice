import AppKit
import SwiftUI

/// A lightweight macOS-native text view that reliably renders bound text immediately,
/// avoiding occasional `TextEditor` refresh glitches in sheets.
///
/// Board 04c · editor sheet: a prompt is prose, so the body reads in Karma 15.
/// The parts that are not prose — the `{placeholders}` and `<context>` tags the
/// app substitutes at run time — switch to JetBrains Mono so they read as
/// machinery rather than as a sentence. The caret is brand.
struct PromptTextView: NSViewRepresentable {
    @Binding var text: String

    var isEditable: Bool = true
    var font: NSFont = PromptTextView.proseFont
    var contentInset: CGFloat = 12

    /// Karma 15 — the prose face, at the size the board sets prompt bodies in.
    static var proseFont: NSFont {
        NSFont(name: BasicsTokens.FontName.proseRegular, size: 15)
            ?? NSFont.systemFont(ofSize: 15)
    }

    /// JetBrains Mono for the substituted tokens, one step down so the mono
    /// x-height matches Karma's rather than towering over it.
    static func variableFont(matching prose: NSFont) -> NSFont {
        NSFont(name: BasicsTokens.FontName.monoRegular, size: prose.pointSize - 2)
            ?? NSFont.monospacedSystemFont(ofSize: prose.pointSize - 2, weight: .regular)
    }

    /// `{placeholder}`, `{{placeholder}}` and `<context>`-style tags.
    private static let variablePattern = try? NSRegularExpression(
        pattern: "\\{\\{[^{}]*\\}\\}|\\{[^{}\\n]*\\}|</?[A-Za-z][A-Za-z0-9_.-]*>",
        options: []
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text, owner: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.isEditable = self.isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = self.font
        textView.textColor = NSColor(BasicsTokens.Ink.foreground)
        textView.insertionPointColor = NSColor(BasicsTokens.Semantic.brand)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(BasicsTokens.Semantic.brand.opacity(0.16)),
            .foregroundColor: NSColor(BasicsTokens.Ink.foreground),
        ]
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: self.contentInset, height: self.contentInset)
        textView.textContainer?.lineFragmentPadding = 0

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        textView.string = self.text
        Self.applyHighlighting(to: textView, baseFont: self.font)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.owner = self

        // Keep AppKit view in sync with SwiftUI state.
        // This is the critical bit that avoids "blank until focus changes" behavior.
        if textView.string != self.text {
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
            Self.applyHighlighting(to: textView, baseFont: self.font)
        }

        if textView.isEditable != self.isEditable { textView.isEditable = self.isEditable }
        textView.isSelectable = true
        textView.drawsBackground = false
        if textView.font != self.font {
            textView.font = self.font
            Self.applyHighlighting(to: textView, baseFont: self.font)
        }
        if textView.textContainerInset != NSSize(width: self.contentInset, height: self.contentInset) {
            textView.textContainerInset = NSSize(width: self.contentInset, height: self.contentInset)
        }
        if textView.textContainer?.lineFragmentPadding != 0 {
            textView.textContainer?.lineFragmentPadding = 0
        }
    }

    /// Repaints the whole string: prose everywhere, mono on every substituted
    /// token. Cheap enough for prompt-length text and always self-consistent, so
    /// an edit can never leave a half-highlighted run behind.
    static func applyHighlighting(to textView: NSTextView, baseFont: NSFont) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let ink = NSColor(BasicsTokens.Ink.foreground)
        let variableInk = NSColor(BasicsTokens.Semantic.brand)

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: ink], range: full)

        if let pattern = self.variablePattern {
            let variable = self.variableFont(matching: baseFont)
            pattern.enumerateMatches(in: storage.string, options: [], range: full) { match, _, _ in
                guard let range = match?.range else { return }
                storage.addAttributes([.font: variable, .foregroundColor: variableInk], range: range)
            }
        }
        storage.endEditing()

        textView.typingAttributes = [.font: baseFont, .foregroundColor: ink]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        var owner: PromptTextView

        init(text: Binding<String>, owner: PromptTextView) {
            self.text = text
            self.owner = owner
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if self.text.wrappedValue != textView.string {
                self.text.wrappedValue = textView.string
            }
            let selectedRanges = textView.selectedRanges
            PromptTextView.applyHighlighting(to: textView, baseFont: self.owner.font)
            textView.selectedRanges = selectedRanges
        }
    }
}
