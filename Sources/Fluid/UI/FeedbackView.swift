//
//  FeedbackView.swift
//  fluid
//
//  Extracted from ContentView.swift to reduce monolithic architecture.
//  Created: 2025-12-14
//  Restyled to board "13 — Feedback" (+ sending / sent / failed).
//

import AppKit
import SwiftUI

/// Board "13 — Feedback".
///
/// One composer card carrying the message, the reply address and the send
/// action; the debug-logs checkbox directly under it; then three hairline link
/// rows. The submit path is unchanged — a real POST to the FluidVoice feedback
/// endpoint, with the two outcome dialogs driven by its result.
struct FeedbackView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State Variables (moved from ContentView)

    @State private var feedbackText: String = ""
    @State private var feedbackEmail: String = ""
    @State private var includeDebugLogs: Bool = false
    @State private var isSendingFeedback: Bool = false
    @State private var showFeedbackConfirmation: Bool = false
    @State private var showFeedbackError: Bool = false
    @State private var feedbackErrorMessage: String = ""
    @FocusState private var isComposerFocused: Bool

    private var canSend: Bool {
        !self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.isSendingFeedback
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                self.pageHead
                self.composer
                self.linkRows
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.contentBackground)
        .overlay {
            if self.showFeedbackConfirmation {
                self.sentDialog
            } else if self.showFeedbackError {
                self.failedDialog
            }
        }
    }

    // MARK: - Page head

    private var pageHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text("Feedback")
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Text("Goes upstream to the FluidVoice maintainers, who this fork is built on. Your transcriptions are never attached — only what you type here.")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 700, alignment: .leading)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if self.feedbackText.isEmpty {
                        Text("Share your thoughts, report a bug, or suggest a feature…")
                            .basicsProse(15)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .padding(.top, 2)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: self.$feedbackText)
                        .basicsProse(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .scrollContentBackground(.hidden)
                        .focused(self.$isComposerFocused)
                        .frame(height: 120)
                }

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(self.theme.palette.separator)
                        .frame(height: 1)

                    HStack(spacing: 12) {
                        TextField("your.email@example.com", text: self.$feedbackEmail)
                            .textFieldStyle(.plain)
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .padding(.horizontal, 12)
                            .frame(width: 260, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)
                                    .fill(self.theme.palette.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BasicsControl.radius, style: .continuous)
                                            .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                                    )
                            )

                        Spacer(minLength: 0)

                        self.sendButton
                    }
                    .padding(.top, 12)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                            .stroke(
                                self.isComposerFocused
                                    ? self.theme.palette.accent.opacity(0.45)
                                    : self.theme.palette.cardBorder,
                                lineWidth: 1
                            )
                    )
            )
            .opacity(self.isSendingFeedback ? 0.55 : 1)
            .allowsHitTesting(!self.isSendingFeedback)

            self.debugLogsCheckbox
        }
    }

    private var sendButton: some View {
        Button {
            Task { await self.sendFeedback() }
        } label: {
            HStack(spacing: 8) {
                if self.isSendingFeedback {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                }
                Text(self.isSendingFeedback ? "Sending…" : "Send feedback")
                    .basicsButtonLabel(14)
            }
            .foregroundStyle(self.isSendingFeedback ? self.theme.palette.tertiaryText : Color.white)
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(
                Capsule().fill(
                    self.isSendingFeedback
                        ? self.theme.palette.sidebarBackground
                        : self.theme.palette.accent
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!self.canSend)
        .opacity(self.canSend || self.isSendingFeedback ? 1 : 0.45)
    }

    /// Wording matches what `includeDebugLogs` actually appends to the payload.
    private var debugLogsCheckbox: some View {
        Button {
            self.includeDebugLogs.toggle()
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(self.includeDebugLogs ? self.theme.palette.accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                self.includeDebugLogs
                                    ? self.theme.palette.accent
                                    : BasicsBorder.strong(self.theme, self.colorScheme),
                                lineWidth: 1.5
                            )
                    )
                    .overlay {
                        if self.includeDebugLogs {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 17, height: 17)

                Text("Attach debug logs — app version, macOS version and the last 30 log lines. No transcription text.")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(self.isSendingFeedback)
    }

    // MARK: - Link rows

    private var linkRows: some View {
        VStack(spacing: 0) {
            self.linkRow(
                icon: "star",
                title: "Star FluidVoice on GitHub",
                subtitle: "altic-dev/FluidVoice — the upstream this fork tracks.",
                url: URL(string: "https://github.com/altic-dev/Fluid-oss")
            )
            self.linkRow(
                icon: "envelope",
                title: "Your fork",
                subtitle: "akeildev/basics-voice — where Send to Instinct and the notch HUD live.",
                url: URL(string: "https://github.com/akeildev/basics-voice")
            )
            self.linkRow(
                icon: "heart",
                title: "Support FluidVoice",
                subtitle: "Sponsor Altic on GitHub — keeps local dictation free to use.",
                url: URL(string: "https://github.com/sponsors/altic-dev"),
                help: "Sponsor Altic on GitHub"
            )
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func linkRow(
        icon: String,
        title: String,
        subtitle: String,
        url: URL?,
        help: String? = nil
    ) -> some View {
        if let url {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)

                Link(destination: url) {
                    HStack(spacing: 16) {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .basicsLabel(15)
                                .foregroundStyle(self.theme.palette.primaryText)
                            Text(subtitle)
                                .basicsProse(14)
                                .foregroundStyle(self.theme.palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .frame(width: 14, height: 14)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help ?? title)
            }
        }
    }

    // MARK: - Outcome dialogs

    private var sentDialog: some View {
        self.dialog(
            icon: "checkmark",
            tint: self.theme.palette.accent,
            title: "Feedback sent",
            message: "Thank you for helping us improve FluidVoice."
        ) {
            LibraryPagePill(title: "OK", tone: .brand, height: 38, labelSize: 14, expands: true) {
                self.showFeedbackConfirmation = false
            }
        }
    }

    private var failedDialog: some View {
        self.dialog(
            icon: "exclamationmark",
            tint: BasicsTokens.Semantic.danger,
            title: "Feedback failed",
            message: self.feedbackErrorMessage
        ) {
            HStack(spacing: 10) {
                LibraryPagePill(title: "Cancel", tone: .outline, height: 38, labelSize: 14, width: 183) {
                    self.showFeedbackError = false
                }

                LibraryPagePill(title: "Try Again", tone: .brand, height: 38, labelSize: 14, width: 183) {
                    self.showFeedbackError = false
                    Task { await self.sendFeedback() }
                }
            }
        }
    }

    private func dialog(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint)
                    )

                Text(title)
                    .basicsLabel(20)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(message)
                    .basicsProse(15)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 352)

                actions()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 26)
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.xl, style: .continuous)
                            .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                    )
            )
            .shadow(color: BasicsTokens.Ink.foreground.opacity(0.30), radius: 40, x: 0, y: 32)
        }
    }

    // MARK: - Feedback Functions

    private func sendFeedback() async {
        guard !self.feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        await MainActor.run {
            self.isSendingFeedback = true
        }

        let feedbackData = self.createFeedbackData()
        let success = await submitFeedback(data: feedbackData)

        await MainActor.run {
            self.isSendingFeedback = false
            if success {
                // Show confirmation and clear form
                self.showFeedbackConfirmation = true
                self.feedbackText = ""
                self.feedbackEmail = ""
                self.includeDebugLogs = false
            } else {
                // Show error to user - inputs are preserved for retry
                self.feedbackErrorMessage = "We couldn't send your feedback. Please check your internet connection and try again. What you typed is still here."
                self.showFeedbackError = true
            }
        }
    }

    private func createFeedbackData() -> [String: Any] {
        var feedbackContent = self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)

        if self.includeDebugLogs {
            feedbackContent += "\n\n--- Debug Information ---\n"
            feedbackContent += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\n"
            feedbackContent += "Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")\n"
            feedbackContent += "macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            feedbackContent += "Date: \(Date().formatted())\n\n"

            // Add recent log entries
            let logFileURL = FileLogger.shared.currentLogFileURL()
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                do {
                    let logContent = try String(contentsOf: logFileURL)
                    let lines = logContent.components(separatedBy: .newlines)
                    let recentLines = Array(lines.suffix(30)) // Last 30 lines
                    feedbackContent += "Recent Log Entries:\n"
                    feedbackContent += recentLines.joined(separator: "\n")
                } catch {
                    feedbackContent += "Could not read log file: \(error.localizedDescription)\n"
                }
            }
        }

        return [
            "email_id": self.feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            "feedback": feedbackContent,
        ]
    }

    private func submitFeedback(data: [String: Any]) async -> Bool {
        guard let url = URL(string: "https://altic.dev/api/fluid/feedback") else {
            DebugLogger.shared.error("Invalid feedback API URL", source: "FeedbackView")
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: data)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let success = (200 ... 299).contains(httpResponse.statusCode)
                if success {
                    DebugLogger.shared.info("Feedback submitted successfully", source: "FeedbackView")
                } else {
                    DebugLogger.shared.error(
                        "Feedback submission failed with status: \(httpResponse.statusCode)",
                        source: "FeedbackView"
                    )
                }
                return success
            }
            return false
        } catch {
            DebugLogger.shared.error(
                "Network error submitting feedback: \(error.localizedDescription)",
                source: "FeedbackView"
            )
            return false
        }
    }
}

#Preview {
    FeedbackView()
        .frame(width: 1096, height: 900)
}
