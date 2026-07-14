import Foundation
import UserNotifications

enum NotificationService {
    enum UserInfoKey {
        static let kind = "kind"
    }

    enum Kind {
        static let aiProcessingFallback = "aiProcessingFallback"
        static let commandModeFailure = "commandModeFailure"
        static let pokeResult = "pokeResult"
        static let taskResult = "taskResult"
    }

    static func showAIProcessingFallback(error: String) {
        guard SettingsStore.shared.notifyAIProcessingFailures else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverAIProcessingFallback(error: error, using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, requestError in
                    if let requestError {
                        DebugLogger.shared.warning(
                            "Notification permission request failed: \(requestError.localizedDescription)",
                            source: "NotificationService"
                        )
                    }
                    guard granted else { return }
                    self.deliverAIProcessingFallback(error: error, using: center)
                }
            case .denied:
                DebugLogger.shared.debug(
                    "Skipping AI fallback notification because notification permission is denied",
                    source: "NotificationService"
                )
            @unknown default:
                break
            }
        }
    }

    static func showCommandModeFailure(error: String) {
        guard SettingsStore.shared.notifyAIProcessingFailures else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverCommandModeFailure(error: error, using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, requestError in
                    if let requestError {
                        DebugLogger.shared.warning(
                            "Notification permission request failed: \(requestError.localizedDescription)",
                            source: "NotificationService"
                        )
                    }
                    guard granted else { return }
                    self.deliverCommandModeFailure(error: error, using: center)
                }
            case .denied:
                DebugLogger.shared.debug(
                    "Skipping Command Mode notification because notification permission is denied",
                    source: "NotificationService"
                )
            @unknown default:
                break
            }
        }
    }

    /// Shown after a "Send to Poke" dictation completes — success confirmation or the failure reason.
    /// Not gated on notifyAIProcessingFailures: the send is invisible otherwise, so the user
    /// always deserves confirmation that their message actually left the machine.
    static func showPokeResult(success: Bool, detail: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverPokeResult(success: success, detail: detail, using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, requestError in
                    if let requestError {
                        DebugLogger.shared.warning(
                            "Notification permission request failed: \(requestError.localizedDescription)",
                            source: "NotificationService"
                        )
                    }
                    guard granted else { return }
                    self.deliverPokeResult(success: success, detail: detail, using: center)
                }
            case .denied:
                DebugLogger.shared.debug(
                    "Skipping Poke notification because notification permission is denied",
                    source: "NotificationService"
                )
            @unknown default:
                break
            }
        }
    }

    /// Shown after a voice task command: what was applied (or why nothing was).
    /// Ungated for the same reason as Poke — the HUD updates silently otherwise.
    static func showTaskResult(success: Bool, detail: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverTaskResult(success: success, detail: detail, using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.deliverTaskResult(success: success, detail: detail, using: center)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func deliverTaskResult(success: Bool, detail: String, using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Tasks updated" : "Task command failed"
        content.body = detail
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.taskResult]

        let request = UNNotificationRequest(
            identifier: "task-result-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show task notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }

    private static func deliverPokeResult(success: Bool, detail: String, using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Sent to Instinct ✓" : "Instinct send failed"
        content.body = detail
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.pokeResult]

        let request = UNNotificationRequest(
            identifier: "poke-result-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show Poke notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }

    private static func deliverAIProcessingFallback(error: String, using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "AI Enhancement failed"
        content.body = "Typed raw transcription instead."
        content.subtitle = error
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.aiProcessingFallback]

        let request = UNNotificationRequest(
            identifier: "ai-cleanup-fallback-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show AI fallback notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }

    private static func deliverCommandModeFailure(error: String, using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Command Mode needs setup"
        content.body = error
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.commandModeFailure]

        let request = UNNotificationRequest(
            identifier: "command-mode-failure-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show Command Mode notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }
}
