import AVFoundation
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

/// Board "08 — Meeting transcription" and its six state boards.
///
/// The whole page is one lane on the white main surface: page head, then the
/// single card that changes shape as the run progresses (dropzone → file card →
/// file card + progress → result card), then the hairline-separated recent list.
/// Every value on screen is read off `MeetingTranscriptionService`,
/// `FileTranscriptionHistoryStore` or the file on disk — nothing is authored here.
struct MeetingTranscriptionView: View {
    @ObservedObject var asrService: ASRService
    @StateObject private var transcriptionService: MeetingTranscriptionService
    @ObservedObject private var fileHistoryStore = FileTranscriptionHistoryStore.shared
    @State private var selectedFileURL: URL?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    init(asrService: ASRService) {
        self.asrService = asrService
        _transcriptionService = StateObject(wrappedValue: MeetingTranscriptionService(asrService: asrService))
    }

    @State private var showingFilePicker = false
    @State private var showingExportSheet = false
    @State private var showingExportPanel = false
    @State private var exportResult: TranscriptionResult?
    @State private var exportFormat: ExportFormat = .text
    @State private var exportFileName: String = "transcript.txt"
    @State private var showingCopyConfirmation = false
    @State private var isDropTargeted = false
    @State private var incomingDropName: String?
    @State private var dropErrorMessage: String?
    @State private var selectedFileDuration: TimeInterval?
    @State private var isPreparingModel = false

    enum ExportFormat: String, CaseIterable {
        case text = "Text (.txt)"
        case json = "JSON (.json)"

        var fileExtension: String {
            switch self {
            case .text: return "txt"
            case .json: return "json"
            }
        }
    }

    // MARK: - Board metrics

    private enum Board {
        /// Board: every state card on this page is a 16pt rounded rectangle.
        static let card: CGFloat = 16
        static let notice: CGFloat = 14
        static let row: CGFloat = 52
        /// Fixed trailing lanes so the recent rows line up column by column.
        static let durationLane: CGFloat = 72
        static let wordsLane: CGFloat = 96
    }

    /// Copied off the @MainActor service so the drop handler — which runs on a
    /// background queue — can read them without hopping.
    private static let supportedFileExtensions = MeetingTranscriptionService.supportedFileExtensions
    private static let dropErrorCopy = MeetingTranscriptionService.dropErrorCopy

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                self.pageHead

                if !self.asrService.modelsExistOnDisk, !self.asrService.isAsrReady {
                    self.noModelCard
                }

                self.stateCard

                if let error = self.transcriptionService.error {
                    self.transcriptionErrorCard(error: error)
                }

                if let message = self.dropErrorMessage {
                    self.dropErrorCard(message: message)
                }

                if let result = self.transcriptionService.result {
                    self.transcriptBlock(text: result.text)
                } else {
                    if !self.fileHistoryStore.entries.isEmpty {
                        self.recentTranscriptionsSection
                    }

                    if let entry = self.fileHistoryStore.selectedEntry {
                        self.historyDetailCard(entry: entry)
                        self.transcriptBlock(text: entry.text)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.contentBackground)
        .overlay(alignment: .topTrailing) {
            if self.showingCopyConfirmation {
                self.copiedToast
                    .padding(.top, 28)
                    .padding(.trailing, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if self.showingExportSheet {
                self.exportSheet
            }
        }
        .fileImporter(
            isPresented: self.$showingFilePicker,
            allowedContentTypes: MeetingTranscriptionService.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    self.select(url: url)
                }
            case let .failure(error):
                DebugLogger.shared.error("File picker error: \(error)", source: "MeetingTranscriptionView")
            }
        }
        .fileExporter(
            isPresented: self.$showingExportPanel,
            document: TranscriptionDocument(
                result: self.exportResult ?? TranscriptionResult(
                    text: "",
                    confidence: 0,
                    duration: 0,
                    processingTime: 0,
                    fileName: "transcript"
                ),
                format: self.exportFormat,
                service: self.transcriptionService
            ),
            contentType: self.exportFormat == .text ? .plainText : .json,
            defaultFilename: self.exportFileName
        ) { exportCompletion in
            switch exportCompletion {
            case .success:
                DebugLogger.shared.info("File exported successfully", source: "MeetingTranscriptionView")
            case let .failure(error):
                DebugLogger.shared.error("Export failed: \(error)", source: "MeetingTranscriptionView")
            }
            self.exportResult = nil
        }
        .task {
            await self.asrService.checkIfModelsExistAsync()
        }
    }

