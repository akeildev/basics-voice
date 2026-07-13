#!/bin/bash
#
# Send-to-Poke setup
# -------------------
# Wires the "Send to Poke" dictation mode to YOUR Poke conversation:
# finds your Poke thread in Messages, stores its chat id for the app, and
# (optionally) binds the shortcut keys.
#
# Usage:
#   scripts/setup-poke.sh                    # detect Poke thread + enable, backtick (`) as the Poke key
#   scripts/setup-poke.sh --with-fn-dictation  # ALSO move normal dictation to the Fn/Globe key
#   scripts/setup-poke.sh --check            # requirements check only, change nothing
#
# Requirements (checked below):
#   1. A Poke account (poke.com) connected to Apple Messages — i.e. you have a
#      "Poke" conversation in the Messages app that you've texted at least once.
#      If you don't: sign up at poke.com and start its Apple Messages chat first.
#   2. This fork's app installed (scripts/deploy-basics-voice.sh).
#   3. Terminal needs Full Disk Access to read the Messages database for
#      auto-detection (System Settings > Privacy & Security > Full Disk Access).
#      Without it, find the chat id manually — see BASICS-VOICE.md.
#
set -euo pipefail

BUNDLE_ID="com.FluidApp.app"
DB="$HOME/Library/Messages/chat.db"
MODE="${1:-}"

fail() { echo "!! $1"; exit 1; }

echo "==> Checking requirements..."

[ "$(uname)" = "Darwin" ] || fail "macOS only."

APP_NAME="${BASICS_APP_NAME:-Basics Voice}"
if [ ! -d "/Applications/${APP_NAME}.app" ]; then
  echo "   (\"${APP_NAME}\" not found in /Applications yet — run scripts/deploy-basics-voice.sh first)"
else
  echo "   ✓ /Applications/${APP_NAME}.app installed"
fi

[ -r "$DB" ] || fail "Cannot read $DB.
   Give your terminal Full Disk Access (System Settings > Privacy & Security >
   Full Disk Access), restart the terminal, and re-run. Or set the chat id
   manually — see 'Send to Poke' in BASICS-VOICE.md."

# Poke uses an Apple Messages-for-Business chat; its stable identifier is a
# urn:biz: chat. Match by display name.
CHAT_GUID=$(sqlite3 "$DB" \
  "SELECT guid FROM chat WHERE display_name='Poke' AND chat_identifier LIKE 'urn:biz:%' LIMIT 1;" 2>/dev/null || true)

[ -n "$CHAT_GUID" ] || fail "No Poke conversation found in Messages.
   Requirements: a Poke account (poke.com) with its Apple Messages chat started —
   open the Poke onboarding link / text Poke once so the thread exists, then re-run."

echo "   ✓ Found Poke thread: $CHAT_GUID"

if [ "$MODE" = "--check" ]; then
  echo "==> Check complete. Nothing changed."
  exit 0
fi

echo "==> Configuring the app..."
defaults write "$BUNDLE_ID" PokeIMessageChatID -string "$CHAT_GUID"
defaults write "$BUNDLE_ID" PokeShortcutEnabled -bool true

# Default Poke key: plain backtick (`), press-and-hold. Change anytime in the
# app: Settings > "Send to Poke" row.
POKE_KEY='{"kind":"keyboard","keyCode":50,"modifierFlagsRawValue":0}'
defaults write "$BUNDLE_ID" PokeHotkeyShortcut -data "$(printf '%s' "$POKE_KEY" | xxd -p | tr -d '\n')"
echo "   ✓ Poke chat id stored; backtick (\`) bound to Send-to-Poke (hold to talk)"

if [ "$MODE" = "--with-fn-dictation" ]; then
  PRIMARY='[{"kind":"keyboard","keyCode":63,"modifierFlagsRawValue":0,"modifierKeyCodes":[63]}]'
  defaults write "$BUNDLE_ID" PrimaryDictationShortcuts -data "$(printf '%s' "$PRIMARY" | xxd -p | tr -d '\n')"
  # Stop macOS from opening the emoji picker / system dictation on Fn presses.
  defaults write com.apple.HIToolbox AppleFnUsageType -int 0
  echo "   ✓ Normal dictation moved to the Fn/Globe key (system Fn action disabled)"
fi

echo "==> Restarting the app to pick up settings..."
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 1
open -a "$APP_NAME" 2>/dev/null || echo "   (launch \"$APP_NAME\" manually)"

cat <<'EOF'

==> Done. How to use:
    HOLD the backtick key (`), speak, RELEASE — the transcript is sent as an
    iMessage to your Poke conversation; Poke replies in that same thread.

    First send: macOS will ask "…wants to control Messages" — click Allow (once).
    A "Sent to Poke ✓" notification confirms each send (enable notifications for
    the app in System Settings > Notifications).
EOF
