#!/bin/bash
# Creatorize Suite rescue for macOS: for a Creatorize window that stays dark or empty (or won't open at all).
#   curl -fsSL https://get.creatorize.io/rescue.sh | bash
# Quits Creatorize Suite, updates it if a newer version is out, then starts it with software graphics (the window always
# shows; 3D previews and exports are slower: switch back in Settings > System > Graphics once your Mac is updated).
# Projects, settings and the Skool login are not touched.
# Source: installer/rescue.sh in the Creatorize Suite code repo (published by scripts/publish-installer.mjs).
set -euo pipefail

main() {
OWNER="therussellchris"
MAC_REPO="creatorize-suite-mac-releases"
APP="/Applications/Creatorize Suite.app"
# Creatorize's own download server first; the same file on GitHub only when it gives no answer, while GitHub is the fallback
CF="https://get.creatorize.io"
GH_FALLBACK=1
DRY="${CZ_INSTALL_DRY:-}"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
ok()   { printf '    %s[ok]%s %s\n' "$green" "$off" "$1"; }
note() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }
warn() { printf '    %s[!]%s %s\n' "$yellow" "$off" "$1"; }
die()  { printf '\n%sRescue stopped:%s %s\n' "$red" "$off" "$1" >&2; exit 1; }
# a release file of the Mac app: the download server's address, else GitHub's (the same path)
gh_url() { printf 'https://github.com/%s/%s' "$OWNER" "$1"; }
# the newest full release's version and the sha256 of this Mac's .dmg (its update-manifest.json), else github.com's
# "latest release" redirect (version only)
latest_manifest() {
  local t
  if t=$(curl -fsSL --max-time 20 "$CF/$MAC_REPO/releases/latest/download/update-manifest.json" 2>/dev/null); then printf '%s' "$t"; return 0; fi
  [ -n "$GH_FALLBACK" ] && curl -fsSL --max-time 20 "$(gh_url "$MAC_REPO/releases/latest/download/update-manifest.json")" 2>/dev/null || true
}
# 1 when version $1 is older than $2 (plain x.y.z)
older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "${1%%-*}" "${2%%-*}" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "${1%%-*}" ]; }

printf '%sCreatorize Suite rescue (macOS)%s\n' "$bold" "$off"
note "Your projects, settings and Skool login stay as they are."
[ -n "$DRY" ] && warn "Test mode (CZ_INSTALL_DRY): nothing is closed, installed or changed."
if [ ! -d "$APP" ] && [ -z "$DRY" ]; then
  die "Creatorize Suite is not installed in Applications. Install it with:  curl -fsSL $CF/install.sh | bash"
fi

step "Quitting Creatorize Suite"
if ! pgrep -xq "Creatorize Suite"; then ok "it was not running"
elif [ -n "$DRY" ]; then note "(test mode) would quit Creatorize Suite"
else
  pkill -x "Creatorize Suite" || true
  for _ in $(seq 1 20); do pgrep -xq "Creatorize Suite" || break; sleep 0.5; done
  pgrep -xq "Creatorize Suite" && pkill -9 -x "Creatorize Suite" || true
  ok "closed"
fi

step "Updating Creatorize Suite"
case "$(uname -m)" in arm64) CHIP="arm64" ;; *) CHIP="x64" ;; esac
CURRENT=""
[ -d "$APP" ] && CURRENT=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
MF=$(latest_manifest)
LATEST=$(printf '%s\n' "$MF" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9A-Za-z.-]*\)".*/\1/p' | head -1 || true)
if [ -z "$LATEST" ] && [ -n "$GH_FALLBACK" ]; then
  LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$(gh_url "$MAC_REPO/releases/latest")" 2>/dev/null || true)
  case "$LATEST_URL" in */releases/tag/v*) LATEST="${LATEST_URL##*/tag/v}" ;; esac
fi
[ -n "$LATEST" ] || warn "could not reach the Creatorize Suite releases, so it was not updated (it is started anyway)"
if [ -n "$LATEST" ]; then
  if [ -n "$CURRENT" ] && ! older "$CURRENT" "$LATEST"; then ok "Creatorize Suite $CURRENT is up to date"
  elif [ -n "$DRY" ]; then note "(test mode) would install Creatorize Suite $LATEST (installed: ${CURRENT:-none})"
  else
    DMG="Creatorize-Suite-$LATEST-Mac-$CHIP.dmg"   # name set in .github/workflows/mac-build.yml
    REL="$MAC_REPO/releases/download/v$LATEST/$DMG"
    # its sha256 from the manifest (when the manifest was this version's): a download that differs is never opened
    WANT_SHA=""
    case "$MF" in *"\"$DMG\""*) WANT_SHA=$(printf '%s' "$MF" | tr -d '\n\r' | sed -n "s/.*\"$(printf '%s' "$DMG" | sed 's/[.]/[.]/g')\"[[:space:]]*:[[:space:]]*{[^}]*\"sha256\"[[:space:]]*:[[:space:]]*\"\([0-9a-f]\{64\}\)\".*/\1/p" | head -1 || true) ;; esac
    note "Downloading Creatorize Suite $LATEST ..."
    TMP=$(mktemp -d); trap 'hdiutil detach -quiet "$TMP/mnt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
    GOT=0
    curl -fL --progress-bar -o "$TMP/suite.dmg" "$CF/$REL" && GOT=1
    if [ "$GOT" = 0 ] && [ -n "$GH_FALLBACK" ]; then rm -f "$TMP/suite.dmg"; curl -fL --progress-bar -o "$TMP/suite.dmg" "$(gh_url "$REL")" && GOT=1; fi
    if [ "$GOT" = 1 ] && [ -n "$WANT_SHA" ] && [ "$(shasum -a 256 "$TMP/suite.dmg" | cut -d' ' -f1)" != "$WANT_SHA" ]; then GOT=0; warn "the download was damaged on the way (it did not match the release), so it was not opened"; fi
    if [ "$GOT" = 1 ] && hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/suite.dmg" && [ -d "$TMP/mnt/Creatorize Suite.app" ]; then
      rm -rf "$APP"
      ditto "$TMP/mnt/Creatorize Suite.app" "$APP" || die "could not copy the app into Applications."
      hdiutil detach -quiet "$TMP/mnt" || true
      xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
      CURRENT="$LATEST"; ok "Creatorize Suite $LATEST installed"
    else warn "the update did not finish; starting the installed version"; fi
  fi
fi

step "Starting Creatorize Suite"
# software graphics (--software-graphics) exists from 0.15.0
if [ -n "$CURRENT" ] && older "$CURRENT" "0.15.0"; then
  warn "this version ($CURRENT) is too old for the rescue start: run this again when you are online to update it"
  [ -z "$DRY" ] && open "$APP"
else
  if [ -n "$DRY" ]; then note "(test mode) would start Creatorize Suite --software-graphics"
  else open -a "$APP" --args --software-graphics; ok "Started in software graphics (switch back in Settings > System > Graphics)"; fi
fi
printf '\n%sDone.%s Still not showing? Ask in the community and include a screenshot.\n' "$bold" "$off"
}

main "$@"
