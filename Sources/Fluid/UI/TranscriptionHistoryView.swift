import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Waveform sampling

/// Real peak values read off the saved WAV — 12 buckets, normalised to the
/// loudest one. Nonisolated and `async`, so it runs off the main actor.
private func historyWaveformPeaks(url: URL, buckets: Int) async -> [CGFloat] {
    guard buckets > 0,
          let file = try? AVAudioFile(forReading: url)
    else { return [] }

    let frames = AVAudioFrameCount(file.length)
    guard frames > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
          (try? file.read(into: buffer)) != nil,
          let channel = buffer.floatChannelData?[0]
    else { return [] }

    let sampleCount = Int(buffer.frameLength)
    guard sampleCount > 0 else { return [] }

    let bucketSize = max(1, sampleCount / buckets)
    var peaks: [CGFloat] = []
    peaks.reserveCapacity(buckets)

    for bucket in 0..<buckets {
        let start = bucket * bucketSize
        let end = min(sampleCount, start + bucketSize)
        guard start < end else { break }

        var peak: Float = 0
        var index = start
        while index < end {
            peak = Swift.max(peak, Swift.abs(channel[index]))
            index += 1
        }
        peaks.append(CGFloat(peak))
    }

    let loudest = peaks.max() ?? 0
    guard loudest > 0 else { return Array(repeating: 0.2, count: peaks.count) }
    // 0.2 floor so a near-silent bucket still draws a bar rather than nothing.
    return peaks.map { Swift.max(0.2, $0 / loudest) }
}

// MARK: - Audio playback

/// Board "09 — History": the transport strip at the top of the detail pane.
/// Backed by a real `AVAudioPlayer` over the entry's saved WAV — the play
/// button plays, the bars scrub, and the clock is the player's own position.
@MainActor
final class HistoryAudioPlayer: ObservableObject {
    static let barCount = 12

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var peaks: [CGFloat] = []
    @Published private(set) var isReady: Bool = false

    private var player: AVAudioPlayer?
    private var loadedEntryID: UUID?

    /// Fraction of the clip already played, 0...1.
    var progress: Double {
        guard self.duration > 0 else { return 0 }
        return min(1, max(0, self.currentTime / self.duration))
    }

    func load(entry: TranscriptionHistoryEntry?) {
        let entryID = entry?.id
        guard entryID != self.loadedEntryID else { return }

        self.player?.stop()
        self.player = nil
        self.isPlaying = false
        self.currentTime = 0
        self.duration = 0
        self.peaks = []
        self.isReady = false
        self.loadedEntryID = entryID

        guard let entry else { return }

        // Metadata duration is the fallback so the clock is never blank while
        // the file is still being opened.
        if let audio = entry.audio {
            self.duration = Double(audio.durationMilliseconds) / 1000
        }

        guard let url = DictationAudioHistoryStore.shared.audioFileURL(for: entry),
              FileManager.default.fileExists(atPath: url.path)
        else { return }

        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            self.player = player
            self.duration = player.duration
            self.isReady = true
        }

