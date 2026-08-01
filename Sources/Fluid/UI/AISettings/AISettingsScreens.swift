import SwiftUI

struct VoiceEngineSettingsScreen: View {
    let appServices: AppServices
    let theme: AppTheme

    @StateObject private var viewModel: VoiceEngineSettingsViewModel

    init(appServices: AppServices, theme: AppTheme) {
        self.appServices = appServices
        self.theme = theme
        _viewModel = StateObject(wrappedValue: VoiceEngineSettingsViewModel(
            settings: SettingsStore.shared,
            appServices: appServices
        ))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                self.pageHead

                VoiceEngineSettingsView(
                    viewModel: self.viewModel,
                    settings: self.viewModel.settings,
                    theme: self.theme
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.windowBackground)
    }

    /// Eyebrow → title → one prose line, per the Basics page-head pattern.
    private var pageHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictation")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text("Voice engine")
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Text("Which model turns your speech into text, and where it runs. Local models never leave this Mac.")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AIEnhancementSettingsScreen: View {
    let menuBarManager: MenuBarManager
    let theme: AppTheme
    @Binding var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @Binding var shortcutRecordingMessage: String?

    @StateObject private var viewModel: AIEnhancementSettingsViewModel

    init(
        menuBarManager: MenuBarManager,
        theme: AppTheme,
        activeShortcutRecordingTarget: Binding<ShortcutRecordingTarget?> = .constant(nil),
        shortcutRecordingMessage: Binding<String?> = .constant(nil)
    ) {
        self.menuBarManager = menuBarManager
        self.theme = theme
        _activeShortcutRecordingTarget = activeShortcutRecordingTarget
        _shortcutRecordingMessage = shortcutRecordingMessage
        _viewModel = StateObject(wrappedValue: AIEnhancementSettingsViewModel(
            settings: SettingsStore.shared,
            menuBarManager: menuBarManager,
            promptTest: DictationPromptTestCoordinator.shared
        ))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                self.pageHead

                AIEnhancementSettingsView(
                    viewModel: self.viewModel,
                    settings: self.viewModel.settings,
                    promptTest: self.viewModel.promptTest,
                    theme: self.theme,
                    activeShortcutRecordingTarget: self.$activeShortcutRecordingTarget,
                    shortcutRecordingMessage: self.$shortcutRecordingMessage
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(self.theme.palette.windowBackground)
    }

    /// Eyebrow → title → one prose line, per the Basics page-head pattern.
    private var pageHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictation")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.accent)
            Text("AI enhancements")
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
            Text("Set up providers and prompt behavior separately. Providers are the models that can rewrite a transcript; prompts decide what they are told to do.")
                .basicsProse(15)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640, alignment: .leading)
        }
    }
}
