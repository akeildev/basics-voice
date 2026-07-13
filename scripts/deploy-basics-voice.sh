#!/bin/bash
#
# Basics Voice — build & deploy
# ------------------------------
# Builds this FluidVoice fork and installs it to /Applications under your own
# app name (default "Basics Voice"), signed with a stable identity so macOS
# permissions (Accessibility, Microphone) survive rebuilds.
#
# Usage:
#   scripts/deploy-basics-voice.sh             # build current source + (re)install
#   scripts/deploy-basics-voice.sh --update    # git pull --rebase upstream first
#
# Environment overrides:
#   BASICS_APP_NAME   App name to install as        (default: Basics Voice)
#   BASICS_SIGN_ID    codesign identity to use      (default: first "Apple Development" in keychain)
#
# Requirements: Xcode (full, not just CLT) and at least one Apple Development
# signing certificate (a free Apple ID added in Xcode > Settings > Accounts works).
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${BASICS_APP_NAME:-Basics Voice}"
DEST="/Applications/${APP_NAME}.app"
DD="$REPO/.build-dd"
LOG="$REPO/.last-deploy.log"

cd "$REPO"

if [[ "${1:-}" == "--update" ]]; then
  echo "==> Pulling upstream updates (git pull --rebase)..."
  git pull --rebase
fi

echo "==> Building ${APP_NAME} (Release, from FluidVoice source)..."
if ! xcodebuild -project Fluid.xcodeproj -scheme Fluid -configuration Release \
      -destination 'platform=macOS' -derivedDataPath "$DD" \
      build CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1; then
  echo "!! BUILD FAILED. Last 20 lines of $LOG:"
  tail -20 "$LOG"
  exit 1
fi

BUILT="$DD/Build/Products/Release/FluidVoice.app"
[ -d "$BUILT" ] || { echo "!! Built app not found at $BUILT"; exit 1; }

echo "==> Quitting any running instance..."
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 1

echo "==> Installing to $DEST ..."
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

# The `xcodebuild build` action does not embed SPM dynamic frameworks (e.g.
# MediaRemoteAdapter) into the bundle, so the app dyld-crashes at launch when
# run outside DerivedData. Copy every built package framework into Frameworks/.
echo "==> Embedding package frameworks..."
PKGFW="$DD/Build/Products/Release/PackageFrameworks"
if [ -d "$PKGFW" ]; then
  for fw in "$PKGFW"/*.framework; do
    [ -e "$fw" ] || continue
    name=$(basename "$fw")
    if [ ! -e "$DEST/Contents/Frameworks/$name" ]; then
      cp -R "$fw" "$DEST/Contents/Frameworks/"
      echo "    embedded: $name"
    fi
  done
fi

echo "==> Applying \"$APP_NAME\" name..."
PL="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_NAME}" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${APP_NAME}" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME}" "$PL"

# Local build has no quarantine, but strip just in case.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# CRITICAL — sign with a STABLE identity, never ad-hoc.
#
# An ad-hoc signature's designated requirement is a raw cdhash, which CHANGES on
# every rebuild. macOS TCC (Accessibility / Microphone) keys its grant to that
# requirement, so after each rebuild the app shows as "enabled" in System
# Settings but still reports "permission required" — and toggling cannot fix it.
# A real certificate makes the requirement (bundle id + cert) constant across
# rebuilds, so permissions are granted ONCE.
#
# Also: sign with Fluid.release.entitlements, NOT Fluid.entitlements. The dev
# entitlements lack com.apple.security.device.audio-input; with hardened runtime
# that silently auto-denies the microphone prompt (no dialog ever appears).
#
# Frameworks first, then the outer bundle. NEVER use --deep (mangles frameworks).
SIGN_ID="${BASICS_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"')
fi
if [ -z "$SIGN_ID" ] || ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
  echo "!! No usable signing identity found."
  echo "   Add an Apple ID in Xcode > Settings > Accounts (a free account works),"
  echo "   create an Apple Development certificate, or set BASICS_SIGN_ID explicitly."
  echo "   Refusing to fall back to ad-hoc — it would break Accessibility/Microphone TCC."
  exit 1
fi
echo "==> Signing with: $SIGN_ID"
for fw in "$DEST"/Contents/Frameworks/*.framework; do
  [ -e "$fw" ] || continue
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$fw" 2>/dev/null || true
done
codesign --force --options runtime --timestamp \
  --entitlements "$REPO/Fluid.release.entitlements" --sign "$SIGN_ID" "$DEST" 2>/dev/null || true

# Sanity: the designated requirement must NOT be a bare cdhash.
if codesign -d -r- "$DEST" 2>&1 | grep -q "designated => cdhash"; then
  echo "!! WARNING: app is ad-hoc signed — Accessibility permission will break on next rebuild."
fi

# Register with Launch Services so it appears in Spotlight/Launchpad immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PL" 2>/dev/null || echo "?")
echo ""
echo "==> Done. Installed \"$APP_NAME\" (v${VER}) to /Applications."
echo "    Launch:  open -a \"$APP_NAME\""
