# Basics Voice — redesign tracker

Generated from an exhaustive read of the real code (8 parallel readers + completeness audit).
A row is only DONE when: the Paper board exists, the Swift matches it, and it has been
seen working in the running app. No mocked data, no hard-coded values, no static images.

- **120 live surfaces** to cover
- **7 unreachable** (dead code — flag for deletion, do not redesign)
- **13 Paper boards** exist so far (light mode)

Legend — `paper`: design exists · `code`: implemented · `proof`: seen working in the app


## window-page  (15)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Settings | 98 | 21 | ✅ | — | — | `Sources/Fluid/UI/SettingsView.swift:242` |
| Getting Started / Welcome to FluidVoice | 65 | 14 | ✅ | — | — | `Sources/Fluid/UI/WelcomeView.swift:12` |
| Custom Dictionary | 52 | 15 | ✅ | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:13` |
| Stats | 36 | 7 | ✅ | — | — | `Sources/Fluid/UI/StatsView.swift:3` |
| Transcription History | 27 | 10 | ✅ | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:5` |
| Meeting Transcription | 24 | 10 | ✅ | — | — | `Sources/Fluid/UI/MeetingTranscriptionView.swift:4` |
| Edit Mode | 23 | 10 | ✅ | — | — | `Sources/Fluid/Views/RewriteModeView.swift:3` |
| Command Mode | 18 | 11 | ✅ | — | — | `Sources/Fluid/Views/CommandModeView.swift:3` |
| Voice Engine | 15 | 6 | ✅ | — | — | `Sources/Fluid/UI/AISettingsView+SpeechRecognition.swift:13` |
| Send Feedback | 11 | 6 | ✅ | — | — | `Sources/Fluid/UI/FeedbackView.swift:12` |
| Change logs | 8 | 5 | ✅ | — | — | `Sources/Fluid/UI/ChangelogView.swift:3` |
| FluidVoice | 7 | 5 | — | — | — | `Sources/Fluid/ContentView.swift:324` |
| Voice Dictation | 4 | 5 | — | — | — | `Sources/Fluid/UI/RecordingView.swift:11` |
| AI Enhancement | 4 | 4 | ✅ | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:49` |
| FluidVoice (main window shell created from the menu  | 3 | 4 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:957` |

## overlay  (9)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Dictation Overlay (bottom pill/panel) | 29 | 16 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:1953` |
| Train by Voice | 19 | 8 | — | — | — | `Sources/Fluid/Views/AutomaticDictionaryCorrectionOverlay.swift:302` |
| TASKS (notch HUD — expanded) | 18 | 7 | — | — | — | `Sources/Fluid/NotchHUD/NotchHUDRootView.swift:151` |
| Correction noticed | 10 | 4 | — | — | — | `Sources/Fluid/Views/AutomaticDictionaryCorrectionOverlay.swift:270` |
| Notch overlay status strings driven from the main wi | 9 | 7 | — | — | — | `Sources/Fluid/ContentView.swift:2106` |
| Tasks notch HUD — collapsed | 6 | 5 | — | — | — | `Sources/Fluid/NotchHUD/NotchHUDRootView.swift:101` |
| Drag <App> into the Accessibility apps list as shown | 4 | 6 | — | — | — | `Sources/Fluid/ContentView.swift:4486` |
| Added to Dictionary | 3 | 3 | — | — | — | `Sources/Fluid/Views/AutomaticDictionaryCorrectionOverlay.swift:409` |
| Replacement added / Recorded toast | 3 | 3 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:2794` |

## onboarding-step  (8)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| One more thing... (onboarding step 6 of 6 — Set Up A | 43 | 10 | ✅ | — | — | `Sources/Fluid/UI/OnboardingAIEnhancementStepView.swift:4` |
| Choose your voice engine (onboarding step 3 of 6 — C | 33 | 12 | ✅ | — | — | `Sources/Fluid/UI/WelcomeView.swift:1544` |
| Let FluidVoice listen and type (onboarding step 4 of | 18 | 6 | — | — | — | `Sources/Fluid/UI/WelcomeView.swift:1670` |
| Let's polish your text. (AI Enhancement step — try-o | 15 | 6 | ✅ | — | — | `Sources/Fluid/UI/OnboardingAIEnhancementStepView.swift:342` |
| What language will you speak most? (onboarding step  | 10 | 5 | — | — | — | `Sources/Fluid/UI/WelcomeView.swift:1084` |
| Onboarding (full-window takeover) | 8 | 3 | — | — | — | `Sources/Fluid/ContentView.swift:1384` |
| Welcome (onboarding step 1 of 6) | 7 | 4 | — | — | — | `Sources/Fluid/UI/WelcomeView.swift:1005` |
| FluidVoice is ready. (onboarding step 5 of 6 — Try F | 7 | 5 | — | — | — | `Sources/Fluid/UI/WelcomeView.swift:1784` |

## sheet  (15)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Prompt editor (Default / New / Edit / local-AI promp | 35 | 7 | — | — | — | `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:1631` |
| Anonymous Analytics | 19 | 1 | — | — | — | `Sources/Fluid/UI/AnalyticsPrivacyView.swift:3` |
| Edit Dictionary Entry | 9 | 4 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:3338` |
| Add Dictionary Entry | 9 | 5 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:3187` |
| Share anonymous datapoint | 8 | 4 | — | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:632` |
| Are you sure you want to stop sharing anonymous anal | 5 | 1 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:2722` |
| You’re Up To Date  /  You’re Up To Date (Beta) | 5 | 2 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:758` |
| No rollback backup found | 4 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:776` |
| Rollback to <version>? | 4 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:788` |
| Rollback Successful | 4 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:800` |
| Delete this chat? | 3 | 2 | — | — | — | `Sources/Fluid/Views/CommandModeView.swift:163` |
| Error alert | 3 | 2 | — | — | — | `Sources/Fluid/ContentView.swift:383` |
| Update Found! | 3 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:748` |
| Update Check Failed | 3 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:763` |
| Rollback Failed | 3 | 1 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:810` |

