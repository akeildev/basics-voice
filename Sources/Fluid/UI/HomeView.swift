import AppKit
import AVFoundation
import Combine
import SwiftUI

// MARK: - Audio preview

/// Plays one saved dictation clip at a time for the Recent list's play button.
/// Kept here because Home is the only screen with an inline play affordance;
/// `DictationAudioHistoryStore` owns the files, this owns the transport.
@MainActor
final class HomeAudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingEntryID: UUID?

    private var player: AVAudioPlayer?

    func toggle(entry: TranscriptionHistoryEntry) {
        if self.playingEntryID == entry.id {
            self.stop()
            return
        }
        guard let url = DictationAudioHistoryStore.shared.audioFileURL(for: entry) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            self.playingEntryID = entry.id
        } catch {
            DebugLogger.shared.error(
                "Could not play saved dictation audio: \(error.localizedDescription)",
                source: "HomeView"
            )
            self.stop()
        }
    }

    func stop() {
        self.player?.stop()
        self.player = nil
        self.playingEntryID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.stop() }
    }
}

// MARK: - Home

/// Board `01 — Home` (+ `· setup pending`, `· playground`, `· guides`).
///
/// The dashboard that replaced "Getting Started". Nothing on this page is
/// decorative: the headline reads the real primary dictation chord and the real
/// frontmost app, the stat strip is computed by `TranscriptionHistoryStore`,
/// the setup rail uses the same five conditions the onboarding gate uses, and
/// the Recent list is the actual history with working copy / play buttons.
struct HomeView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @StateObject private var audioPreview = HomeAudioPreviewPlayer()

    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var playgroundUsed: Bool
    var isTranscriptionFocused: FocusState<Bool>.Binding

    let accessibilityEnabled: Bool
    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void
    let openAccessibilitySettings: () -> Void

    @State private var frontmostAppName: String?
    @State private var searchText = ""
    @State private var copiedEntryID: UUID?
    @State private var isCommandGuideExpanded = false
    @State private var isRewriteGuideExpanded = false

    private static let playgroundAnchor = "home-playground"

    /// Spelled out because the synthesized memberwise initialiser would inherit
    /// the private access level of the environment and state properties above.
    init(
        selectedSidebarItem: Binding<SidebarItem?>,
        playgroundUsed: Binding<Bool>,
        isTranscriptionFocused: FocusState<Bool>.Binding,
        accessibilityEnabled: Bool,
        stopAndProcessTranscription: @escaping () async -> Void,
        startRecording: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self._selectedSidebarItem = selectedSidebarItem
        self._playgroundUsed = playgroundUsed
        self.isTranscriptionFocused = isTranscriptionFocused
        self.accessibilityEnabled = accessibilityEnabled
        self.stopAndProcessTranscription = stopAndProcessTranscription
        self.startRecording = startRecording
        self.openAccessibilitySettings = openAccessibilitySettings
    }

    private var asr: ASRService { self.appServices.asr }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    self.dictateHeadline
                    self.statStrip
                    self.quickSetup(proxy: proxy)
                    self.recentSection
                    self.playgroundSection.id(Self.playgroundAnchor)
                    self.guidesSection
                }
                .padding(.horizontal, 40)
                .padding(.top, 34)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(self.theme.palette.contentBackground)
        .onAppear { self.updateFrontmostApp() }
        .onReceive(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            self.updateFrontmostApp()
        }
        .onDisappear { self.audioPreview.stop() }
    }

    // MARK: - Headline

    private var primaryShortcutDisplay: String {
        self.settings.primaryDictationShortcutDisplayString
    }

    private var dictateHeadline: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Hold")
                .basicsLabel(26)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.primaryShortcutDisplay)
                .basicsMono(16, weight: .medium)
                .foregroundStyle(self.theme.palette.accent)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BasicsTokens.Semantic.brandSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(self.theme.palette.accent.opacity(0.22), lineWidth: 1)
                        )
                )

            if let appName = self.frontmostAppName {
                Text("to dictate in")
                    .basicsLabel(26)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text(appName)
                    .basicsLabel(26)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
            } else {
                Text("to dictate anywhere")
                    .basicsLabel(26)
                    .foregroundStyle(self.theme.palette.primaryText)
            }

            Spacer(minLength: 12)
        }
    }

    /// The app the next dictation would type into — never this app, so the
    /// headline keeps naming the real target while the window is in front.
    private func updateFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        guard front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard let name = front.localizedName, !name.isEmpty else { return }
        self.frontmostAppName = name
    }

    // MARK: - Stat strip

    private struct StatValue {
        /// Alternating numeral / unit parts, e.g. ["19", "hrs", "10", "min"].
        let parts: [String]
        let isBrand: Bool
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var timeSavedValue: StatValue {
        let minutes = self.historyStore.timeSavedMinutes(typingWPM: self.settings.userTypingWPM)
        if minutes < 1 {
            return StatValue(parts: ["< 1", "min"], isBrand: false)
        }
        let whole = Int(minutes)
        if whole < 60 {
            return StatValue(parts: ["\(whole)", "min"], isBrand: false)
        }
        let hours = whole / 60
        let remainder = whole % 60
        if remainder == 0 {
            return StatValue(parts: ["\(hours)", "hrs"], isBrand: false)
        }
        return StatValue(parts: ["\(hours)", "hrs", "\(remainder)", "min"], isBrand: false)
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            self.statCell(
                label: "Dictated words",
                value: StatValue(parts: [Self.grouped(self.historyStore.totalWords), "words"], isBrand: false),
                showsDivider: false
            )
            self.statCell(label: "Time saved", value: self.timeSavedValue, showsDivider: true)
            self.statCell(
                label: "Day streak",
                value: StatValue(parts: ["\(self.historyStore.currentStreak)", "days"], isBrand: self.historyStore.currentStreak > 0),
                showsDivider: true
            )
            self.statCell(
                label: "AI enhanced",
                value: StatValue(parts: ["\(self.historyStore.aiEnhancementRate)", "%"], isBrand: false),
                showsDivider: true
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(self.theme.palette.separator, lineWidth: 1)
                )
        )
    }

    private func statCell(label: String, value: StatValue, showsDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ForEach(Array(value.parts.enumerated()), id: \.offset) { index, part in
                    if index.isMultiple(of: 2) {
                        // A stat numeral must never wrap — at the window's
                        // compact width "12,765" was breaking into "12,76 / 5".
                        // Shrink to fit instead of splitting the number.
                        Text(part)
                            .basicsLabel(34)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(value.isBrand ? self.theme.palette.accent : self.theme.palette.primaryText)
                    } else {
                        Text(part)
                            .basicsLabel(14)
                            .lineLimit(1)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsDivider {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Quick setup

    private enum SetupState {
        case done
        case inProgress
        case pending
    }

    private struct SetupStep: Identifiable {
        let index: Int
        let title: String
        let helper: String?
        let state: SetupState
        let actionTitle: String?
        let action: (() -> Void)?
        /// 0...1 while the voice model is downloading; nil otherwise.
        let progress: Double?
        var id: Int { self.index }
    }

    private var isVoiceModelReady: Bool {
        self.asr.isAsrReady || self.asr.modelsExistOnDisk
    }

    private var isVoiceModelPreparing: Bool {
        self.asr.isDownloadingModel || self.asr.isLoadingModel || self.asr.downloadingModelId != nil
    }

    private var isAIEnhancementReady: Bool {
        DictationAIPostProcessingGate.isProviderConfigured()
    }

    private func setupSteps(proxy: ScrollViewProxy) -> [SetupStep] {
        [
            SetupStep(
                index: 1,
                title: self.isVoiceModelReady ? "Voice model ready" : "Download voice model",
                helper: self.isVoiceModelReady
                    ? (self.asr.isAsrReady ? nil : "Downloaded. It loads into memory on the first dictation.")
                    : "\(self.settings.selectedSpeechModel.displayName) — \(self.settings.selectedSpeechModel.downloadSize), \(self.asr.modelStatusMessage.lowercased()). It never leaves this Mac.",
                state: self.isVoiceModelReady ? .done : (self.isVoiceModelPreparing ? .inProgress : .pending),
                actionTitle: self.isVoiceModelReady ? nil : "Voice engine",
                action: self.isVoiceModelReady ? nil : { self.selectedSidebarItem = .voiceEngine },
                progress: self.isVoiceModelPreparing ? self.asr.downloadProgress : nil
            ),
            SetupStep(
                index: 2,
                title: self.asr.micStatus == .authorized ? "Microphone permission granted" : "Grant microphone permission",
                helper: self.asr.micStatus == .authorized
                    ? nil
                    : (self.asr.micStatus == .notDetermined
                        ? "macOS asks once. If you have already said no, this button opens System Settings instead."
                        : "macOS has this switched off. Turn it back on in System Settings."),
                state: self.asr.micStatus == .authorized ? .done : .pending,
                actionTitle: self.asr.micStatus == .authorized
                    ? nil
                    : (self.asr.micStatus == .notDetermined ? "Grant access" : "Open Settings"),
                action: self.asr.micStatus == .authorized ? nil : {
                    if self.asr.micStatus == .notDetermined {
                        self.asr.requestMicAccess()
                    } else {
                        self.asr.openSystemSettingsForMic()
                    }
                },
                progress: nil
            ),
            SetupStep(
                index: 3,
                title: self.accessibilityEnabled ? "Accessibility access enabled" : "Enable accessibility access",
                helper: self.accessibilityEnabled
                    ? nil
                    : "Drag \(Bundle.main.fluidAppDisplayName) into the Accessibility list. A guide window follows you into System Settings.",
                state: self.accessibilityEnabled ? .done : .pending,
                actionTitle: self.accessibilityEnabled ? nil : "Open Settings",
                action: self.accessibilityEnabled ? nil : { self.openAccessibilitySettings() },
                progress: nil
            ),
            SetupStep(
                index: 4,
                title: self.isAIEnhancementReady ? "AI enhancements configured" : "Set up AI enhancements",
                helper: self.isAIEnhancementReady
                    ? nil
                    : "Optional. Add a provider key so dictation gets cleaned up before it lands.",
                state: self.isAIEnhancementReady ? .done : .pending,
                actionTitle: "Configure AI",
                action: { self.selectedSidebarItem = .aiEnhancements },
                progress: nil
            ),
            SetupStep(
                index: 5,
                title: self.playgroundUsed ? "Setup tested" : "Test your setup",
                helper: self.playgroundUsed
                    ? nil
                    : "Say one sentence in the playground below and watch it land.",
                state: self.playgroundUsed ? .done : .pending,
                actionTitle: self.playgroundUsed ? nil : "Go to playground",
                action: self.playgroundUsed ? nil : {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(Self.playgroundAnchor, anchor: .top)
                    }
                    self.isTranscriptionFocused.wrappedValue = true
                },
                progress: nil
            ),
        ]
    }

    /// The AI step is optional, so it never blocks; it still counts toward the
    /// five so the rail matches what the checklist shows.
    private func remainingCount(_ steps: [SetupStep]) -> Int {
        steps.filter { $0.state != .done }.count
    }

    private func introSentence(remaining: Int, doneCount: Int) -> String {
        switch remaining {
        case 0:
            return "All five done. Hold your key anywhere and talk."
        case 5:
            return "Nothing works yet. Five steps, about two minutes, mostly waiting on a download."
        case 1, 2:
            return "\(Self.spelled(doneCount)) of five done. AI enhancement is optional; the last step just proves the whole thing works."
        default:
            return "\(Self.spelled(doneCount)) of five done. Keep going — dictation starts working as soon as the first three land."
        }
    }

    private static func spelled(_ value: Int) -> String {
        switch value {
        case 0: return "None"
        case 1: return "One"
        case 2: return "Two"
        case 3: return "Three"
        case 4: return "Four"
        default: return "Five"
        }
    }

    private func quickSetup(proxy: ScrollViewProxy) -> some View {
        let steps = self.setupSteps(proxy: proxy)
        let remaining = self.remainingCount(steps)
        let doneCount = steps.count - remaining

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Quick setup")
                    .basicsLabel(19)
                    .foregroundStyle(self.theme.palette.primaryText)
                Spacer(minLength: 12)
                Button("Run setup again") {
                    self.settings.resetOnboardingProgress()
                    self.playgroundUsed = false
                }
                .buttonStyle(.plain)
                .basicsButtonLabel(13)
                .foregroundStyle(self.theme.palette.accent)
            }

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(remaining == 0 ? "All done" : "\(remaining) remaining")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)

                    Text(self.introSentence(remaining: remaining, doneCount: doneCount))
                        .basicsProse(15)
                        .lineSpacing(15 * 0.6)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(self.theme.palette.separator)
                            Capsule()
                                .fill(self.theme.palette.accent)
                                .frame(width: geometry.size.width * (CGFloat(doneCount) / CGFloat(max(steps.count, 1))))
                        }
                    }
                    .frame(height: 4)
                }
                .frame(width: 236, alignment: .leading)
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(self.theme.palette.separator)
                        .frame(width: 1)
                }

                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        self.setupRow(step, isLast: step.index == steps.count)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(self.theme.palette.separator, lineWidth: 1)
                    )
            )
        }
    }

    private func setupRow(_ step: SetupStep, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", step.index))
                .basicsMono(12)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: 22, alignment: .leading)

            self.setupMarker(step.state)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)
                if let helper = step.helper {
                    Text(helper)
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if let progress = step.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(self.theme.palette.accent)
                        .frame(width: 56)
                    Text("\(Int(min(max(progress, 0), 1) * 100))%")
                        .basicsMono(11)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }

                if step.state == .done, step.actionTitle == nil {
                    Text("Done")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                } else if let title = step.actionTitle, let action = step.action {
                    Button(action: action) {
                        HStack(spacing: 5) {
                            Text(title)
                                .basicsLabel(12)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(self.theme.palette.accent)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(Capsule().fill(BasicsTokens.Semantic.brandSoft))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { ModeHairline() }
        }
    }

    @ViewBuilder
    private func setupMarker(_ state: SetupState) -> some View {
        switch state {
        case .done:
            Circle()
                .fill(self.theme.palette.accent)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
        case .inProgress:
            Circle()
                .strokeBorder(self.theme.palette.accent, lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .fill(self.theme.palette.accent)
                        .frame(width: 8, height: 8)
                }
        case .pending:
            Circle()
                .strokeBorder(BasicsTokens.Surface.borderStrong, lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }

    // MARK: - Recent

    private static let recentLimit = 6

    private var recentEntries: [TranscriptionHistoryEntry] {
        let source = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? self.historyStore.entries
            : self.historyStore.search(query: self.searchText)
        return Array(source.prefix(Self.recentLimit))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Recent")
                    .basicsLabel(19)
                    .foregroundStyle(self.theme.palette.primaryText)
                Spacer(minLength: 12)
                self.recentSearchField
            }

            if self.recentEntries.isEmpty {
                self.recentEmptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(self.groupedRecentEntries, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.key)
                                .basicsMicroLabel(11)
                                .foregroundStyle(self.theme.palette.tertiaryText)
                            VStack(spacing: 0) {
                                ForEach(group.entries) { entry in
                                    self.recentRow(entry)
                                }
                            }
                        }
                    }

                    if self.historyStore.entries.count > Self.recentLimit {
                        Button("Open history") { self.selectedSidebarItem = .history }
                            .buttonStyle(.plain)
                            .basicsButtonLabel(13)
                            .foregroundStyle(self.theme.palette.accent)
                    }
                }
            }
        }
    }

    private var recentSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.theme.palette.tertiaryText)
            TextField(
                "Search \(Self.grouped(self.historyStore.entries.count)) transcriptions",
                text: self.$searchText
            )
            .textFieldStyle(.plain)
            .basicsLabel(13)
            .foregroundStyle(self.theme.palette.primaryText)
        }
        .padding(.horizontal, 13)
        .frame(width: 260, height: 34)
        .background(
            Capsule()
                .fill(self.theme.palette.cardBackground)
                .overlay(Capsule().stroke(self.theme.palette.separator, lineWidth: 1))
        )
    }

    private struct RecentGroup {
        let key: String
        let entries: [TranscriptionHistoryEntry]
    }

    private var groupedRecentEntries: [RecentGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [TranscriptionHistoryEntry]] = [:]

        for entry in self.recentEntries {
            let key: String
            if calendar.isDateInToday(entry.timestamp) {
                key = "Today"
            } else if calendar.isDateInYesterday(entry.timestamp) {
                key = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                key = formatter.string(from: entry.timestamp)
            }
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(entry)
        }

        return order.map { RecentGroup(key: $0, entries: buckets[$0] ?? []) }
    }

    private static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }

    private static func durationString(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds) / 1000
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func recentRow(_ entry: TranscriptionHistoryEntry) -> some View {
        let hasAudio = DictationAudioHistoryStore.shared.audioFileExists(for: entry)

        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.clockString(entry.timestamp))
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                if let audio = entry.audio {
                    Text(Self.durationString(audio.durationMilliseconds))
                        .basicsMono(11)
                        .foregroundStyle(self.theme.palette.accent)
                }
            }
            .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.clipboardText ?? "")
                    .basicsProse(15)
                    .lineSpacing(15 * 0.6)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if !entry.appName.isEmpty {
                        Text(entry.appName)
                            .basicsLabel(12)
                            .foregroundStyle(self.theme.palette.secondaryText)
                        Circle()
                            .fill(self.theme.palette.separator)
                            .frame(width: 3, height: 3)
                    }

                    if let failure = entry.aiProcessingError {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.theme.palette.warning)
                        Text("AI enhancement failed — typed the raw transcription")
                            .basicsProse(12)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .help(failure)
                    } else if let model = entry.processingModel {
                        Text(model)
                            .basicsMono(11)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    } else {
                        Text("no AI pass")
                            .basicsMono(11)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                self.iconButton(
                    systemName: self.copiedEntryID == entry.id ? "checkmark" : "doc.on.doc",
                    help: "Copy transcription"
                ) {
                    self.copy(entry)
                }

                if hasAudio {
                    self.iconButton(
                        systemName: self.audioPreview.playingEntryID == entry.id ? "stop.fill" : "play.fill",
                        help: "Play saved audio"
                    ) {
                        self.audioPreview.toggle(entry: entry)
                    }
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .overlay(alignment: .top) { ModeHairline() }
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(self.theme.palette.separator, lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func copy(_ entry: TranscriptionHistoryEntry) {
        guard let text = entry.clipboardText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        self.copiedEntryID = entry.id
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.copiedEntryID == entry.id { self.copiedEntryID = nil }
        }
    }

    private var recentEmptyState: some View {
        VStack(spacing: 8) {
            Text(self.searchText.isEmpty ? "Nothing dictated yet" : "No transcription matches that")
                .basicsLabel(16)
                .foregroundStyle(self.theme.palette.primaryText)
            Text(self.searchText.isEmpty
                ? "Finish the steps above, then hold your key anywhere and talk. Everything you dictate lands here."
                : "Try fewer words, or open History for the full list.")
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .overlay(alignment: .top) { ModeHairline() }
    }

    // MARK: - Playground

    private var isPlaygroundReady: Bool {
        self.asr.isAsrReady || self.asr.isRunning
    }

    private var showsWordBoost: Bool {
        self.settings.selectedSpeechModel == .parakeetTDT || self.settings.selectedSpeechModel == .parakeetTDTv2
    }

    private var playgroundSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home · step 05")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.accent)
                Text("Test playground")
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("Say one sentence here before you trust it anywhere else. Nothing typed from this box leaves the window.")
                    .basicsProse(15)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Click record, speak, and see your transcription")
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Spacer(minLength: 12)
                    self.playgroundStatus
                }

                self.playgroundEditor

                HStack(spacing: 12) {
                    LibraryPagePill(
                        title: self.asr.isRunning ? "Stop recording" : "Start recording",
                        systemImage: self.asr.isRunning ? "stop.fill" : "mic.fill",
                        tone: self.asr.isRunning ? .outline : .brand,
                        height: 34,
                        labelSize: 13
                    ) {
                        if self.asr.isRunning {
                            Task { await self.stopAndProcessTranscription() }
                        } else {
                            self.startRecording()
                            self.playgroundUsed = true
                            self.settings.playgroundUsed = true
                        }
                    }
                    .disabled(!self.isPlaygroundReady)

                    if !self.asr.finalText.isEmpty {
                        LibraryPagePill(title: "Copy text", tone: .outline, height: 34, labelSize: 13) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                        }

                        LibraryPagePill(title: "Clear & test again", tone: .ghost, height: 34, labelSize: 13) {
                            self.asr.finalText = ""
                        }
                    }

                    if !self.isPlaygroundReady {
                        Text("Disabled until the voice model finishes downloading.")
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(self.theme.palette.separator, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var playgroundStatus: some View {
        if self.asr.isRunning {
            HStack(spacing: 6) {
                Circle()
                    .fill(BasicsTokens.Semantic.danger)
                    .frame(width: 6, height: 6)
                Text("Recording…")
                    .basicsLabel(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        } else if !self.asr.finalText.isEmpty {
            Text("\(self.asr.finalText.count) characters")
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
        } else if self.showsWordBoost {
            Text(self.asr.wordBoostStatusText)
                .basicsLabel(11)
                .foregroundStyle(self.theme.palette.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 19)
                .background(Capsule().fill(BasicsTokens.Surface.muted))
        }
    }

    private var playgroundEditor: some View {
        TextEditor(text: Binding(
            get: { self.asr.finalText },
            set: { self.asr.finalText = $0 }
        ))
        .font(BasicsTokens.prose(15))
        .scrollContentBackground(.hidden)
        .focused(self.isTranscriptionFocused)
        .padding(10)
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BasicsTokens.Surface.muted.opacity(self.colorScheme == .dark ? 0.25 : 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            self.asr.isRunning ? self.theme.palette.accent : self.theme.palette.separator,
                            lineWidth: self.asr.isRunning ? 2 : 1
                        )
                )
        )
        .overlay {
            if self.asr.isRunning, self.asr.finalText.isEmpty {
                VStack(spacing: 4) {
                    Text("Listening… Speak now!")
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("Transcription will appear when you stop recording")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .allowsHitTesting(false)
            } else if self.asr.finalText.isEmpty {
                Text("Press record or your hotkey to begin")
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Guides

    private struct HowToStep {
        let index: String
        let title: String
        let body: String
    }

    private var howToSteps: [HowToStep] {
        [
            HowToStep(
                index: "01",
                title: "Start recording",
                body: "Hold your key — \(self.primaryShortcutDisplay) — or click the button in the playground."
            ),
            HowToStep(
                index: "02",
                title: "Speak clearly",
                body: "Talk normally. It works best somewhere quiet, but it forgives a café."
            ),
            HowToStep(
                index: "03",
                title: "It types for you",
                body: "The transcript is typed straight into whatever app is in front."
            ),
        ]
    }

    private var guidesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home · guides")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.accent)
                Text("How to use it")
                    .basicsLabel(22)
                    .foregroundStyle(self.theme.palette.primaryText)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(self.howToSteps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.index)
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        Text(step.title)
                            .basicsLabel(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                        Text(step.body)
                            .basicsProse(14)
                            .lineSpacing(14 * 0.6)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, index == 0 ? 0 : 26)
                    .padding(.trailing, 26)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(self.theme.palette.separator)
                                .frame(width: 1)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 22) {
                self.commandModeGuide
                self.rewriteModeGuide
            }
        }
    }

    private var commandModeGuide: some View {
        self.guideCard(
            title: "Command mode",
            badges: ["New", "Alpha"],
            isExpanded: self.$isCommandGuideExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Control your Mac by voice — run a terminal command, open an app, answer a quick question.")
                    .basicsProse(14)
                    .lineSpacing(14 * 0.6)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    self.chordChip(self.settings.commandModeHotkeyShortcut?.displayString)
                    Text(self.settings.commandModeHotkeyShortcut == nil
                        ? "is not set yet — assign it in Preferences."
                        : "to open, speak, then press again to send.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Examples")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach([
                        "“List files in my Downloads folder”",
                        "“Create a folder called Projects on Desktop”",
                        "“What's my IP address?”",
                        "“Open Safari”",
                    ], id: \.self) { example in
                        Text(example)
                            .basicsProse(14)
                            .foregroundStyle(self.theme.palette.primaryText)
                    }
                }

                ModeHairline()

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.theme.palette.warning)
                    Text("AI can make mistakes. Avoid destructive commands.")
                        .basicsProse(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    LibraryPagePill(title: "Open", tone: .brand, height: 28, labelSize: 12) {
                        self.selectedSidebarItem = .commandMode
                    }
                }
            }
        }
    }

    private var rewriteModeGuide: some View {
        self.guideCard(
            title: "Rewrite mode",
            badges: ["New"],
            isExpanded: self.$isRewriteGuideExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("An editing assistant. Write something fresh, or select text and say how to change it.")
                    .basicsProse(14)
                    .lineSpacing(14 * 0.6)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text("Create new text")
                        .basicsLabel(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    self.chordChip(self.settings.rewriteModeHotkeyShortcut.displayString)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("“Write an email asking for time off”")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("“Draft a thank you note”")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                }

                Text("Edit selected text")
                    .basicsLabel(14)
                    .foregroundStyle(self.theme.palette.primaryText)

                VStack(alignment: .leading, spacing: 5) {
                    Text("“Make this more formal”")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("“Fix grammar and spelling”")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("“Summarize this”")
                        .basicsProse(14)
                        .foregroundStyle(self.theme.palette.primaryText)
                }

                ModeHairline()

                HStack(spacing: 10) {
                    if self.isAIEnhancementReady {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.theme.palette.accent)
                        Text("A model provider is configured, so this is ready to use.")
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        Text("Needs a model provider in AI enhancements first.")
                            .basicsProse(13)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    LibraryPagePill(
                        title: self.isAIEnhancementReady ? "Open" : "Open AI enhancements",
                        tone: self.isAIEnhancementReady ? .brand : .outline,
                        height: 28,
                        labelSize: 12
                    ) {
                        self.selectedSidebarItem = self.isAIEnhancementReady ? .rewriteMode : .aiEnhancements
                    }
                }
            }
        }
    }

    private func chordChip(_ display: String?) -> some View {
        Text(display ?? "Not set")
            .basicsMono(12, weight: .medium)
            .foregroundStyle(display == nil ? self.theme.palette.tertiaryText : self.theme.palette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BasicsTokens.Surface.muted)
            )
    }

    private func guideCard<Content: View>(
        title: String,
        badges: [String],
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .basicsLabel(19)
                        .foregroundStyle(self.theme.palette.primaryText)
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .basicsLabel(11)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 19)
                            .background(Capsule().fill(BasicsTokens.Surface.muted))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(self.theme.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(self.theme.palette.separator, lineWidth: 1)
                )
        )
    }
}
