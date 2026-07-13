import Combine
import Foundation

// MARK: - Model

enum FluidTaskStatus: String, Codable {
    case current
    case upcoming
    case done
}

struct FluidTask: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    /// 1-2 word label for the collapsed notch wing (interpreter-provided).
    var shortTitle: String?
    var status: FluidTaskStatus
    var createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(), title: String, shortTitle: String? = nil, status: FluidTaskStatus = .upcoming) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.status = status
        self.createdAt = Date()
        self.completedAt = nil
    }

    /// Always-fits label for the collapsed pill: the interpreter's short title,
    /// else the first two significant words of the full title.
    var compactLabel: String {
        if let shortTitle, !shortTitle.isEmpty { return shortTitle }
        return Self.deriveShortLabel(from: self.title)
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "to", "on", "of", "for", "in", "at", "with", "my", "our", "and", "up",
    ]

    static func deriveShortLabel(from title: String) -> String {
        let words = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !self.stopwords.contains($0.lowercased()) }
        let picked = words.prefix(2)
        return picked.isEmpty ? title : picked.joined(separator: " ")
    }
}

// MARK: - Operations (the Conduit/voice contract)

/// One task mutation, as returned by the command interpreter (or the offline
/// fallback parser). Codable against the JSON contract:
/// `{"ops":[{"op":"start","title":"..."},{"op":"done"},{"op":"add","title":"..."},
///   {"op":"update","id":"<uuid>","title":"..."},{"op":"remove","id":"<uuid>"},
///   {"op":"none","reason":"..."}]}`
struct TaskOp: Codable, Equatable {
    enum Kind: String, Codable {
        case start, done, add, update, remove, none
    }

    var op: Kind
    var id: String?
    var title: String?
    /// 1-2 word display label supplied by the interpreter for start/add/update.
    var short: String?
    var reason: String?
}

struct TaskOpEnvelope: Codable {
    var ops: [TaskOp]
}

struct TaskOpResult {
    var appliedCount: Int
    var summaries: [String]
    var rejected: [String]

    var summaryLine: String {
        if self.appliedCount == 0 {
            return self.rejected.first ?? "No task changes"
        }
        return self.summaries.joined(separator: "; ")
    }
}

// MARK: - Store

/// File-backed task list — the single source of truth for the notch HUD.
///
/// Invariants (enforced in `apply`):
/// - at most ONE task has `.current` status; `start` demotes the previous
///   current task back to `.upcoming`.
/// - array order is display order for upcoming tasks.
///
/// Persistence: `~/Library/Application Support/FluidVoice/tasks.json`,
/// atomic write. Kept Foundation-only (no app singletons) so it can be
/// exercised by a standalone test harness.
@MainActor
final class TasksStore: ObservableObject {
    static let shared = TasksStore()

    @Published private(set) var tasks: [FluidTask] = []

    var currentTask: FluidTask? {
        self.tasks.first { $0.status == .current }
    }

    /// Upcoming tasks in display order.
    var upcomingTasks: [FluidTask] {
        self.tasks.filter { $0.status == .upcoming }
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.load()
    }

    // MARK: Apply operations

