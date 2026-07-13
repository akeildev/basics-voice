import Foundation
import Security

enum PokeServiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)
    case network(String)
    case messagesSendFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Poke API key found. Add one in Settings or the Keychain (service \"poke-api\")."
        case .invalidResponse:
            return "Poke returned an unexpected response."
        case let .httpError(status, body):
            return "Poke request failed (HTTP \(status)): \(body)"
        case let .network(message):
            return message
        case let .messagesSendFailed(message):
            return "Could not send via Messages: \(message)"
        }
    }
}

/// Sends dictated transcripts to Poke.
///
/// Preferred transport: an iMessage into the user's real Poke conversation via Messages.app
/// (Apple Messages for Business chat), configured through the `PokeIMessageChatID` default —
/// a Messages chat id like "any;-;urn:biz:<uuid>". This lands the message in the same thread
/// the user already reads, and Poke's replies come back there.
///
/// Fallback transport: the Poke inbound API (https://poke.com/api/v1/inbound/api-message).
/// Caveat: API messages go to whichever Poke ACCOUNT owns the API key, which is not
/// necessarily the account behind the user's iMessage thread. The API key is read from the
/// app Keychain (provider ID "poke"), falling back to the user-level generic password item
/// with service "poke-api" (as created via `security add-generic-password -s poke-api`).
@MainActor
final class PokeService {
    static let shared = PokeService()

    static let keychainProviderID = "poke"
    static let iMessageChatIDDefaultsKey = "PokeIMessageChatID"
    private static let cliKeychainService = "poke-api"
    private static let endpoint = URL(string: "https://poke.com/api/v1/inbound/api-message")!

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    func hasAPIKey() -> Bool {
        self.resolveAPIKey() != nil
    }

    func send(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Preferred: send into the user's real Poke iMessage thread.
        if let chatID = UserDefaults.standard.string(forKey: Self.iMessageChatIDDefaultsKey),
           !chatID.isEmpty
        {
            try self.sendViaMessages(trimmed, chatID: chatID)
            DebugLogger.shared.info("Sent \(trimmed.count) chars to Poke via iMessage", source: "PokeService")
            return
        }

        guard let apiKey = self.resolveAPIKey() else {
            throw PokeServiceError.missingAPIKey
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": trimmed])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw PokeServiceError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PokeServiceError.invalidResponse
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw PokeServiceError.httpError(httpResponse.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true
        else {
            throw PokeServiceError.httpError(httpResponse.statusCode, body)
        }

        DebugLogger.shared.info("Sent \(trimmed.count) chars to Poke", source: "PokeService")
    }

    // MARK: - iMessage transport

    private func sendViaMessages(_ text: String, chatID: String) throws {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedChatID = chatID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Messages\" to send \"\(escapedText)\" to chat id \"\(escapedChatID)\""

        guard let script = NSAppleScript(source: source) else {
            throw PokeServiceError.messagesSendFailed("Could not build the Messages script.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw PokeServiceError.messagesSendFailed(message)
        }
    }

    // MARK: - API key resolution

    private func resolveAPIKey() -> String? {
        if let key = try? KeychainService.shared.fetchKey(for: Self.keychainProviderID),
           !key.isEmpty
        {
            return key
        }

        // Fall back to the CLI-created item and migrate it into the app's key store
        // so subsequent reads don't re-prompt for the foreign Keychain item.
        if let cliKey = self.readCLIKeychainItem(), !cliKey.isEmpty {
            try? KeychainService.shared.storeKey(cliKey, for: Self.keychainProviderID)
            return cliKey
        }

        return nil
    }

    private func readCLIKeychainItem() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.cliKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                DebugLogger.shared.warning(
                    "Poke CLI keychain lookup failed (OSStatus: \(status))",
                    source: "PokeService"
                )
            }
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
