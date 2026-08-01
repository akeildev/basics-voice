import SwiftUI

/// Board "13b — Analytics privacy".
///
/// A single card sheet: header with Done, then four sections. "We do not
/// collect" is the one green moment on the surface — a brand-tinted block with
/// brand bullets, so the promise reads louder than the disclosure.
struct AnalyticsPrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            self.header

            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    self.weCollectSection
                    self.weDoNotCollectSection
                    self.howItIsUsedSection
                    self.controlSection
                    self.contactRow
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(self.theme.palette.cardBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anonymous analytics")
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("What Basics Voice collects when analytics is on.")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LibraryPagePill(title: "Done", tone: .brand, height: 34, labelSize: 13) {
                self.dismiss()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    // MARK: - Sections

    private var weCollectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("We collect", isBrand: true)
            self.bullet("Basic app and device info — app version, macOS version, CPU family.")
            self.bullet("Which features were used — dictation, Command mode, and so on.")
            self.bullet("Performance numbers — transcription chunk latency and AI post-processing latency, in milliseconds.")
            self.bullet("Model and provider names, plus the character count of post-processing input — never the text itself.")
            self.bullet("Whether something worked, and high-level error info.")
        }
    }

    private var weDoNotCollectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("We do not collect", isBrand: true)
            self.bullet("Any transcription text or audio.", isBrand: true)
            self.bullet("Selected text, rewrite prompts, or AI responses.", isBrand: true)
            self.bullet("Terminal commands or output from Command mode.", isBrand: true)
            self.bullet("Window titles, app names, file paths, clipboard contents, or anything you type.", isBrand: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(BasicsTokens.Semantic.brandSoft)
        )
    }

    private var howItIsUsedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("How it is used", isBrand: false)
            self.bullet("To see which features are actually used, and where reliability or speed needs work.")
            self.bullet("To measure product health — active devices, retention — without requiring accounts.")
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("Control", isBrand: false)
            Text("Turn analytics off any time in Preferences → Share anonymous analytics.")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contactRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(self.theme.palette.tertiaryText)

                Text(self.contactInfoText)
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String, isBrand: Bool) -> some View {
        Text(text)
            .basicsMicroLabel(11)
            .foregroundStyle(isBrand ? self.theme.palette.accent : self.theme.palette.tertiaryText)
    }

    private func bullet(_ text: String, isBrand: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(isBrand
                    ? self.theme.palette.accent
                    : BasicsBorder.strong(self.theme, self.colorScheme))
                .frame(width: 5, height: 5)
                .padding(.top, 8)

            Text(text)
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contactInfoText: AttributedString {
        var text = AttributedString("Concerns? Email alticdev@gmail.com or file an issue on GitHub.")

        if let emailRange = text.range(of: "alticdev@gmail.com") {
            text[emailRange].link = URL(string: "mailto:alticdev@gmail.com")
            text[emailRange].foregroundColor = self.theme.palette.accent
        }

        if let githubRange = text.range(of: "GitHub") {
            text[githubRange].link = URL(string: "https://github.com/altic-dev/FluidVoice")
            text[githubRange].foregroundColor = self.theme.palette.accent
        }

        return text
    }
}

#Preview {
    AnalyticsPrivacyView()
        .frame(width: 640, height: 804)
}
