# Basics Voice — a FluidVoice fork with Send-to-Poke

This is a personal/team fork of [FluidVoice](https://github.com/altic-dev/FluidVoice)
(open-source macOS voice dictation, GPLv3) that adds:

- **Send-to-Poke** — a second push-to-talk shortcut: hold a key, speak, release,
  and the transcript is sent straight to your [Poke](https://poke.com) assistant
  as an iMessage into your real Poke conversation. Poke replies in that thread
  like any other text. Nothing is typed into the frontmost app.
- **A repeatable local deploy pipeline** — one script builds the source and
  installs it to `/Applications` under your own app name, signed so macOS
  permissions survive every rebuild.

Everything upstream still works: on-device speech models (Parakeet etc.),
normal dictation typing, Command Mode, Edit Mode.

---

## Requirements

| What | Why | Notes |
|---|---|---|
| macOS 14+ on Apple Silicon | upstream requirement | |
| Xcode (full app, not just CLT) | building | `xcodebuild -version` should work |
| An Apple Development signing certificate | **permissions survive rebuilds** | Free Apple ID works: Xcode → Settings → Accounts → add ID → Manage Certificates → “+” → Apple Development |
| A Poke account **connected to Apple Messages** | Send-to-Poke | You must have a "Poke" conversation in the Messages app that you've texted at least once. Sign up at poke.com and start its Apple Messages chat during onboarding. |
| Full Disk Access for your terminal (setup only) | auto-detecting your Poke thread | System Settings → Privacy & Security → Full Disk Access |

## Install

```bash
git clone https://github.com/akeildev/basics-voice.git
cd basics-voice
scripts/deploy-basics-voice.sh          # build + install "/Applications/Basics Voice.app"
scripts/setup-poke.sh                   # wire Send-to-Poke to YOUR Poke thread
open -a "Basics Voice"
```

Want a different app name? `BASICS_APP_NAME="My Voice" scripts/deploy-basics-voice.sh`
(and pass the same env to `setup-poke.sh`).

### First-run permissions (one time each)

1. **Accessibility** — System Settings → Privacy & Security → Accessibility → add the app
   (needed for global hotkeys + typing).
2. **Microphone** — the app asks on first recording; click Allow. If no dialog ever
   appears, the app was signed without the release entitlements — use the deploy
   script, never sign by hand.
3. **Notifications** — allow, so you get the "Sent to Poke ✓" confirmations.
4. **Automation → Messages** — on your FIRST Poke send, macOS asks
   "…wants to control Messages"; click Allow.

## Using it

| Key (defaults from `setup-poke.sh`) | Action |
|---|---|
| hold **`` ` ``** (backtick), speak, release | send transcript to Poke via iMessage |
| primary dictation key (upstream default, or **Fn/Globe** with `--with-fn-dictation`) | normal dictation — types where your cursor is |

Change any binding in the app: **Settings → shortcut rows** ("Send to Poke" has its
own row with an enable toggle). Activation mode (hold / toggle / automatic) is shared
by all shortcuts and set in the same screen.

## How Send-to-Poke delivers (and why iMessage, not the API)

Poke has an inbound HTTP API, but it delivers to whichever Poke **account owns the
API key** — which is easy to get wrong (web login ≠ the account behind your phone's
thread) and Poke has **no web chat** to check (it lives in Apple Messages / WhatsApp /
Telegram only). Messages sent to the wrong account vanish somewhere you can never read.

So this fork sends through **Messages.app into your actual Poke thread** (an Apple
Messages-for-Business chat). Your message and Poke's reply both live in the
conversation you already read, on every device.

- The chat id is stored in the app default `PokeIMessageChatID`
  (looks like `any;-;urn:biz:<uuid>`). `scripts/setup-poke.sh` finds it automatically.
- Manual lookup, if you skip the script:
  ```bash
  sqlite3 ~/Library/Messages/chat.db \
    "SELECT guid FROM chat WHERE display_name='Poke' AND chat_identifier LIKE 'urn:biz:%';"
  defaults write com.FluidApp.app PokeIMessageChatID -string "<that guid>"
  ```
- **API fallback:** if `PokeIMessageChatID` is unset, the app POSTs to
  `poke.com/api/v1/inbound/api-message` with a key from the Keychain
  (app keychain provider `poke`, or a generic password with service `poke-api`).
  Only use this if you're certain the key belongs to the same account as the
  conversation you actually read.

## Updating

```bash
scripts/deploy-basics-voice.sh --update   # pull upstream FluidVoice, rebuild, reinstall
```

Your local commits are rebased on top of upstream (`git pull --rebase`). Permissions
survive because the signing identity stays constant.

## Troubleshooting (hard-won)

- **"Enabled in Accessibility settings but the app says permission required"** —
  the app is ad-hoc signed (designated requirement = cdhash, changes every build).
  Re-deploy with the script; it refuses ad-hoc signing for exactly this reason.
  Then remove the stale entry in System Settings and re-add.
- **Mic permission dialog never appears / app absent from Microphone settings** —
  signed with the dev entitlements instead of `Fluid.release.entitlements`
  (hardened runtime silently kills the request without
  `com.apple.security.device.audio-input`). The Microphone pane has no “+” button;
  apps only appear after they ask. Re-deploy with the script.
- **App crashes at launch: `Library not loaded: @rpath/MediaRemoteAdapter.framework`** —
  `xcodebuild build` doesn't embed SPM dynamic frameworks; the deploy script copies
  them into `Contents/Frameworks/`. Don't install the raw DerivedData app by hand.
- **Never `codesign --deep`** — it mangles nested framework bundles
  ("bundle format is ambiguous"). Sign frameworks first, then the outer bundle
  (the script does).
- **Poke never replies** — check the Messages thread: did your message appear?
  If the send failed, you got a "Poke send failed" notification with the reason.
  If it sent but Poke is silent, that's between you and Poke (check poke.com status).
- **Fn/Globe key also opens the emoji picker** — `setup-poke.sh --with-fn-dictation`
  sets `AppleFnUsageType=0` ("Press 🌐 to: Do Nothing"). Re-enable in System
  Settings → Keyboard if you ever want the system action back.

## License

GPLv3, same as upstream FluidVoice. This fork's changes are published under the
same license; upstream authorship and history are preserved.