    // MARK: - Page head

    private var pageHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text("Meeting transcription")
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Text("Drop in a recording you already have. This runs on the same on-device model as dictation, so nothing is uploaded.")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 700, alignment: .leading)
        }
    }

    // MARK: - The one card that changes shape

    @ViewBuilder
    private var stateCard: some View {
        if let result = self.transcriptionService.result {
            self.resultCard(result: result)
        } else if let fileURL = self.selectedFileURL {
            self.fileCard(fileURL: fileURL)
        } else {
            self.dropzone
        }
    }

    // MARK: - Dropzone

    private var dropzone: some View {
        let enabled = self.asrService.modelsExistOnDisk || self.asrService.isAsrReady

        return Button {
            self.showingFilePicker = true
        } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(self.isDropTargeted
                            ? self.theme.palette.accent
                            : BasicsTokens.Semantic.brandSoft)
                        .frame(width: 52, height: 52)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(self.isDropTargeted ? Color.white : self.theme.palette.accent)
                }

                Text(self.isDropTargeted ? "Release to transcribe" : "Drop an audio or video file")
                    .basicsLabel(17)
                    .foregroundStyle(self.isDropTargeted
                        ? self.theme.palette.accent
                        : self.theme.palette.primaryText)

                Text(self.dropzoneSubtitle)
                    .basicsProse(14)
                    .foregroundStyle(self.isDropTargeted
                        ? self.theme.palette.accent
                        : self.theme.palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .background(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .fill(self.isDropTargeted
                    ? BasicsTokens.Semantic.brandSoft
                    : self.theme.palette.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .strokeBorder(
                    self.isDropTargeted
                        ? self.theme.palette.accent
                        : BasicsBorder.strong(self.theme, self.colorScheme),
                    style: StrokeStyle(lineWidth: 1.5, dash: self.isDropTargeted ? [7, 5] : [])
                )
        )
        .animation(.easeOut(duration: 0.16), value: self.isDropTargeted)
        .onDrop(
            of: [UTType.fileURL],
            delegate: MeetingDropDelegate(
                isEnabled: enabled,
                onTargetChange: { targeted, name in
                    self.isDropTargeted = targeted
                    self.incomingDropName = name
                },
                onPerform: { providers in self.handleDrop(providers: providers) }
            )
        )
    }

    private var dropzoneSubtitle: String {
        if self.isDropTargeted, let name = self.incomingDropName {
            return name
        }
        return "or click to browse — \(Self.browsableExtensions)"
    }

    /// The five formats the picker leads with, taken from the extension set the
    /// service actually accepts (never a hard-coded list).
    private static let browsableExtensions: String = {
        let preferred = ["m4a", "mp3", "wav", "mov", "mp4"]
        let available = preferred.filter { Self.supportedFileExtensions.contains($0) }
        return available.isEmpty
            ? Self.supportedFileExtensions.sorted().prefix(5).joined(separator: ", ")
            : available.joined(separator: ", ")
    }()

    // MARK: - File card (selected · transcribing · error)

    private func fileCard(fileURL: URL) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BasicsTokens.Semantic.brandSoft)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(self.theme.palette.accent)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(fileURL.lastPathComponent)
                        .basicsLabel(17)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(self.fileMetaLine(fileURL: fileURL))
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !self.transcriptionService.isTranscribing {
                    Button {
                        self.clearSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(self.theme.palette.cardBackground)
                                    .overlay(Circle().stroke(self.theme.palette.cardBorder, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Clear selected file")
                }

                if self.transcriptionService.isTranscribing {
                    LibraryPagePill(
                        title: "Transcribing…",
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: .quiet,
                        height: 38,
                        labelSize: 14
                    ) {}
                        .disabled(true)
                } else {
                    LibraryPagePill(
                        title: self.transcriptionService.error == nil ? "Transcribe" : "Try again",
                        systemImage: nil,
                        tone: .brand,
                        height: 38,
                        labelSize: 14
                    ) {
                        Task { await self.transcribeFile() }
                    }
                }
            }

            if self.transcriptionService.isTranscribing {
                VStack(alignment: .leading, spacing: 11) {
                    self.progressTrack

                    HStack(spacing: 12) {
                        Text(self.transcriptionService.currentStatus)
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(Int((self.transcriptionService.progress * 100).rounded()))%")
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.accent)
                            .frame(width: 44, alignment: .trailing)
                    }

                    self.phaseTrail
                        .padding(.top, 4)
                }
                .padding(.top, 18)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(self.theme.palette.separator)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(self.theme.palette.separator)
                Capsule()
                    .fill(self.theme.palette.accent)
                    .frame(width: max(0, geo.size.width * min(max(self.transcriptionService.progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.25), value: self.transcriptionService.progress)
    }

    /// PREPARING MODELS — ANALYZING AUDIO — TRANSCRIBING, lit from the progress
    /// value the service publishes (0.1 / 0.2 / 0.3+).
    private var phaseTrail: some View {
        let phases = ["Preparing models", "Analyzing audio", "Transcribing"]
        let progress = self.transcriptionService.progress
        let active: Int = progress >= 0.3 ? 2 : (progress >= 0.2 ? 1 : 0)

        return HStack(spacing: 10) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                if index > 0 {
                    Rectangle()
                        .fill(BasicsBorder.strong(self.theme, self.colorScheme))
                        .frame(width: 14, height: 1)
                }
                Text(phase)
                    .basicsMicroLabel(11)
                    .foregroundStyle(index == active
                        ? self.theme.palette.accent
                        : self.theme.palette.tertiaryText)
            }
        }
    }

    // MARK: - Result card

    private func resultCard(result: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(self.theme.palette.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcription complete")
                        .basicsLabel(17)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text(result.fileName)
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    self.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(self.theme.palette.cardBackground)
                                .overlay(Circle().stroke(self.theme.palette.cardBorder, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .help("Start another transcription")

                LibraryPagePill(title: "Copy", systemImage: "doc.on.doc", tone: .outline, height: 34, labelSize: 13) {
                    self.copyToClipboard(result.text)
                }

                LibraryPagePill(title: "Export", systemImage: "square.and.arrow.down", tone: .brand, height: 34, labelSize: 13) {
                    self.presentExport(for: result)
                }
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)

                HStack(spacing: 32) {
                    self.statBlock(
                        label: "Processing time",
                        value: "\(String(format: "%.1f", result.processingTime))s",
                        isBrand: false
                    )
                    self.statDivider
                    self.statBlock(
                        label: "Confidence",
                        value: "\(Int((result.confidence * 100).rounded()))%",
                        isBrand: false
                    )
                    if result.processingTime > 0 {
                        self.statDivider
                        self.statBlock(
                            label: "Faster than realtime",
                            value: "\(String(format: "%.1f", result.duration / result.processingTime))×",
                            isBrand: true
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private func statBlock(label: String, value: String, isBrand: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
            Text(value)
                .basicsMono(15)
                .foregroundStyle(isBrand ? self.theme.palette.accent : self.theme.palette.primaryText)
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(self.theme.palette.separator)
            .frame(width: 1, height: 34)
    }

    // MARK: - Transcript

    private func transcriptBlock(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text(text)
                .basicsProse(15)
                .lineSpacing(5)
                .foregroundStyle(self.theme.palette.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 900, alignment: .leading)
        }
    }

    // MARK: - Recent transcriptions

    private var recentTranscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Recent transcriptions")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LibraryPagePill(title: "Clear all", systemImage: nil, tone: .ghost, height: 26, labelSize: 12) {
                    self.fileHistoryStore.clearAll()
                }
            }

            VStack(spacing: 0) {
                ForEach(self.fileHistoryStore.entries) { entry in
                    self.recentEntryRow(entry: entry)
                }
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)
            }
        }
    }

    private func recentEntryRow(entry: FileTranscriptionEntry) -> some View {
        let isSelected = self.fileHistoryStore.selectedEntryID == entry.id

        return VStack(spacing: 0) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)

            Button {
                self.fileHistoryStore.selectedEntryID = isSelected ? nil : entry.id
            } label: {
                HStack(spacing: 20) {
                    Image(systemName: "doc")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isSelected ? self.theme.palette.accent : self.theme.palette.secondaryText)
                        .frame(width: 17, height: 17)

                    Text(entry.fileName)
                        .basicsLabel(15)
                        .foregroundStyle(isSelected ? self.theme.palette.accent : self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(Self.clockString(entry.duration))
                        .basicsMono(12)
                        .foregroundStyle(isSelected ? self.theme.palette.accent : self.theme.palette.secondaryText)
                        .frame(width: Board.durationLane, alignment: .trailing)

                    Text(Self.wordCountString(entry.text))
                        .basicsMono(12)
                        .foregroundStyle(isSelected ? self.theme.palette.accent : self.theme.palette.tertiaryText)
                        .frame(width: Board.wordsLane, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .frame(height: Board.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(isSelected ? BasicsTokens.Semantic.brandSoft : Color.clear)
            )
        }
    }

    // MARK: - History detail

    private func historyDetailCard(entry: FileTranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("From history")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                    Text(entry.fileName)
                        .basicsLabel(17)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LibraryPagePill(title: "Copy", systemImage: nil, tone: .outline, height: 34, labelSize: 13) {
                    self.copyToClipboard(entry.text)
                }

                LibraryPagePill(title: "Export", systemImage: nil, tone: .outline, height: 34, labelSize: 13) {
                    self.presentExport(for: entry.toTranscriptionResult())
                }

                LibraryPagePill(title: "Remove", systemImage: nil, tone: .danger, height: 34, labelSize: 13) {
                    self.fileHistoryStore.deleteEntry(id: entry.id)
                }
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)

                HStack(spacing: 28) {
                    Text(Self.clockString(entry.duration))
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    self.metaDivider
                    Text("\(Int((entry.confidence * 100).rounded()))% confidence")
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    self.metaDivider
                    Text(entry.fullDateString)
                        .basicsMono(12)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .fill(self.theme.palette.windowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                        .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                )
        )
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(BasicsBorder.strong(self.theme, self.colorScheme))
            .frame(width: 1, height: 14)
    }

    // MARK: - Notices

    /// Board "08 · no model". `modelsExistOnDisk` is the real signal, and the
    /// action runs the same model preparation Voice engine runs.
    private var noModelCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(self.theme.palette.accent)

            VStack(alignment: .leading, spacing: 5) {
                Text("No voice model on this Mac yet")
                    .basicsLabel(17)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("Meeting transcription runs on the same on-device model as dictation. Download \(SettingsStore.shared.selectedSpeechModel.displayName) and this page will work offline.")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 740, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LibraryPagePill(
                title: self.isPreparingModel ? "Downloading…" : "Download model",
                systemImage: nil,
                tone: self.isPreparingModel ? .quiet : .brand,
                height: 38,
                labelSize: 14
            ) {
                self.prepareModel()
            }
            .disabled(self.isPreparingModel || self.asrService.isDownloadingModel)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                .fill(BasicsTokens.Semantic.brandSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Board.card, style: .continuous)
                        .stroke(self.theme.palette.accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func transcriptionErrorCard(error: String) -> some View {
        let parts = Self.split(error: error)
        return self.noticeCard(
            icon: "exclamationmark.circle",
            tint: BasicsTokens.Semantic.danger,
            fillOpacity: 0.06,
            borderOpacity: 0.22,
            title: parts.title,
            detail: parts.detail
        ) {
            self.transcriptionService.reset()
        }
    }

    private func dropErrorCard(message: String) -> some View {
        self.noticeCard(
            icon: "exclamationmark.triangle",
            tint: BasicsTokens.Semantic.warning,
            fillOpacity: 0.09,
            borderOpacity: 0.30,
            title: "That file type will not transcribe",
            detail: message
        ) {
            self.dropErrorMessage = nil
        }
    }

    private func noticeCard(
        icon: String,
        tint: Color,
        fillOpacity: Double,
        borderOpacity: Double,
        title: String,
        detail: String?,
        dismiss: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LibraryPagePill(title: "Dismiss", systemImage: nil, tone: .outline, height: 30, labelSize: 13, action: dismiss)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Board.notice, style: .continuous)
                .fill(tint.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: Board.notice, style: .continuous)
                        .stroke(tint.opacity(borderOpacity), lineWidth: 1)
                )
        )
    }

    // MARK: - Toast

    private var copiedToast: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BasicsTokens.Green.g300)
            Text("Copied to clipboard")
                .basicsLabel(13)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Capsule().fill(BasicsTokens.Green.g950))
        .shadow(color: BasicsTokens.Ink.foreground.opacity(0.16), radius: 12, x: 0, y: 8)
    }

    // MARK: - Export sheet

    private var exportSheet: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { self.showingExportSheet = false }

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export transcription")
                        .basicsLabel(22)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("Saves the text to disk. The audio file stays where it is.")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Format")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    HStack(spacing: 4) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Button {
                                self.exportFormat = format
                                self.exportFileName = Self.fileName(
                                    base: self.exportResult?.fileName ?? "transcript",
                                    format: format
                                )
                            } label: {
                                Text(format.rawValue)
                                    .basicsButtonLabel(13)
                                    .foregroundStyle(self.exportFormat == format
                                        ? self.theme.palette.primaryText
                                        : self.theme.palette.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(self.exportFormat == format
                                                ? self.theme.palette.cardBackground
                                                : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .stroke(
                                                        self.exportFormat == format
                                                            ? BasicsBorder.strong(self.theme, self.colorScheme)
                                                            : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(self.theme.palette.sidebarBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(self.theme.palette.cardBorder, lineWidth: 1)
                            )
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Save as")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    TextField("transcript.\(self.exportFormat.fileExtension)", text: self.$exportFileName)
                        .textFieldStyle(.plain)
                        .basicsMono(13)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                                .fill(self.theme.palette.windowBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                                        .stroke(BasicsBorder.strong(self.theme, self.colorScheme), lineWidth: 1)
                                )
                        )
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    LibraryPagePill(title: "Cancel", systemImage: nil, tone: .outline, height: 38, labelSize: 14) {
                        self.showingExportSheet = false
                    }
                    LibraryPagePill(title: "Export", systemImage: nil, tone: .brand, height: 38, labelSize: 14) {
                        self.showingExportSheet = false
                        self.showingExportPanel = true
                    }
                }
                .padding(.top, 6)
            }
            .padding(28)
            .frame(width: 520)
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
        .transition(.opacity)
    }

    // MARK: - Actions

    private func select(url: URL) {
        self.selectedFileURL = url
        self.selectedFileDuration = nil
        self.transcriptionService.reset()
        self.dropErrorMessage = nil
        self.fileHistoryStore.selectedEntryID = nil
        self.loadDuration(of: url)
    }

    private func clearSelection() {
        self.selectedFileURL = nil
        self.selectedFileDuration = nil
        self.transcriptionService.reset()
    }

    private func presentExport(for result: TranscriptionResult) {
        self.exportResult = result
        self.exportFileName = Self.fileName(base: result.fileName, format: self.exportFormat)
        self.showingExportSheet = true
    }

    private func prepareModel() {
        self.isPreparingModel = true
        Task {
            do {
                try await self.asrService.ensureAsrReady()
            } catch {
                DebugLogger.shared.error(
                    "Model preparation failed: \(error.localizedDescription)",
                    source: "MeetingTranscriptionView"
                )
            }
            await self.asrService.checkIfModelsExistAsync()
            await MainActor.run { self.isPreparingModel = false }
        }
    }

    private func loadDuration(of url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { return }
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return }
            await MainActor.run {
                guard self.selectedFileURL == url else { return }
                self.selectedFileDuration = seconds
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url = url else { return }
            let ext = url.pathExtension.lowercased()
            guard Self.supportedFileExtensions.contains(ext) else {
                DispatchQueue.main.async {
                    self.dropErrorMessage = Self.dropErrorCopy
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.dropErrorMessage = nil
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.select(url: url)
            }
        }
        return true
    }

    private func transcribeFile() async {
        guard let fileURL = selectedFileURL else { return }

        do {
            _ = try await self.transcriptionService.transcribeFile(fileURL)
        } catch {
            DebugLogger.shared.error("Transcription error: \(error)", source: "MeetingTranscriptionView")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation(.easeOut(duration: 0.18)) {
            self.showingCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.18)) {
                self.showingCopyConfirmation = false
            }
        }
    }

    // MARK: - Formatting

    /// "M4A · 42.8 MB · 48:12" — extension, on-disk size, and the real asset
    /// duration once AVFoundation has read it.
    private func fileMetaLine(fileURL: URL) -> String {
        var parts: [String] = []

        let ext = fileURL.pathExtension.uppercased()
        if !ext.isEmpty { parts.append(ext) }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fileSize = attributes[.size] as? Int64
        {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            parts.append(formatter.string(fromByteCount: fileSize))
        } else {
            parts.append("Unknown size")
        }

        if let duration = self.selectedFileDuration {
            parts.append(Self.clockString(duration))
        }

        return parts.joined(separator: " · ")
    }

    private static func clockString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func wordCountString(_ text: String) -> String {
        let count = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(number) words"
    }

    /// The service publishes "<what failed>: <why>". The board shows those as a
    /// Chillax title and a Karma sentence, so split on the first colon.
    private static func split(error: String) -> (title: String, detail: String?) {
        guard let range = error.range(of: ": ") else { return (error, nil) }
        return (
            String(error[error.startIndex ..< range.lowerBound]),
            String(error[range.upperBound...])
        )
    }

    private static func fileName(base: String, format: ExportFormat) -> String {
        let stem = (base as NSString).deletingPathExtension
        let cleaned = stem.isEmpty ? "transcript" : stem
        return "\(cleaned).\(format.fileExtension)"
    }
}