        Task {
            let values = await historyWaveformPeaks(url: url, buckets: Self.barCount)
            guard self.loadedEntryID == entryID else { return }
            self.peaks = values
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            self.isPlaying = false
        } else {
            if player.currentTime >= player.duration - 0.05 {
                player.currentTime = 0
            }
            player.play()
            self.isPlaying = true
        }
        self.currentTime = player.currentTime
    }

    func seek(toFraction fraction: Double) {
        guard let player, player.duration > 0 else { return }
        player.currentTime = max(0, min(player.duration, fraction * player.duration))
        self.currentTime = player.currentTime
    }

    /// Driven by the view's timer publisher — AVAudioPlayer has no position
    /// callback, so the clock is polled.
    func tick() {
        guard let player else { return }
        self.currentTime = player.currentTime
        if self.isPlaying, !player.isPlaying {
            self.isPlaying = false
        }
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - History

/// Boards "09 — History" (`1GV-0`) plus its entry-menu, report, alert,
/// no-audio / AI-failure, empty and no-results states.
///
/// Fixed 340pt list on the snow ground, a hairline, then the detail pane on
/// white. Every value on screen comes from `TranscriptionHistoryStore` or the
/// saved audio file — nothing here is sample data.
struct TranscriptionHistoryView: View {
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchQuery: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var showReportConfirmation: Bool = false
    @State private var selectedReportEntry: TranscriptionHistoryEntry?
    @State private var selectedEntryID: UUID?
    @State private var hoveredEntryID: UUID?
    @StateObject private var audio = HistoryAudioPlayer()
    @State private var ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter
    }()

    private var filteredEntries: [TranscriptionHistoryEntry] {
        self.historyStore.search(query: self.searchQuery)
    }

    private var selectedEntry: TranscriptionHistoryEntry? {
        guard let id = selectedEntryID else { return self.filteredEntries.first }
        return self.filteredEntries.first(where: { $0.id == id })
    }

    var body: some View {
        HStack(spacing: 0) {
            self.listPane
                .frame(width: 340)

            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(width: 1)

            Group {
                if let entry = selectedEntry {
                    self.detailPane(entry)
                } else {
                    self.noSelectionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(self.theme.palette.cardBackground)
        .onAppear {
            if self.selectedEntryID == nil {
                self.selectedEntryID = self.filteredEntries.first?.id
            }
            self.audio.load(entry: self.selectedEntry)
        }
        .onChange(of: self.selectedEntry?.id) { _, _ in
            self.audio.load(entry: self.selectedEntry)
        }
        .onReceive(self.ticker) { _ in
            self.audio.tick()
        }
        .alert("Clear all history", isPresented: self.$showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear all", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.historyStore.clearAllHistory()
                    self.selectedEntryID = nil
                }
            }
        } message: {
            Text(
                "This will permanently delete all \(self.historyStore.entries.count) transcription entries. This action cannot be undone."
            )
        }
        .alert("Report sent", isPresented: self.$showReportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you for helping improve Basics Voice dictation.")
        }
        .sheet(item: self.$selectedReportEntry) { entry in
            TranscriptionFeedbackReportSheet(entry: entry) {
                self.selectedReportEntry = nil
                self.showReportConfirmation = true
            }
            .environment(\.theme, self.theme)
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("History")
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)

                self.searchField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 16)

            if self.filteredEntries.isEmpty {
                self.emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(self.filteredEntries) { entry in
                            self.entryRow(entry)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            self.footerView
        }
        .background(self.theme.palette.windowBackground)
    }

    private var searchPlaceholder: String {
        let count = self.historyStore.entries.count
        guard count > 0 else { return "Search transcriptions" }
        return "Search \(self.formatNumber(count)) entries"
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)

            TextField(self.searchPlaceholder, text: self.$searchQuery)
                .textFieldStyle(.plain)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.primaryText)

            if !self.searchQuery.isEmpty {
                Button {
                    self.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(self.theme.palette.cardBackground)
                .overlay(Capsule().stroke(self.theme.palette.cardBorder, lineWidth: 1))
        )
    }

    // MARK: - Entry row

    private func rowDurationText(_ entry: TranscriptionHistoryEntry) -> String {
        let time = Self.rowTimeFormatter.string(from: entry.timestamp)
        guard let audio = entry.audio, self.hasAudio(entry) else { return time }
        return "\(time) · \(HistoryAudioPlayer.clock(Double(audio.durationMilliseconds) / 1000))"
    }

    private func entryRow(_ entry: TranscriptionHistoryEntry) -> some View {
        let isSelected = self.selectedEntryID == entry.id
        let isHovered = self.hoveredEntryID == entry.id
        let accent = self.theme.palette.accent

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.selectedEntryID = entry.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(self.rowDurationText(entry))
                        .basicsMono(11)
                        .foregroundStyle(isSelected ? accent : self.theme.palette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)

                    Text(entry.appName.isEmpty ? "Unknown app" : entry.appName)
                        .basicsMicroLabel(10)
                        .foregroundStyle(isSelected ? accent : self.theme.palette.tertiaryText)
                        .lineLimit(1)

                    if entry.wasAIProcessed {
                        Text("AI")
                            .basicsMicroLabel(9)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(accent))
                    }

                    if entry.aiProcessingError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.theme.palette.warning)
                            .help(entry.aiProcessingError ?? "")
                    }
                }

                Text(entry.previewText)
                    .basicsProse(14)
                    .foregroundStyle(
                        isSelected ? self.theme.palette.primaryText : self.theme.palette.secondaryText
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(self.rowFill(isSelected: isSelected, isHovered: isHovered))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hoveredEntryID = hovering ? entry.id : nil
        }
        .contextMenu { self.entryMenu(entry) }
    }

    private func rowFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return self.theme.palette.accent.opacity(0.10) }
        if isHovered { return self.theme.palette.sidebarBackground }
        return .clear
    }

    @ViewBuilder
    private func entryMenu(_ entry: TranscriptionHistoryEntry) -> some View {
        Button(entry.wasAIProcessed ? "Copy AI text" : "Copy text") {
            self.copyToClipboard(entry.processedText)
        }

        if entry.wasAIProcessed {
            Button("Copy raw text") {
                self.copyToClipboard(entry.rawText)
            }
            Button("Copy both") {
                self.copyToClipboard(self.combinedText(for: entry))
            }
        }

        if self.hasAudio(entry) {
            Divider().hidden()
            Button("Export pair...") { self.exportPair(entry) }
            Button("Reveal audio") { self.revealAudio(entry) }
        }

        Divider().hidden()

        Button("Report bad result...") {
            self.openFeedbackReport(for: entry)
        }

        Divider().hidden()

        Button("Delete", role: .destructive) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.deleteEntry(entry)
            }
        }
    }

    // MARK: - Empty states

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if self.searchQuery.isEmpty {
                ZStack {
                    Circle()
                        .fill(self.theme.palette.accent.opacity(0.10))
                        .frame(width: 44, height: 44)

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(self.theme.palette.accent)
                }
            }

            Text(self.searchQuery.isEmpty ? "No history yet" : "No results")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.searchQuery.isEmpty
                ? "Your transcriptions will appear here as soon as you dictate."
                : "Try a different search term.")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 230)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
    }

    private var noSelectionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text("Select a transcription")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.theme.palette.cardBackground)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            HStack {
                Text(self.historyStore.entries.isEmpty
                    ? "No entries"
                    : "\(self.formatNumber(self.historyStore.entries.count)) entries")
                    .basicsMono(11)
                    .foregroundStyle(self.theme.palette.secondaryText)

                Spacer()

                if !self.historyStore.entries.isEmpty {
                    LibraryPagePill(
                        title: "Clear all",
                        tone: .danger,
                        height: 26,
                        labelSize: 12
                    ) {
                        self.showClearConfirmation = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
    }

    // MARK: - Detail pane

    private func detailPane(_ entry: TranscriptionHistoryEntry) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if self.hasAudio(entry) {
                    self.audioTransport
                } else {
                    self.noAudioRow
                }

                if let error = entry.aiProcessingError {
                    self.aiFailureBanner(error)
                }

                if entry.wasAIProcessed {
                    self.textBlock(
                        label: "Raw transcription",
                        text: entry.rawText,
                        color: self.theme.palette.secondaryText
                    )
                    self.enhancedCard(entry.processedText)
                } else {
                    self.textBlock(
                        label: "Final text · what was typed",
                        text: entry.processedText,
                        color: self.theme.palette.primaryText
                    )
                }

                self.actionRow(entry)
                self.detailsGrid(entry)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(self.theme.palette.cardBackground)
    }

    // MARK: Transport

    private var audioTransport: some View {
        HStack(spacing: 12) {
            Button {
                self.audio.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(self.theme.palette.accent)
                        .frame(width: 34, height: 34)

                    Image(systemName: self.audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!self.audio.isReady)
            .opacity(self.audio.isReady ? 1 : 0.45)
            .help(self.audio.isPlaying ? "Pause" : "Play this recording")

            self.waveform

            Spacer(minLength: 12)

            Text("\(HistoryAudioPlayer.clock(self.audio.currentTime)) / \(HistoryAudioPlayer.clock(self.audio.duration))")
                .basicsMono(12)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(height: 34)
    }

    private var waveform: some View {
        let peaks = self.audio.peaks
        let played = Int((Double(HistoryAudioPlayer.barCount) * self.audio.progress).rounded())

        return HStack(alignment: .center, spacing: 2) {
            ForEach(0..<HistoryAudioPlayer.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        index < played
                            ? self.theme.palette.accent
                            : BasicsBorder.strong(self.theme, self.colorScheme)
                    )
                    .frame(
                        width: 3,
                        height: index < peaks.count ? max(6, peaks[index] * 28) : 6
                    )
            }
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    // 12 bars at 3pt with 2pt gutters = 58pt of scrub track.
                    let track: CGFloat = CGFloat(HistoryAudioPlayer.barCount) * 5 - 2
                    self.audio.seek(toFraction: Double(value.location.x / track))
                }
        )
        .help("Click to scrub")
    }

    private var noAudioRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text("No audio was saved for this entry — turn on Keep audio recordings in Voice engine.")
                .basicsProse(13)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: 34)
    }

    // MARK: Text blocks

    private func textBlock(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text(text)
                .basicsProse(15)
                .lineSpacing(6)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func enhancedCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enhanced · what was typed")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)

            Text(text)
                .basicsProse(15)
                .lineSpacing(6)
                .foregroundStyle(self.theme.palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private func aiFailureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(self.theme.palette.warning)

            VStack(alignment: .leading, spacing: 5) {
                Text("AI enhancement failed — the raw transcription was typed instead")
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .basicsMono(11)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.warning.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                        .stroke(self.theme.palette.warning, lineWidth: 1)
                )
        )
    }

    // MARK: Actions

    private func actionRow(_ entry: TranscriptionHistoryEntry) -> some View {
        HStack(spacing: 8) {
            LibraryPagePill(
                title: entry.wasAIProcessed ? "Copy AI" : "Copy",
                height: 32,
                labelSize: 13
            ) {
                self.copyToClipboard(entry.processedText)
            }

            if entry.wasAIProcessed {
                LibraryPagePill(title: "Copy raw", height: 32, labelSize: 13) {
                    self.copyToClipboard(entry.rawText)
                }

                LibraryPagePill(title: "Copy both", height: 32, labelSize: 13) {
                    self.copyToClipboard(self.combinedText(for: entry))
                }
            }

            if self.hasAudio(entry) {
                LibraryPagePill(title: "Export pair", height: 32, labelSize: 13) {
                    self.exportPair(entry)
                }

                LibraryPagePill(title: "Reveal audio", height: 32, labelSize: 13) {
                    self.revealAudio(entry)
                }
            }

            LibraryPagePill(title: "Report", systemImage: "flag", height: 32, labelSize: 13) {
                self.openFeedbackReport(for: entry)
            }
            .help("Review and send this example to Basics Voice")

            LibraryPagePill(title: "Delete", tone: .danger, height: 32, labelSize: 13) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.deleteEntry(entry)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Details

    private func detailsGrid(_ entry: TranscriptionHistoryEntry) -> some View {
        let cells: [(label: String, value: String, style: DetailValueStyle)] = [
            ("Application", entry.appName.isEmpty ? "Unknown" : entry.appName, .label),
            ("Window", entry.windowTitle.isEmpty ? "Unknown" : entry.windowTitle, .label),
            ("Characters", "\(entry.characterCount)", .mono),
            ("AI processed", entry.wasAIProcessed ? "Yes" : "No", .brand),
            ("Audio", self.audioMetadataText(for: entry), .mono),
        ]

        return VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    self.detailCell(label: cell.label, value: cell.value, style: cell.style)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            if index > 0 {
                                Rectangle()
                                    .fill(self.theme.palette.separator)
                                    .frame(width: 1)
                            }
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .stroke(self.theme.palette.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous))
        }
        .padding(.top, 8)
    }

    private enum DetailValueStyle {
        case label
        case mono
        case brand
    }

    @ViewBuilder
    private func detailCell(label: String, value: String, style: DetailValueStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .basicsLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .lineLimit(1)

            switch style {
            case .label:
                Text(value)
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .mono:
                Text(value)
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .lineLimit(1)
            case .brand:
                Text(value)
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func deleteEntry(_ entry: TranscriptionHistoryEntry) {
        let nextEntry = self.filteredEntries.first(where: { $0.id != entry.id })
        self.historyStore.deleteEntry(id: entry.id)
        if self.selectedEntryID == entry.id || self.selectedEntryID == nil {
            self.selectedEntryID = nextEntry?.id
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openFeedbackReport(for entry: TranscriptionHistoryEntry) {
        self.selectedReportEntry = entry
    }

    private func combinedText(for entry: TranscriptionHistoryEntry) -> String {
        "\(entry.rawText)\n\n\(entry.processedText)"
    }

    private func hasAudio(_ entry: TranscriptionHistoryEntry) -> Bool {
        DictationAudioHistoryStore.shared.audioFileExists(for: entry)
    }

    private func audioMetadataText(for entry: TranscriptionHistoryEntry) -> String {
        guard let audio = entry.audio, self.hasAudio(entry) else { return "No" }
        let seconds = Double(audio.durationMilliseconds) / 1000.0
        let size = ByteCountFormatter.string(fromByteCount: Int64(audio.byteCount), countStyle: .file)
        return "\(String(format: "%.1f", seconds))s · \(size)"
    }

    private func revealAudio(_ entry: TranscriptionHistoryEntry) {
        guard let url = DictationAudioHistoryStore.shared.audioFileURL(for: entry),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportPair(_ entry: TranscriptionHistoryEntry) {
        do {
            guard self.hasAudio(entry) else { throw DictationAudioHistoryError.audioMissing }
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = DictationAudioHistoryStore.shared.suggestedPairExportFilename(for: entry)

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try DictationAudioHistoryStore.shared.exportPair(entry: entry, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Pair export failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Report sheet

/// Board "09 — History · report datapoint" (`395-0`).
private struct TranscriptionFeedbackReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText: String
    @State private var outputText: String
    @State private var processingModel: String
    @State private var comment: String
    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    let onSent: () -> Void

    init(entry: TranscriptionHistoryEntry, onSent: @escaping () -> Void) {
        _inputText = State(initialValue: entry.rawText)
        _outputText = State(initialValue: entry.processedText)
        _processingModel = State(initialValue: Self.reportModel(for: entry))
        _comment = State(initialValue: "")
        self.onSent = onSent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Share anonymous datapoint")
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text("Help improve our model. Only the example shown below will be sent.")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                self.feedbackField(title: "Raw text", text: self.$inputText, height: 88, isMono: false)
                self.feedbackField(title: "Processed text", text: self.$outputText, height: 88, isMono: false)

                HStack(alignment: .top, spacing: 16) {
                    self.feedbackField(
                        title: "Processing model",
                        text: self.$processingModel,
                        height: 40,
                        isMono: true
                    )
                    self.feedbackField(
                        title: "Comment · optional",
                        text: self.$comment,
                        height: 40,
                        isMono: false
                    )
                }
            }

            HStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .basicsProse(13)
                        .foregroundStyle(BasicsTokens.Semantic.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                LibraryPagePill(title: "Cancel", height: 34, labelSize: 13) {
                    self.dismiss()
                }
                .disabled(self.isSending)

                if self.isSending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Sending...")
                            .basicsButtonLabel(13)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(Capsule().fill(self.theme.palette.accent.opacity(0.55)))
                } else {
                    LibraryPagePill(
                        title: "Send example",
                        tone: .brand,
                        height: 34,
                        labelSize: 13
                    ) {
                        Task { await self.sendReport() }
                    }
                    .disabled(self.isSendDisabled)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(width: 560)
        .background(self.theme.palette.cardBackground)
    }

    private var isSendDisabled: Bool {
        self.isSending ||
            (self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                self.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            self.processingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendReport() async {
        let payload = TranscriptionFeedbackReporter.Payload(
            rawText: self.inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            processedText: self.outputText.trimmingCharacters(in: .whitespacesAndNewlines),
            processingModel: self.processingModel.trimmingCharacters(in: .whitespacesAndNewlines),
            comments: self.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        self.isSending = true
        self.errorMessage = nil
        do {
            try await TranscriptionFeedbackReporter.submit(payload)
            self.isSending = false
            self.onSent()
        } catch {
            self.errorMessage = error.localizedDescription
            self.isSending = false
        }
    }

    private func feedbackField(
        title: String,
        text: Binding<String>,
        height: CGFloat,
        isMono: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            TextEditor(text: text)
                .font(isMono ? BasicsTokens.mono(12) : BasicsTokens.prose(13))
                .foregroundStyle(self.theme.palette.primaryText)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                        .fill(self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                                .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func reportModel(for entry: TranscriptionHistoryEntry) -> String {
        let model = entry.processingModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return model.isEmpty ? "unknown" : model
    }
}

#Preview {
    TranscriptionHistoryView()
        .frame(width: 1096, height: 900)
        .environment(\.theme, AppTheme.light(accent: BasicsTokens.Semantic.brand))
}
