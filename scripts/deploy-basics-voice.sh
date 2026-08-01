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
#   scripts/deploy-basics-voice.sh --check     # report how far behind upstream, install nothing
#   scripts/deploy-basics-voice.sh --update    # rebase your work onto upstream, then build + install
#
# Environment overrides:
#   BASICS_APP_NAME         App name to install as    (default: Basics Voice)
#   BASICS_SIGN_ID          codesign identity to use  (default: first "Apple Development" in keychain)
#   BASICS_UPSTREAM_REMOTE  remote holding new releases (default: upstream)
#   BASICS_UPSTREAM_BRANCH  branch on that remote       (default: main)
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

# Where new FluidVoice releases actually come from. This fork lives on `origin`
# (your own copy); new upstream versions land on `upstream`. A bare
# `git pull --rebase` is wrong here: on a feature branch with no tracking branch
# it fails outright, and when it does work it pulls your own fork, not upstream.
UPSTREAM_REMOTE="${BASICS_UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${BASICS_UPSTREAM_BRANCH:-main}"
UPSTREAM_REF="$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"

upstream_status() {
  git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 || {
    echo "!! No '$UPSTREAM_REMOTE' remote. Add it with:"
    echo "   git remote add $UPSTREAM_REMOTE https://github.com/altic-dev/FluidVoice.git"
    return 1
  }
  git fetch --quiet --tags "$UPSTREAM_REMOTE" || return 1
  local behind ahead
  behind=$(git rev-list --count "HEAD..$UPSTREAM_REF")
  ahead=$(git rev-list --count "$UPSTREAM_REF..HEAD")
  echo "    branch:   $(git rev-parse --abbrev-ref HEAD)"
  echo "    upstream: $UPSTREAM_REF ($(git describe --tags --abbrev=0 "$UPSTREAM_REF" 2>/dev/null || echo 'no tag'))"
  echo "    behind upstream by $behind commit(s); your own work: $ahead commit(s)"
  return 0
}

if [[ "${1:-}" == "--check" ]]; then
  echo "==> Update check"
  upstream_status || exit 1
  INSTALLED_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$DEST/Contents/Info.plist" 2>/dev/null || echo "not installed")
  echo "    installed $APP_NAME: v${INSTALLED_VER}"
  exit 0
fi

if [[ "${1:-}" == "--update" ]]; then
  echo "==> Checking for upstream updates..."
  upstream_status || exit 1

  # Refuse to rebase over uncommitted work — a mid-rebase conflict on a dirty
  # tree is how you lose changes.
  if [ -n "$(git status --porcelain)" ]; then
    echo "!! Working tree is dirty. Commit or stash first, then re-run --update."
    git status --short
    exit 1
  fi
  if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
    echo "!! A rebase is already in progress. Finish it (git rebase --continue)"
    echo "   or abandon it (git rebase --abort), then re-run."
    exit 1
  fi

  if [ "$(git rev-list --count "HEAD..$UPSTREAM_REF")" -eq 0 ]; then
    echo "    Already up to date with $UPSTREAM_REF — building current source."
  else
    BACKUP="backup/pre-update-$(date +%Y%m%d-%H%M%S)"
    git branch "$BACKUP" >/dev/null
    echo "==> Safety branch: $BACKUP (git reset --hard $BACKUP to undo)"
    echo "==> Rebasing your commits onto $UPSTREAM_REF ..."
    if ! git rebase "$UPSTREAM_REF"; then
      echo ""
      echo "!! Rebase hit a conflict. Nothing was installed; the app on disk still works."
      echo "   Conflicted files:"
      git diff --name-only --diff-filter=U | sed 's/^/     /'
      echo "   Resolve them, then: git add <files> && git rebase --continue && $0"
      echo "   Or back out entirely: git rebase --abort"
      exit 1
    fi
    echo "    Rebase clean. Your work is now on top of $UPSTREAM_REF."
  fi
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
