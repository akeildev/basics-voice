import SwiftUI

/// Board "12 — Changelog" (+ loading / refresh-failed / unavailable).
///
/// Two columns per release: version, date, badges and the GitHub link on the
/// left; the parsed note blocks on the right; a hairline between releases. The
/// fetch, cache and note-parsing logic is unchanged — this is real GitHub data
/// from `SimpleUpdater.fetchRecentReleaseNotes`.
struct ChangelogView: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var releases: [SimpleUpdater.ReleaseNote] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private let owner = "altic-dev"
    private let repo = "Fluid-oss"
    private let releaseLimit = 3

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                self.header

                if !self.releases.isEmpty, self.errorMessage != nil {
                    self.refreshFailedBanner
                }

                if self.releases.isEmpty, self.isRefreshing {
                    self.loadingCard
                    self.skeletonRows
                } else if self.releases.isEmpty {
                    self.emptyCard
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(self.releases.enumerated()), id: \.element) { index, release in
                            ChangelogReleaseCard(
                                release: release,
                                isLatest: index == 0,
                                isLast: index == self.releases.count - 1,
                                theme: self.theme,
                                colorScheme: self.colorScheme
                            )
                        }
                    }
                }

                self.footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.contentBackground)
        .task {
            self.loadCachedReleases()
            await self.refreshReleases()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("App")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.accent)
                Text("Changelog")
                    .basicsLabel(28)
                    .foregroundStyle(self.theme.palette.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if self.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 32)
            } else {
                LibraryPagePill(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    tone: .outline,
                    height: 32,
                    labelSize: 13
                ) {
                    Task { await self.refreshReleases() }
                }
                .help("Refresh changelog")
            }

            self.installedVersionChip
        }
    }

    /// The version this build actually is, straight off the bundle.
    private var installedVersionChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(self.theme.palette.accent)
                .frame(width: 6, height: 6)
            Text("You're on \(Self.installedVersion)")
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.accent)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(BasicsTokens.Semantic.brandSoft))
    }

    private static let installedVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    // MARK: - States

    private var refreshFailedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(self.theme.palette.warning)

            Text(self.errorMessage ?? "")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            LibraryPagePill(title: "Try again", tone: .outline, height: 28, labelSize: 12) {
                Task { await self.refreshReleases() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BasicsTokens.Semantic.warning.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BasicsTokens.Semantic.warning.opacity(0.30), lineWidth: 1)
                )
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading release notes…")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    /// Placeholder geometry only — it never shows a fabricated version or note.
    private var skeletonRows: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach([0.92, 0.62], id: \.self) { widthFraction in
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 8) {
                        self.skeletonBar(width: 74, height: 12)
                        self.skeletonBar(width: 96, height: 8)
                    }
                    .frame(width: 150, alignment: .leading)

                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 10) {
                            self.skeletonBar(width: geo.size.width * widthFraction, height: 10)
                            if widthFraction > 0.8 {
                                self.skeletonBar(width: geo.size.width * 0.68, height: 10)
                            }
                        }
                    }
                    .frame(height: widthFraction > 0.8 ? 30 : 10)
                }
            }
        }
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(self.theme.palette.separator)
            .frame(width: max(width, 0), height: height)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.scope")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text("No changelog available")
                .basicsLabel(17)
                .foregroundStyle(self.theme.palette.primaryText)

            Text("Basics Voice could not reach GitHub for release notes, and there is nothing saved on this Mac yet.")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            LibraryPagePill(title: "Try again", tone: .outline, height: 34, labelSize: 13) {
                Task { await self.refreshReleases() }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack {
            if let url = URL(string: "https://github.com/\(self.owner)/\(self.repo)/releases") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Older releases on GitHub")
                            .basicsButtonLabel(15)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(self.theme.palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Data

    private func loadCachedReleases() {
        let cacheKey = self.cacheKey
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let cache = try? JSONDecoder().decode(ChangelogCache.self, from: data)
        else { return }

        self.releases = Array(cache.releases.prefix(self.releaseLimit))
    }

    private func refreshReleases() async {
        guard !self.isRefreshing else { return }

        self.isRefreshing = true
        self.errorMessage = nil

        do {
            let includePrerelease = SettingsStore.shared.betaReleasesEnabled
            let fetched = try await SimpleUpdater.shared.fetchRecentReleaseNotes(
                owner: self.owner,
                repo: self.repo,
                limit: self.releaseLimit,
                includePrerelease: includePrerelease
            )
            let limitedReleases = Array(fetched.prefix(self.releaseLimit))
            self.releases = limitedReleases
            self.saveCachedReleases(limitedReleases)
        } catch {
            if self.releases.isEmpty {
                self.errorMessage = "Unable to load release notes."
            } else {
                self.errorMessage = "Showing saved release notes. Refresh failed."
            }
        }

        self.isRefreshing = false
    }

    private func saveCachedReleases(_ releases: [SimpleUpdater.ReleaseNote]) {
        let cache = ChangelogCache(releases: releases, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: self.cacheKey)
    }

    private var cacheKey: String {
        let channel = SettingsStore.shared.betaReleasesEnabled ? "beta" : "stable"
        return "FluidVoiceChangelogCache.\(channel)"
    }
}

private struct ChangelogCache: Codable {
    let releases: [SimpleUpdater.ReleaseNote]
    let savedAt: Date
}

// MARK: - Release row

private struct ChangelogReleaseCard: View {
    let release: SimpleUpdater.ReleaseNote
    let isLatest: Bool
    let isLast: Bool
    let theme: AppTheme
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 36) {
                self.versionColumn
                    .frame(width: 150, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(self.noteBlocks, id: \.self) { block in
                        ChangelogNoteBlock(block: block, theme: self.theme, colorScheme: self.colorScheme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 24)

            if !self.isLast {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)
                    .padding(.bottom, 24)
            }
        }
    }

    private var versionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(self.release.version)
                    .basicsLabel(self.isLatest ? 19 : 18)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)

                if self.isLatest {
                    Text("Latest")
                        .basicsMicroLabel(10)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .frame(height: 19)
                        .background(Capsule().fill(self.theme.palette.accent))
                }
            }

            if let published = self.release.publishedAt {
                Text(published.formatted(date: .abbreviated, time: .omitted))
                    .basicsMono(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            }

            if self.release.isPrerelease {
                Text("Beta")
                    .basicsLabel(11)
                    .foregroundStyle(self.theme.palette.warning)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Capsule().fill(BasicsTokens.Semantic.warning.opacity(0.16)))
            }

            if let headline = self.headline {
                Text(headline)
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = self.release.url {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("On GitHub")
                            .basicsButtonLabel(12)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(self.theme.palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .help("Open this release on GitHub")
            }
        }
    }

    /// GitHub release titles are often just the version again; only show the
    /// title when it actually says something the version does not.
    private var headline: String? {
        let title = self.release.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).lowercased()
        let normalizedVersion = self.release.version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).lowercased()
        return normalizedTitle == normalizedVersion ? nil : title
    }

    private var noteBlocks: [ChangelogNoteBlock.Model] {
        ChangelogNoteBlock.Model.make(
            from: self.release.notes,
            releaseTitle: self.release.title,
            version: self.release.version
        )
    }
}

