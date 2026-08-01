import AppKit
import SwiftUI

/// Boards `14 — Tasks` and `14b — Tasks · states`.
///
/// The page owns three real things and invents none of them:
///
/// 1. the task shortcut — `SettingsStore.taskHotkeyShortcut` /
///    `taskShortcutEnabled`, captured through the shell's own
///    `ShortcutRecordingTarget.task` monitor (keyboard chords only, and
///    assigning one auto-enables it, which is why the switch is disabled
///    until a chord exists);
/// 2. the interpreter — a live `ConduitTaskClient.isGatewayUp()` health probe,
///    so the row says which of the two documented paths the next command will
///    actually take (Codex via Conduit, or the offline word-matcher);
/// 3. the list — `TasksStore.shared`, the same file the notch HUD renders.
///    Done / Start / Remove go through `TasksStore.apply(_:)`, the one
///    mutation entry point, so the invariants (single current task, atomic
///    write to `tasks.json`) hold exactly as they do for a spoken command.
struct TasksSettingsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var tasksStore = TasksStore.shared

    @Binding var shortcut: HotkeyShortcut?
    @Binding var shortcutEnabled: Bool
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?

    @State private var gatewayUp: Bool?
    @State private var isProbingGateway = false

    /// Spelled out because the synthesized memberwise initialiser would inherit
    /// the private access level of the environment and state properties above.
    init(
        shortcut: Binding<HotkeyShortcut?>,
        shortcutEnabled: Binding<Bool>,
        activeShortcutRecordingTarget: Binding<ShortcutRecordingTarget?>,
        shortcutRecordingMessage: Binding<String?>
    ) {
        self._shortcut = shortcut
        self._shortcutEnabled = shortcutEnabled
        self._activeShortcutRecordingTarget = activeShortcutRecordingTarget
        self._shortcutRecordingMessage = shortcutRecordingMessage
    }

    private var isCapturing: Bool {
        self.activeShortcutRecordingTarget == .task
    }

    private var isRecordingAnything: Bool {
        self.activeShortcutRecordingTarget != nil
    }

    private var heroState: ModeShortcutHeroState {
        if self.isCapturing {
            if let message = self.shortcutRecordingMessage, !message.isEmpty {
                return .conflict(message)
            }
            return .listening
        }
        guard let shortcut = self.shortcut else { return .notSet }
        return .set(shortcut, enabled: self.shortcutEnabled)
    }

    private var heroEyebrow: String {
        switch self.heroState {
        case .notSet: return "Task shortcut · not set"
        case .listening: return "Task shortcut · listening"
        case .conflict: return "Task shortcut · conflict"
        case let .set(_, enabled):
            return enabled ? "Task shortcut · hold to talk" : "Task shortcut · switched off"
        }
    }

    private var heroHelper: String {
        switch self.heroState {
        case .notSet:
            return "Pick a chord first — the switch cannot come on without one."
        case .listening:
            return "Escape cancels. A modifier-only chord commits when you let it go."
        case let .conflict(message):
            return message
        case let .set(_, enabled):
            return enabled
                ? "Hold, speak, release. Nothing gets typed — the words are read as task commands."
                : "The chord is kept. Nothing listens for it until this comes back on."
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                ModePageHeader(
                    eyebrow: "Modes",
                    title: "Tasks",
                    lede: "Hold the key and say what you are doing. The list lives in the notch above your screen — this page only sets the shortcut and shows you what is in it."
                )

                self.shortcutHero
                self.commandsSection
                self.interpreterSection
                self.listSection
                self.storageFootnote
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.contentBackground)
        .task {
            await self.probeGateway()
        }
    }

    // MARK: - Shortcut hero

    private var shortcutHero: some View {
        ModeShortcutHero(
            eyebrow: self.heroEyebrow,
            glyph: self.heroState.glyph,
            value: self.heroState.value,
            helper: self.heroHelper,
            tone: self.heroState.tone
        ) {
            HStack(spacing: 14) {
                if self.shortcut != nil, !self.isCapturing {
                    Button("Remove") { self.removeShortcut() }
                        .buttonStyle(.plain)
                        .basicsButtonLabel(13)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .disabled(self.isRecordingAnything)
                }

                LibraryPagePill(
                    title: self.captureButtonTitle,
                    tone: .outline,
                    height: 36,
                    labelSize: 14
                ) {
                    self.toggleCapture()
                }
                .disabled(!self.isCapturing && self.isRecordingAnything)

                ModeToggle(isOn: self.enabledBinding, label: "Task shortcut")
                    .disabled(self.shortcut == nil || self.isRecordingAnything)
            }
        }
    }

    // MARK: - What you can say

    /// The five `TaskOp.Kind` cases the interpreter is allowed to return; the
    /// raw values come straight off the enum so this table cannot drift from
    /// the wire contract.
    private struct SpokenCommand: Identifiable {
        let kind: TaskOp.Kind
        let example: String
        let effect: String
        var id: String { self.kind.rawValue }
    }

    private static let spokenCommands: [SpokenCommand] = [
        SpokenCommand(
            kind: .start,
            example: "“Start the rebase branch”",
            effect: "Makes it the task in progress. If that title is new it gets created first; whatever was current drops back to up next."
        ),
        SpokenCommand(
            kind: .done,
            example: "“Done”",
            effect: "Completes whatever is in progress. “Finished”, “complete” and “I'm done” do the same thing."
        ),
        SpokenCommand(
            kind: .add,
            example: "“Add ship the Paper boards”",
            effect: "Puts it at the end of up next without touching what you are on."
        ),
        SpokenCommand(
            kind: .update,
            example: "“Rename that to ship the boards”",
            effect: "Retitles a task that already exists. Matched by name, so near-enough wording finds it."
        ),
        SpokenCommand(
            kind: .remove,
            example: "“Drop the changelog task”",
            effect: "Takes it off the list. Anything it cannot place changes nothing and tells you why in a banner."
        ),
    ]

    private var commandsSection: some View {
        ModeSection(title: "What you can say", chip: "Five commands") {
            VStack(spacing: 0) {
                ForEach(Array(Self.spokenCommands.enumerated()), id: \.element.id) { index, command in
                    HStack(alignment: .center, spacing: 24) {
                        Text(command.example)
                            .basicsProse(15)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 300, alignment: .leading)

                        Text(command.effect)
                            .basicsProse(14)
                            .lineSpacing(14 * 0.6)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(command.kind.rawValue)
                            .basicsMono(12)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                    .overlay(alignment: .top) { ModeHairline() }
                    .overlay(alignment: .bottom) {
                        if index == Self.spokenCommands.count - 1 { ModeHairline() }
                    }
                }
            }
        }
    }

    // MARK: - Interpreter

    private var interpreterSection: some View {
        ModeSection(title: "Interpreter") {
            VStack(spacing: 0) {
                ModeSettingRow(
                    title: "Reading your words",
                    helper: self.interpreterHelper,
                    chip: self.interpreterChip
                ) {
                    HStack(spacing: 12) {
                        LibraryPagePill(
                            title: self.isProbingGateway ? "Checking…" : "Check",
                            tone: .ghost,
                            height: 28,
                            labelSize: 12
                        ) {
                            Task { await self.probeGateway() }
                        }
                        .disabled(self.isProbingGateway)

                        ModeValueChip(
                            text: self.gatewayUp == true ? "127.0.0.1:8787" : "gatewayOffline",
                            isMuted: self.gatewayUp != true
                        )
                    }
                }
                .overlay(alignment: .bottom) { ModeHairline() }
            }
        }
    }

    private var interpreterChip: ModeStatusChip.Model {
        switch self.gatewayUp {
        case .some(true): return .init(text: "Connected", tone: .brand)
        case .some(false): return .init(text: "Offline · fallback", tone: .warning)
        case nil: return .init(text: "Checking", tone: .muted)
        }
    }

    private var interpreterHelper: String {
        switch self.gatewayUp {
        case .some(true):
            return "Your own Codex subscription turns the sentence into task changes. Nothing is sent to a paid API."
        case .some(false):
            return "Conduit is not running, so a plain word-matcher takes over. It only understands “start …”, “add …” and “done”."
        case nil:
            return "Checking whether the local Conduit gateway is up."
        }
    }

    private func probeGateway() async {
        self.isProbingGateway = true
        let isUp = await ConduitTaskClient.shared.isGatewayUp()
        self.gatewayUp = isUp
        self.isProbingGateway = false
    }

    // MARK: - The list

    private var doneToday: [FluidTask] {
        let calendar = Calendar.current
        return self.tasksStore.tasks.filter { task in
            guard task.status == .done, let completedAt = task.completedAt else { return false }
            return calendar.isDateInToday(completedAt)
        }
    }

    /// Current task first, then up next in list order — the same order the
    /// notch HUD walks.
    private var liveTasks: [FluidTask] {
        var ordered: [FluidTask] = []
        if let current = self.tasksStore.currentTask { ordered.append(current) }
        ordered.append(contentsOf: self.tasksStore.upcomingTasks)
        return ordered
    }

    private var listSummary: String {
        let upNext = self.tasksStore.upcomingTasks.count
        let done = self.doneToday.count
        return "\(upNext) up next · \(done) done today"
    }

    private var listSection: some View {
        ModeSection(title: "The list", trailingMono: self.listSummary) {
            if self.liveTasks.isEmpty, self.doneToday.isEmpty {
                self.emptyList
            } else {
                VStack(spacing: 0) {
                    ForEach(self.liveTasks) { task in
                        self.taskRow(task)
                    }
                    ForEach(self.doneToday) { task in
                        self.doneRow(task)
                    }
                }
                .overlay(alignment: .bottom) { ModeHairline() }
            }
        }
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            Text("Nothing on the list")
                .basicsLabel(16)
                .foregroundStyle(self.theme.palette.primaryText)
            Text(self.emptyHint)
                .basicsProse(14)
                .foregroundStyle(self.theme.palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .overlay(alignment: .top) { ModeHairline() }
        .overlay(alignment: .bottom) { ModeHairline() }
    }

    private var emptyHint: String {
        guard let shortcut = self.shortcut, self.shortcutEnabled else {
            return "Set the shortcut above, then say “start writing the brief”. It shows up here and in the notch."
        }
        return "Hold \(shortcut.displayString) and say “start writing the brief”. It shows up here and in the notch."
    }

    private var startedTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    @ViewBuilder
    private func taskRow(_ task: FluidTask) -> some View {
        let isCurrent = task.status == .current

        HStack(alignment: .center, spacing: 16) {
            ZStack {
                if isCurrent {
                    Capsule()
                        .fill(self.theme.palette.accent)
                        .frame(width: 3, height: 30)
                } else {
                    Circle()
                        .strokeBorder(BasicsTokens.Surface.borderStrong, lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                if isCurrent {
                    Text(task.title)
                        .basicsLabel(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("In progress · started \(self.startedTimeFormatter.string(from: task.createdAt))")
                        .basicsMicroLabel(11)
                        .foregroundStyle(self.theme.palette.secondaryText)
                } else {
                    Text(task.title)
                        .basicsProse(15)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.taskRowActions(task, isCurrent: isCurrent)
        }
        .padding(.vertical, isCurrent ? 14 : 11)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { ModeHairline() }
    }

    @ViewBuilder
    private func taskRowActions(_ task: FluidTask, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            if isCurrent {
                LibraryPagePill(
                    title: "Done",
                    systemImage: "checkmark",
                    tone: .brand,
                    height: 28,
                    labelSize: 13
                ) {
                    self.apply(.init(op: .done, id: task.id.uuidString))
                }
            } else {
                Button("Start") {
                    self.apply(.init(op: .start, id: task.id.uuidString, title: task.title))
                }
                .buttonStyle(.plain)
                .basicsButtonLabel(13)
                .foregroundStyle(self.theme.palette.primaryText)

                Button("Remove") {
                    self.apply(.init(op: .remove, id: task.id.uuidString))
                }
                .buttonStyle(.plain)
                .basicsButtonLabel(13)
                .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .frame(width: 104, alignment: .trailing)
    }

    private func doneRow(_ task: FluidTask) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 20)

            Text(task.title)
                .strikethrough(true, color: self.theme.palette.tertiaryText)
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.completedAt.map { self.startedTimeFormatter.string(from: $0) } ?? "")
                .basicsMono(12)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { ModeHairline() }
    }

    private func apply(_ op: TaskOp) {
        let result = self.tasksStore.apply([op])
        DebugLogger.shared.info(
            "Tasks page applied op=\(op.op.rawValue) applied=\(result.appliedCount) summary=\(result.summaryLine)",
            source: "TasksSettingsView"
        )
    }

    // MARK: - Storage

    private var tasksFileDisplayPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return "tasks.json" }
        let url = base.appendingPathComponent("FluidVoice", isDirectory: true)
            .appendingPathComponent("tasks.json")
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var storageFootnote: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kept on this Mac")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text("One file, rewritten whenever a command lands. Finished tasks stay in the file but drop out of the notch and out of what the interpreter is shown.")
                    .basicsProse(14)
                    .lineSpacing(14 * 0.6)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LibraryPagePill(
                title: "Reveal",
                systemImage: "folder",
                tone: .ghost,
                height: 28,
                labelSize: 12
            ) {
                self.revealTasksFile()
            }

            ModeValueChip(text: self.tasksFileDisplayPath)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { ModeHairline() }
    }

    private func revealTasksFile() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let url = base.appendingPathComponent("FluidVoice", isDirectory: true)
            .appendingPathComponent("tasks.json")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    // MARK: - Shortcut actions

    private var captureButtonTitle: String {
        if self.isCapturing { return "Cancel" }
        return self.shortcut == nil ? "Set shortcut" : "Change"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.shortcutEnabled && self.shortcut != nil },
            set: { newValue in
                guard self.shortcut != nil else { return }
                self.shortcutEnabled = newValue
            }
        )
    }

    private func toggleCapture() {
        if self.isCapturing {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = nil
        } else {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = .task
        }
    }

    private func removeShortcut() {
        if self.isCapturing {
            self.shortcutRecordingMessage = nil
            self.activeShortcutRecordingTarget = nil
        }
        self.shortcut = nil
        self.shortcutEnabled = false
    }
}