// MARK: - Drop delegate

/// `onDrop(of:isTargeted:)` cannot tell you WHICH file is hovering; the board's
/// drag state names it, so this delegate reads `suggestedName` on entry.
private struct MeetingDropDelegate: DropDelegate {
    let isEnabled: Bool
    let onTargetChange: (Bool, String?) -> Void
    let onPerform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        self.isEnabled && info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard self.isEnabled else { return }
        let name = info.itemProviders(for: [UTType.fileURL]).first?.suggestedName
        self.onTargetChange(true, name)
    }

    func dropExited(info _: DropInfo) {
        self.onTargetChange(false, nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        self.onTargetChange(false, nil)
        guard self.isEnabled else { return false }
        return self.onPerform(info.itemProviders(for: [UTType.fileURL]))
    }
}

// MARK: - Pill button

/// The one pill button the Library/App boards use, in five tones. Height and
/// label size are passed in because the boards draw it at 26 / 28 / 30 / 34 / 38.
/// Shared by Meeting transcription, Changelog, Feedback and Analytics privacy.
struct LibraryPagePill: View {
    enum Tone {
        case brand
        case outline
        case ghost
        case quiet
        case danger
    }

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let title: String
    let systemImage: String?
    let tone: Tone
    let height: CGFloat
    let labelSize: CGFloat
    /// Fixed pill width, when the board pins one (the dialog buttons).
    let width: CGFloat?
    /// Stretch to the container, when the board does (the "OK" dialog button).
    let expands: Bool
    let action: () -> Void

