# Agent setup guide — Basics Voice (FluidVoice fork)

You are setting this fork up on a user's Mac. Full human docs: `BASICS-VOICE.md`.
Read the Troubleshooting section there before improvising — the signing and TCC
traps are non-obvious and the scripts already encode the fixes.

## Golden path

```bash
# 1. Verify prerequisites
xcodebuild -version                                   # needs full Xcode
security find-identity -v -p codesigning              # needs an "Apple Development" identity

# 2. Build + install (idempotent; safe to re-run)
scripts/deploy-basics-voice.sh                        # -> "/Applications/Basics Voice.app"

# 3. Wire Send-to-Poke to the USER'S OWN Poke conversation
scripts/setup-poke.sh --check                         # requirements only
scripts/setup-poke.sh                                 # detect thread + bind backtick
# optional: scripts/setup-poke.sh --with-fn-dictation # move normal dictation to Fn/Globe
```

## Hard rules

- **Never sign ad-hoc, never `codesign --deep`, never hand-install the DerivedData
  app.** Always deploy through `scripts/deploy-basics-voice.sh`. Reasons are
  documented in the script and BASICS-VOICE.md (TCC keys grants to the signature;
  SPM frameworks aren't embedded by `xcodebuild build`).
- **Send-to-Poke requires the user's own Poke thread in Messages** (an Apple
  Messages-for-Business chat named "Poke"). If `setup-poke.sh` can't find it, the
  user must sign up at poke.com and start its Apple Messages chat — you cannot do
  this for them. Do not fall back to the HTTP API unless the user confirms the API
  key's account matches the conversation they read (see BASICS-VOICE.md).
- Reading `~/Library/Messages/chat.db` needs Full Disk Access on the terminal.
  If unavailable, give the user the manual `sqlite3`/`defaults` two-liner from
  BASICS-VOICE.md instead of trying to escalate.
- The things only the USER can do (tell them, don't attempt): grant Accessibility,
  approve the Microphone dialog, approve "control Messages" (Automation) on first
  send, enable Notifications.

## Verify the install (evidence, not vibes)

```bash
pgrep -lf "Basics Voice.app/Contents/MacOS"                       # app running
codesign -d -r- "/Applications/Basics Voice.app" 2>&1 | grep -v cdhash  # NOT ad-hoc
defaults read com.FluidApp.app PokeIMessageChatID                 # chat id set
# After the user holds ` and speaks, confirm the pipeline in the app log:
grep -iE "poke" ~/Library/Logs/Fluid/Fluid.log | tail -5
# Expect: "Poke mode shortcut pressed" ... "Sent N chars to Poke via iMessage"
```

## Key implementation facts (for code changes)

- Send-to-Poke mirrors Command Mode: `.poke` case in `ActiveRecordingMode` +
  `pokeMode` in `GlobalHotkeyManager` + a branch in
  `ContentView.stopAndProcessTranscription` before the typing path.
- Delivery: `Sources/Fluid/Services/PokeService.swift` — iMessage via NSAppleScript
  to `PokeIMessageChatID`, HTTP API fallback (Keychain provider `poke` /
  generic password service `poke-api`).
- Shortcuts persist as JSON-encoded `HotkeyShortcut` data in UserDefaults
  (`PokeHotkeyShortcut`, `PokeShortcutEnabled`); the Settings UI row lives in
  `SettingsView.swift` ("Send to Poke").