// MARK: - Note blocks

private struct ChangelogNoteBlock: View {
    enum Kind: Hashable {
        case heading
        case bullet
        case paragraph
    }

    struct Model: Hashable {
        let kind: Kind
        let text: String

        static func make(from notes: String, releaseTitle: String, version: String) -> [Model] {
            var blocks: [Model] = []

            for rawLine in notes.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }

                if line.hasPrefix("#") {
                    let heading = String(line.drop { $0 == "#" })
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !self.shouldStop(atHeading: heading) else { break }
                    guard heading != releaseTitle, heading != version else { continue }

                    blocks.append(Model(kind: .heading, text: heading))
                    continue
                }

                guard !self.isBoilerplateLine(line) else { continue }

                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    blocks.append(Model(kind: .bullet, text: String(line.dropFirst(2))))
                    continue
                }

                blocks.append(Model(kind: .paragraph, text: line))
            }

            return blocks
        }

        private static func shouldStop(atHeading heading: String) -> Bool {
            heading.localizedCaseInsensitiveContains("contributors") ||
                heading.localizedCaseInsensitiveContains("need help")
        }

        private static func isBoilerplateLine(_ line: String) -> Bool {
            let lowercased = line.lowercased()
            return lowercased.contains("report issues:") ||
                lowercased.contains("github.com/altic-dev/fluidvoice/issues") ||
                lowercased.contains("github.com/altic-dev/fluid-oss/issues")
        }
    }

    let block: Model
    let theme: AppTheme
    let colorScheme: ColorScheme

    var body: some View {
        switch self.block.kind {
        case .heading:
            Text(self.block.text)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .padding(.top, 8)
                .padding(.bottom, 2)
        case .bullet:
            HStack(alignment: .top, spacing: 11) {
                Circle()
                    .fill(BasicsBorder.strong(self.theme, self.colorScheme))
                    .frame(width: 5, height: 5)
                    .padding(.top, 9)
                Text(self.markdownAttributedString(from: self.block.text))
                    .basicsProse(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph:
            Text(self.markdownAttributedString(from: self.block.text))
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdownAttributedString(from text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            return AttributedString(text)
        }
    }
}

#Preview {
    ChangelogView()
        .frame(width: 1096, height: 900)
}