    /// Spelled out because the synthesized memberwise init would be private
    /// (the state and environment properties are), and the other Library/App
    /// pages need it.
    init(
        title: String,
        systemImage: String? = nil,
        tone: Tone = .outline,
        height: CGFloat = 34,
        labelSize: CGFloat = 13,
        width: CGFloat? = nil,
        expands: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.height = height
        self.labelSize = labelSize
        self.width = width
        self.expands = expands
        self.action = action
    }

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: self.labelSize - 2, weight: .medium))
                }
                Text(self.title)
                    .basicsButtonLabel(self.labelSize)
            }
            .foregroundStyle(self.foreground)
            .padding(.horizontal, self.horizontalPadding)
            .frame(maxWidth: self.expands ? .infinity : nil)
            .frame(width: self.width, height: self.height)
            .background(
                Capsule()
                    .fill(self.background)
                    .overlay(Capsule().stroke(self.border, lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(self.isEnabled ? 1 : 0.6)
        .onHover { self.isHovered = $0 && self.isEnabled }
    }

    private var horizontalPadding: CGFloat {
        switch self.height {
        case ..<28: return 12
        case ..<32: return 14
        case ..<36: return 16
        default: return 20
        }
    }

    private var foreground: Color {
        switch self.tone {
        case .brand: return .white
        case .outline: return self.theme.palette.primaryText
        case .ghost: return self.theme.palette.secondaryText
        case .quiet: return self.theme.palette.tertiaryText
        case .danger: return BasicsTokens.Semantic.danger
        }
    }

    private var background: Color {
        switch self.tone {
        case .brand:
            return self.isHovered ? BasicsTokens.Semantic.brandHover : self.theme.palette.accent
        case .outline, .danger:
            return self.isHovered ? self.theme.palette.sidebarBackground : self.theme.palette.cardBackground
        case .ghost:
            return self.isHovered ? self.theme.palette.sidebarBackground : self.theme.palette.windowBackground
        case .quiet:
            return self.theme.palette.sidebarBackground
        }
    }

    private var border: Color {
        switch self.tone {
        case .brand: return .clear
        case .outline: return BasicsBorder.strong(self.theme, self.colorScheme)
        case .ghost, .quiet: return self.theme.palette.cardBorder
        case .danger: return BasicsTokens.Semantic.danger.opacity(0.30)
        }
    }
}

// MARK: - Document for Export

struct TranscriptionDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .json]
    }

    let result: TranscriptionResult
    let format: MeetingTranscriptionView.ExportFormat
    let service: MeetingTranscriptionService

    init(
        result: TranscriptionResult,
        format: MeetingTranscriptionView.ExportFormat,
        service: MeetingTranscriptionService
    ) {
        self.result = result
        self.format = format
        self.service = service
    }

    init(configuration _: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.\(self.format.fileExtension)")

        switch self.format {
        case .text:
            try self.service.exportToText(self.result, to: tempURL)
        case .json:
            try self.service.exportToJSON(self.result, to: tempURL)
        }

        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

#Preview {
    MeetingTranscriptionView(asrService: ASRService())
        .frame(width: 1096, height: 900)
}
