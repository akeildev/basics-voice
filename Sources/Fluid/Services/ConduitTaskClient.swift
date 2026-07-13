import Foundation

enum ConduitTaskClientError: Error, LocalizedError {
    case gatewayOffline
    case badResponse(String)
    case emptyResult
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .gatewayOffline:
            return "Task gateway offline (Conduit not running on 127.0.0.1:8787)."
        case let .badResponse(detail):
            return "Task gateway error: \(detail)"
        case .emptyResult:
            return "The task interpreter returned nothing."
        case let .invalidJSON(text):
            return "The task interpreter returned invalid JSON: \(text.prefix(120))"
        }
    }
}

/// Interprets a spoken task command via the local Conduit gateway
/// (the user's Codex subscription) and returns structured task operations.
///
/// Wire contract (verified live against conduit-serve):
/// - `GET /health` → `{"ok":true,"providers":[...]}` (2 s timeout gate)
/// - `POST /run` `{provider, sessionKey, prompt}` → SSE stream of
///   `event: message` frames; we keep the LAST `"kind":"assistant_text"`
///   frame's `text`, finish on `"kind":"final_result"` / `event: done`,
///   and fail on kinds containing "error".
@MainActor
final class ConduitTaskClient {
    static let shared = ConduitTaskClient()

    private static let baseURL = URL(string: "http://127.0.0.1:8787")!
    private static let provider = "codex-appserver"
    private static let sessionKey = "basics-voice-tasks"
    /// No tools involved; warm codex answers in a few seconds, cold in ~20-40 s.
    private static let overallDeadline: TimeInterval = 60

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = Self.overallDeadline
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public API

    func isGatewayUp() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (data, response) = try? await self.session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true
        else { return false }
        return true
    }

    /// transcript + current task context → ops. Retries ONCE on invalid JSON
    /// with an explicit re-ask.
    func interpret(transcript: String, tasksContextJSON: String) async throws -> [TaskOp] {
        guard await self.isGatewayUp() else {
            throw ConduitTaskClientError.gatewayOffline
        }

        let prompt = Self.buildPrompt(transcript: transcript, tasksContextJSON: tasksContextJSON)
        let firstText = try await self.run(prompt: prompt)
        if let ops = Self.parseOps(from: firstText) {
            return ops
        }

        DebugLogger.shared.warning(
            "Conduit task reply was not valid JSON; re-asking once",
            source: "ConduitTaskClient"
        )
        let retryText = try await self.run(
            prompt: "Your previous reply was not valid JSON. Reply again with ONLY the JSON object, "
                + "no prose, no code fences.\n\n" + prompt
        )
        if let ops = Self.parseOps(from: retryText) {
            return ops
        }
        throw ConduitTaskClientError.invalidJSON(retryText)
    }

    // MARK: - Prompt

    nonisolated static func buildPrompt(transcript: String, tasksContextJSON: String) -> String {
        """
        You are a task-command interpreter for a voice task tracker. The user spoke a command; \
        map it onto operations against their task list. Reply with ONLY a JSON object, no prose, \
        no code fences, matching exactly:
        {"ops":[{"op":"start|done|add|update|remove|none","id":"<uuid, when referring to an existing task>","title":"<title, for start/add/update>","short":"<1-2 word label for start/add/update>","reason":"<only for none>"}]}
        Rules:
        - "short" is a crisp 1-2 word display label for the task (e.g. title "review the quarterly report" → short "Report review"). Always include it for start/add/update.
        - "start X" → op start (match X to an existing task's id when one clearly matches, else provide title to create it).
        - "done" / "finished" / "completed" (no target) → op done for the CURRENT task.
        - "add X" / "remind me to X" / "I need to X later" → op add.
        - Renaming/changing a task → op update with id + new title.
        - Deleting/cancelling → op remove with id.
        - Anything that is not a task command → single op none with a short reason.
        - Multiple commands in one utterance → multiple ops in spoken order.

        Current tasks (JSON): \(tasksContextJSON)

        User said: \(transcript)
        """
    }

    // MARK: - Wire

    private func run(prompt: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("run"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": Self.provider,
            "sessionKey": Self.sessionKey,
            "prompt": prompt,
        ])

        let (bytes, response) = try await self.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ConduitTaskClientError.badResponse("HTTP \(code)")
        }

        var lastAssistantText: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let kind = obj["kind"] as? String ?? ""
            if kind == "assistant_text", let text = obj["text"] as? String {
                lastAssistantText = text
            } else if kind.contains("error") {
                let detail = (obj["message"] as? String) ?? (obj["error"] as? String) ?? kind
                throw ConduitTaskClientError.badResponse(detail)
            } else if kind == "final_result" {
                break
            }
        }

        guard let text = lastAssistantText, !text.isEmpty else {
            throw ConduitTaskClientError.emptyResult
        }
        return text
    }

    // MARK: - JSON hardening (pure, testable)

    /// Strip code fences, slice first `{` to last `}`, decode.
    nonisolated static func parseOps(from raw: String) -> [TaskOp]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else {
            return nil
        }
        let sliced = String(text[first ... last])
        guard let data = sliced.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(TaskOpEnvelope.self, from: data)
        else { return nil }
        return envelope.ops
    }
}

// MARK: - Offline fallback

/// Deterministic parser for the basics when the Conduit gateway is down:
/// "start <title>", "done", "add <title>" (case-insensitive). Anything else
/// is rejected so the user gets an honest "gateway offline" instead of a wrong guess.
enum TaskCommandFallbackParser {
    static func parse(_ transcript: String) -> [TaskOp]? {
        let text = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!,"))
        let lower = text.lowercased()

        if lower == "done" || lower == "i'm done" || lower == "finished" || lower == "complete" || lower == "completed" {
            return [TaskOp(op: .done)]
        }
        for prefix in ["start ", "start working on ", "begin "] where lower.hasPrefix(prefix) {
            let title = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return [TaskOp(op: .start, title: title)] }
        }
        for prefix in ["add ", "add task ", "new task "] where lower.hasPrefix(prefix) {
            let title = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return [TaskOp(op: .add, title: title)] }
        }
        return nil
    }
}
