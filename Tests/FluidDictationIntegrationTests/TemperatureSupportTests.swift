@testable import FluidVoice_Debug
import XCTest

// Regression tests for the Anthropic `temperature` deprecation handling.
// Newer Anthropic models (Opus 4.7+, Sonnet 4.6+, Sonnet 5, Fable/Mythos 5) reject the
// `temperature` parameter with HTTP 400 "`temperature` is deprecated for this model."
// See https://github.com/altic-dev/FluidVoice/issues/285 (Opus 4.7) — the same failure
// recurred for Sonnet 5 / Sonnet 4.6 because the check only matched claude-opus-4-7.

@MainActor
final class TemperatureSupportTests: XCTestCase {
    func testTemperatureUnsupported_newerAnthropicModels() {
        let unsupported = [
            "claude-opus-4-7",
            "claude-opus-4-8",
            "claude-sonnet-4-6",
            "claude-sonnet-5",
            "claude-fable-5",
            "claude-mythos-5",
            // Provider-prefixed IDs (e.g. OpenRouter) must match too
            "anthropic/claude-sonnet-5",
        ]
        for model in unsupported {
            XCTAssertTrue(
                SettingsStore.shared.isTemperatureUnsupported(model),
                "\(model) rejects `temperature` — sending it fails with HTTP 400"
            )
        }
    }

    func testTemperatureUnsupported_openAIReasoningModels() {
        for model in ["o1", "o3-mini", "gpt-5", "openai/gpt-oss-120b"] {
            XCTAssertTrue(
                SettingsStore.shared.isTemperatureUnsupported(model),
                "\(model) is a reasoning model and must not receive `temperature`"
            )
        }
    }

    func testTemperatureSupported_olderAndNonAnthropicModels() {
        for model in ["gpt-4.1", "claude-sonnet-4-20250514", "gemini-2.5-flash", "llama3"] {
            XCTAssertFalse(
                SettingsStore.shared.isTemperatureUnsupported(model),
                "\(model) still supports `temperature` and should keep receiving it"
            )
        }
    }
}