## popover  (10)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Punctuation Dictionary | 19 | 5 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:1261` |
| Reasoning for <model> | 10 | 4 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2457` |
| Custom Words | 9 | 4 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:1106` |
| Your Dictionary | 8 | 3 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:969` |
| Model picker (searchable) | 7 | 6 | — | — | — | `Sources/Fluid/UI/SearchableModelPicker.swift:86` |
| Your Typing Speed | 6 | 2 | — | — | — | `Sources/Fluid/UI/StatsView.swift:206` |
| Model picker popover | 5 | 4 | — | — | — | `Sources/Fluid/UI/SearchableModelPicker.swift:86` |
| Provider picker popover | 5 | 5 | — | — | — | `Sources/Fluid/UI/SearchableProviderPicker.swift:81` |
| Prompt Profiles (help popover) | 5 | 1 | — | — | — | `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:39` |
| Nemotron language picker | 1 | 2 | — | — | — | `Sources/Fluid/UI/AISettingsView+SpeechRecognition.swift:621` |

## menu  (7)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Menu bar dropdown (status-item menu) | 14 | 6 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:485` |
| Microphone (submenu) | 8 | 5 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:622` |
| History entry context menu | 7 | 3 | — | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:200` |
| Mode menu | 5 | 5 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:1324` |
| AI Prompt menu | 5 | 5 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:1437` |
| Actions menu | 4 | 3 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:1670` |
| Recent chats | 2 | 3 | — | — | — | `Sources/Fluid/Views/CommandModeView.swift:105` |

## modal-picker  (18)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Rollback to <version>? | 6 | 3 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:520` |
| Keychain Access Required | 6 | 3 | — | — | — | `Sources/Fluid/UI/AISettings/AIEnhancementSettingsViewModel.swift:711` |
| Download Previous Build | 5 | 2 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:1872` |
| Import this dictionary? | 5 | 1 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:2180` |
| Dictionary Exported / Imported / Failed alerts | 5 | 2 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:2203` |
| Download Previous Build | 5 | 2 | — | — | — | `Sources/Fluid/Services/MenuBarManager.swift:848` |
| Delete Prompt? | 5 | 2 | — | — | — | `Sources/Fluid/UI/AISettings/AIEnhancementSettingsView.swift:119` |
| Couldn't Add App Override | 5 | 1 | — | — | — | `Sources/Fluid/UI/AISettings/AIEnhancementSettingsView.swift:133` |
| Import this backup? | 4 | 3 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:1724` |
| Prune saved audio? | 4 | 3 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:1778` |
| Delete saved audio? | 4 | 2 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:1801` |
| Update result alerts (Update Found! / You're Up To D | 4 | 4 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:480` |
| Clear All History | 4 | 1 | — | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:64` |
| Reset All Stats | 4 | 1 | ✅ | — | — | `Sources/Fluid/UI/StatsView.swift:645` |
| Feedback Failed | 4 | 1 | — | — | — | `Sources/Fluid/UI/FeedbackView.swift:210` |
| Report Sent | 3 | 1 | — | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:75` |
| Pair Export Failed | 3 | 1 | — | — | — | `Sources/Fluid/UI/TranscriptionHistoryView.swift:606` |
| Feedback Sent | 3 | 1 | — | — | — | `Sources/Fluid/UI/FeedbackView.swift:205` |

## component  (38)

| screen | ctrls | states | paper | code | proof | source |
|---|--:|--:|:--:|:--:|:--:|---|
| Fluid Intelligence local runtime (private AI provide | 21 | 8 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:639` |
| AI Providers | 20 | 5 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:167` |
| Shortcut recording (capture overlay behavior + confl | 18 | 5 | — | — | — | `Sources/Fluid/ContentView.swift:101` |
| Dictate prompt routing | 18 | 6 | — | — | — | `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:940` |
| Speech model row | 18 | 8 | — | — | — | `Sources/Fluid/UI/AISettingsView+SpeechRecognition.swift:308` |
| Button & control style catalogue | 17 | 4 | — | — | — | `Sources/Fluid/Theme/NativeButtonStyles.swift:16` |
| Provider details (expanded API provider) | 16 | 7 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:1319` |
| Sidebar | 15 | 3 | — | — | — | `Sources/Fluid/ContentView.swift:1254` |
| App theme tokens | 15 | 3 | — | — | — | `Sources/Fluid/Theme/AppTheme.swift:5` |
| Dictation shortcut try-out card | 14 | 6 | — | — | — | `Sources/Fluid/UI/OnboardingTryoutStepView.swift:3` |
| Edit Mode — How to use | 13 | 3 | ✅ | — | — | `Sources/Fluid/Views/RewriteModeView.swift:353` |
| Message bubble (chat message) | 12 | 7 | — | — | — | `Sources/Fluid/Views/CommandModeView.swift:679` |
| Detail pane (router) | 12 | 3 | — | — | — | `Sources/Fluid/ContentView.swift:1347` |
| Edit Provider | 12 | 4 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2195` |
| Model stats panel | 12 | 6 | — | — | — | `Sources/Fluid/UI/AISettingsView+SpeechRecognition.swift:165` |
| Command Mode — How to use | 11 | 3 | ✅ | — | — | `Sources/Fluid/Views/CommandModeView.swift:205` |
| Add Word / Edit Word | 11 | 4 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:1193` |
| App Overrides | 11 | 5 | — | — | — | `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:1275` |
| Microphone permission block (DEAD CODE — not rendere | 10 | 5 | — | — | — | `Sources/Fluid/ContentView.swift:1432` |
| Edit Provider (Fluid Intelligence / local) | 10 | 4 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2005` |
| Recording modes and output routes (internal state ma | 9 | 3 | — | — | — | `Sources/Fluid/ContentView.swift:184` |
| Add Rule / Edit Rule | 8 | 4 | — | — | — | `Sources/Fluid/UI/CustomDictionaryView.swift:1448` |
| Verified provider row | 8 | 5 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:1610` |
| Confirm Execution | 6 | 3 | — | — | — | `Sources/Fluid/Views/CommandModeView.swift:380` |
| Release card | 6 | 3 | — | — | — | `Sources/Fluid/UI/ChangelogView.swift:180` |
| Provider card (collapsed / expandable) | 6 | 5 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:534` |
| Filler words to remove: | 5 | 3 | — | — | — | `Sources/Fluid/UI/SettingsView.swift:2550` |
| Fluid "F" mark (SwiftUI) | 5 | 1 | — | — | — | `Sources/Fluid/UI/FluidIcon.swift:3` |
| AI enhancement failure row | 3 | 3 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:2779` |
| Waveform visualiser | 3 | 5 | — | — | — | `Sources/Fluid/Views/BottomOverlayView.swift:3249` |
| Edit Mode — Thinking | 3 | 3 | ✅ | — | — | `Sources/Fluid/Views/RewriteModeView.swift:428` |
| Today stats toolbar pill | 3 | 3 | — | — | — | `Sources/Fluid/ContentView.swift:4680` |
| Notch HUD chrome (shape + panel) | 3 | 4 | — | — | — | `Sources/Fluid/NotchHUD/NotchHUDShape.swift:8` |
| Glossy effects | 3 | 1 | — | — | — | `Sources/Fluid/UI/GlossyEffects.swift:5` |
| Model picker | 2 | 6 | — | — | — | `Sources/Fluid/UI/SearchableModelPicker.swift:11` |
| Advanced Prompts | 2 | 2 | — | — | — | `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:1968` |
| Provider picker | 1 | 3 | — | — | — | `Sources/Fluid/UI/SearchableProviderPicker.swift:11` |
| Menu bar icon generator (AppKit) | 1 | 1 | — | — | — | `Sources/Fluid/UI/MenuBarIconGenerator.swift:3` |

## unreachable — delete, do not redesign

- `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2688` — UNREACHABLE — API key editor sheet
- `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2721` — UNREACHABLE — Add Custom Provider form
- `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2615` — UNREACHABLE — legacy connection test + API key rows
- `Sources/Fluid/UI/AISettingsView+AIConfiguration.swift:2384` — UNREACHABLE — legacy model row / add-model / Apple Intelligence rows
- `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:882` — UNREACHABLE — prompt mode tabs, hint row, selected-apps summary
- `Sources/Fluid/UI/AISettingsView+AdvancedSettings.swift:1172` — UNREACHABLE — Edit-mode inline model controls
- `Sources/Fluid/UI/AISettingsView+SpeechRecognition.swift:652` — UNREACHABLE — Voice Engine model status strip