    @discardableResult
    func apply(_ ops: [TaskOp]) -> TaskOpResult {
        var applied = 0
        var summaries: [String] = []
        var rejected: [String] = []

        for op in ops {
            switch op.op {
            case .start:
                let target = self.resolveTask(id: op.id, title: op.title)
                if let target {
                    self.setCurrent(target.id)
                    if let short = op.short, !short.isEmpty,
                       let idx = self.tasks.firstIndex(where: { $0.id == target.id })
                    {
                        self.tasks[idx].shortTitle = short
                    }
                    applied += 1
                    summaries.append("Started “\(target.title)”")
                } else if let title = op.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Unknown title: create it and start it.
                    var task = FluidTask(title: title, shortTitle: op.short)
                    task.status = .upcoming
                    self.tasks.append(task)
                    self.setCurrent(task.id)
                    applied += 1
                    summaries.append("Started new “\(title)”")
                } else {
                    // Bare "start": promote the first upcoming task.
                    if let first = self.upcomingTasks.first {
                        self.setCurrent(first.id)
                        applied += 1
                        summaries.append("Started “\(first.title)”")
                    } else {
                        rejected.append("Nothing to start")
                    }
                }

            case .done:
                let target = self.resolveTask(id: op.id, title: op.title) ?? self.currentTask
                if let target, let idx = self.tasks.firstIndex(where: { $0.id == target.id }) {
                    self.tasks[idx].status = .done
                    self.tasks[idx].completedAt = Date()
                    applied += 1
                    summaries.append("Done: “\(target.title)”")
                } else {
                    rejected.append("No task to complete")
                }

            case .add:
                guard let title = op.title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                    rejected.append("Add without a title")
                    continue
                }
                self.tasks.append(FluidTask(title: title, shortTitle: op.short))
                applied += 1
                summaries.append("Added “\(title)”")

            case .update:
                guard let target = self.resolveTask(id: op.id, title: nil),
                      let idx = self.tasks.firstIndex(where: { $0.id == target.id }),
                      let title = op.title, !title.trimmingCharacters(in: .whitespaces).isEmpty
                else {
                    rejected.append("Update with unknown task or empty title")
                    continue
                }
                self.tasks[idx].title = title
                self.tasks[idx].shortTitle = op.short
                applied += 1
                summaries.append("Updated to “\(title)”")

            case .remove:
                guard let target = self.resolveTask(id: op.id, title: op.title),
                      let idx = self.tasks.firstIndex(where: { $0.id == target.id })
                else {
                    rejected.append("Remove with unknown task")
                    continue
                }
                let removed = self.tasks.remove(at: idx)
                applied += 1
                summaries.append("Removed “\(removed.title)”")

            case .none:
                rejected.append(op.reason ?? "Not a task command")
            }
        }

        if applied > 0 {
            self.save()
        }
        return TaskOpResult(appliedCount: applied, summaries: summaries, rejected: rejected)
    }

    /// Serialized snapshot handed to the command interpreter as context.
    func promptContextJSON() -> String {
        let items = self.tasks
            .filter { $0.status != .done }
            .map { ["id": $0.id.uuidString, "title": $0.title, "status": $0.status.rawValue] }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    // MARK: Invariant helpers

    /// Make exactly this task `.current`, demoting any existing current task.
    private func setCurrent(_ id: UUID) {
        for idx in self.tasks.indices {
            if self.tasks[idx].id == id {
                self.tasks[idx].status = .current
            } else if self.tasks[idx].status == .current {
                self.tasks[idx].status = .upcoming
            }
        }
    }

    /// Resolve by UUID first, then case-insensitive fuzzy title match
    /// (exact, prefix, then substring) against non-done tasks.
    private func resolveTask(id: String?, title: String?) -> FluidTask? {
        if let id, let uuid = UUID(uuidString: id) {
            if let match = self.tasks.first(where: { $0.id == uuid && $0.status != .done }) {
                return match
            }
        }
        guard let title, !title.isEmpty else { return nil }
        let needle = title.lowercased().trimmingCharacters(in: .whitespaces)
        let live = self.tasks.filter { $0.status != .done }
        return live.first { $0.title.lowercased() == needle }
            ?? live.first { $0.title.lowercased().hasPrefix(needle) }
            ?? live.first { $0.title.lowercased().contains(needle) }
    }

    // MARK: Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("FluidVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: self.fileURL) else { return }
        if let decoded = try? JSONDecoder.tasksDecoder.decode([FluidTask].self, from: data) {
            self.tasks = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.tasksEncoder.encode(self.tasks) else { return }
        // Atomic: write to a temp file, then replace.
        let tmp = self.fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(self.fileURL, withItemAt: tmp)
        } catch {
            // Last resort: direct write.
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }
}

extension JSONEncoder {
    static var tasksEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var tasksDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
