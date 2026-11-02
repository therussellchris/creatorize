#!/bin/bash
# Creatorize Suite installer for macOS: everything the app needs, then the app itself.
#   curl -fsSL https://raw.githubusercontent.com/therussellchris/creatorize/main/install.sh | bash
# Safe to run again: it skips what is already there, updates Creatorize Suite if a newer version is out, and repairs
# anything missing. Source: installer/install.sh in the Creatorize Suite code repo (published by scripts/publish-installer.mjs,
# after scripts/installer-test/run.mjs passed on exactly the files it publishes).
# How it ends: 0 = all set; 3 = finished, with something left for you to do (listed at the end); 1 = stopped (the reason
# is printed).
set -euo pipefail

# Everything runs inside main(), called on the last line: with `curl ... | bash` the script arrives on the same stdin the
# commands inside it can read (Homebrew installing Python swallowed part of it once, and the install silently stopped
# after Node.js). Inside a function bash has read the whole script before anything runs.
main() {

OWNER="therussellchris"
MAC_REPO="creatorize-suite-mac-releases"
APP="/Applications/Creatorize Suite.app"
SUPPORT="$HOME/Library/Application Support/Creatorize Suite"
VENV="$SUPPORT/python"
PY_PACKAGES="numpy scipy pillow stable-ts"
WIN_CMD="irm https://raw.githubusercontent.com/$OWNER/creatorize/main/install.ps1 | iex"
# CZ_INSTALL_KEEP=installed (the launcher's Repair): repair the version that is installed, never update it
KEEP=""; [ "${CZ_INSTALL_KEEP:-}" = "installed" ] && KEEP=1
# a launcher from before this installer (no CZ_INSTALL_KEEP): it reads any code but 0 as "Repair stopped" and never
# quits an open Creatorize, so for it "left to do" ends with 0 and an open app is only a warning
OLD_LAUNCHER=""; [ -n "${CZ_FROM_LAUNCHER:-}" ] && [ -z "${CZ_INSTALL_KEEP:-}" ] && OLD_LAUNCHER=1

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
ok()   { printf '    %s[ok]%s %s\n' "$green" "$off" "$1"; }
note() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }
warn() { printf '    %s[!]%s %s\n' "$yellow" "$off" "$1"; }
die()  { printf '\n%sInstall stopped:%s %s\n' "$red" "$off" "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# what is left for the member (listed at the end; the run ends with code 3)
LEFT=""; NLEFT=0
todo() { LEFT="$LEFT  - $1"$'\n'; NLEFT=$((NLEFT + 1)); warn "$1"; }
# a version the app's update gate held on this Mac (updates/held.json next to its settings, keyed by version): only the
# key "<v>": { counts, never a "current": "<v>" inside a record, and the dots match only dots
is_held() { local v; v=$(printf '%s' "$1" | sed 's/\./\\./g'); [ -f "$SUPPORT/updates/held.json" ] && grep -Eq "\"$v\"[[:space:]]*:[[:space:]]*\{" "$SUPPORT/updates/held.json"; }

# versions: prints 1 when $1 is newer, -1 when $2 is, 0 when the same. x.y.z, then a test build (0.24.0-beta.1) is
# older than 0.24.0 and newer than 0.23.x
vercmp() {
  local a1 a2 a3 b1 b2 b3 pa="" pb="" x y i
  case "$1" in *-*) pa="${1#*-}" ;; esac
  case "$2" in *-*) pb="${2#*-}" ;; esac
  IFS=. read -r a1 a2 a3 _ <<< "${1%%-*}.0.0.0"
  IFS=. read -r b1 b2 b3 _ <<< "${2%%-*}.0.0.0"
  for i in 1 2 3; do
    eval "x=\${a$i//[^0-9]/}; y=\${b$i//[^0-9]/}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then echo 1; return 0; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then echo -1; return 0; fi
  done
  if [ "$pa" = "$pb" ]; then echo 0
  elif [ -z "$pa" ]; then echo 1
  elif [ -z "$pb" ]; then echo -1
  else
    x="${pa##*[!0-9]}"; y="${pb##*[!0-9]}"
    if [ -n "$x" ] && [ -n "$y" ] && [ "${pa%"$x"}" = "${pb%"$y"}" ]; then
      if [ "$((10#$x))" -gt "$((10#$y))" ]; then echo 1; elif [ "$((10#$x))" -lt "$((10#$y))" ]; then echo -1; else echo 0; fi
    elif [[ "$pa" > "$pb" ]]; then echo 1
    else echo -1; fi
  fi
}

printf '%sCreatorize Suite installer (macOS)%s\n' "$bold" "$off"
note "Installs Homebrew, git, ffmpeg, Python + packages, Node.js, Claude Code and Creatorize Suite. Takes 5-20 minutes."

[ "$(uname -s)" = "Darwin" ] || die "this installer is for macOS. On Windows, run this in PowerShell: $WIN_CMD"
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MACOS_MAJOR" -ge 12 ] || die "Creatorize Suite needs macOS 12 (Monterey) or newer. This Mac has $(sw_vers -productVersion)."
case "$(uname -m)" in
  arm64) CHIP="arm64"; note "Apple Silicon Mac, macOS $(sw_vers -productVersion)" ;;
  x86_64) CHIP="x64"; note "Intel Mac, macOS $(sw_vers -productVersion)" ;;
  *) die "unknown Mac processor: $(uname -m)" ;;
esac
# (a proxy: curl uses HTTPS_PROXY / https_proxy / ALL_PROXY itself, http://user:password@host:port included)

# ---- Homebrew (also brings Apple's Command Line Tools, which include git) ----
step "Homebrew"
BREW=""
for b in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -n "$b" ] && [ -x "$b" ] && { BREW="$b"; break; }; done
if [ -z "$BREW" ]; then
  # run by the launcher's Repair: no Terminal to type the password into
  [ -z "${CZ_NO_TTY:-}" ] || die "Homebrew is missing, and installing it needs your Mac password once. Open Terminal and run: curl -fsSL https://raw.githubusercontent.com/$OWNER/creatorize/main/install.sh | bash"
  note "Installing Homebrew. macOS asks for your Mac login password once (typing shows nothing, that's normal)."
  sudo -v < /dev/tty || die "the password was not accepted. Run the installer again."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew did not install. Check your internet connection and run the installer again."
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && { BREW="$b"; break; }; done
  [ -n "$BREW" ] || die "Homebrew installed but brew was not found."
  ok "Homebrew installed"
else
  ok "Homebrew already installed"
fi
eval "$("$BREW" shellenv)"
# Terminal and Creatorize Suite (which reads your login shell's PATH) should see Homebrew's tools
PROFILE="$HOME/.zprofile"; [ "$(basename "${SHELL:-zsh}")" = "bash" ] && PROFILE="$HOME/.bash_profile"
LINE="eval \"\$($BREW shellenv)\""
grep -qsF "$LINE" "$PROFILE" || { printf '\n%s\n' "$LINE" >> "$PROFILE"; note "Added Homebrew to $PROFILE"; }

# ---- git, ffmpeg, Python ----
step "git, ffmpeg, Python and Node.js"
for f in git ffmpeg python@3.12 node; do
  if "$BREW" list --versions "$f" >/dev/null 2>&1; then ok "$f already installed"
  else note "Installing $f ..."; "$BREW" install --quiet "$f" || die "brew could not install $f."; ok "$f installed"; fi
done
BREW_PY="$("$BREW" --prefix python@3.12)/bin/python3.12"
[ -x "$BREW_PY" ] || die "Python 3.12 is missing after installing it ($BREW_PY)."

# ---- Python packages (the Suite's own environment; Homebrew's Python refuses system-wide installs) ----
step "Python packages for the audio pipeline"
runs() { "$VENV/bin/python3" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)' >/dev/null 2>&1; }
# (made only when there is none: an environment whose Python link broke is repaired below, not made over it)
if [ ! -d "$VENV/bin" ]; then mkdir -p "$SUPPORT"; "$BREW_PY" -m venv "$VENV" || die "could not create the Python environment in $VENV"; fi
# a `brew upgrade` / `brew cleanup` can take the Python this environment was made with: it is pointed at today's
# python@3.12 (packages kept), else made again from scratch (packages reinstalled below). Before, the check below
# failed under `set -e` and the installer stopped without a word.
if ! runs; then
  note "The Python environment no longer runs (Homebrew updated its Python): repairing it ..."
  "$BREW_PY" -m venv --upgrade "$VENV" >/dev/null 2>&1 || true
  runs || { "$BREW_PY" -m venv --clear "$VENV" || die "could not make the Python environment again in $VENV"; }
  runs || die "the Python environment in $VENV does not run, even made again. Run: $BREW reinstall python@3.12, then this installer again."
  ok "Python environment repaired"
fi
pkgs_missing() {
  "$VENV/bin/python3" - <<'PY'
import importlib.util as u
want = {"numpy": "numpy", "scipy": "scipy", "PIL": "pillow", "stable_whisper": "stable-ts"}
print(" ".join(p for m, p in want.items() if u.find_spec(m) is None))
PY
}
MISSING=$(pkgs_missing) || die "the check of the Python packages could not run ($VENV/bin/python3). Run the installer again."
if [ -n "$MISSING" ]; then
  note "Installing $MISSING (stable-ts brings PyTorch, a few hundred MB) ..."
  "$VENV/bin/python3" -m pip install --quiet --upgrade pip >/dev/null || true
  "$VENV/bin/python3" -m pip install --quiet --no-cache-dir --upgrade $MISSING || true
  AFTER=$(pkgs_missing || echo "$MISSING")
  if [ -n "$AFTER" ]; then todo "pip could not install: $AFTER (internet connection, a proxy or the disk full?). Transcription and the audio steps need them: run the installer again, or Repair in the Creatorize Launcher."
  else ok "Python packages installed"; fi
else
  ok "Python packages already installed"
fi

# ---- Claude Code: a warning when it can't be installed (claude.ai blocked, a Wi-Fi login page): the app still installs ----
step "Claude Code"
if have claude || [ -x "$HOME/.local/bin/claude" ]; then ok "Claude Code already installed"
else
  note "Installing Claude Code ..."
  CS=$(curl -fsSL https://claude.ai/install.sh 2>/dev/null || true)
  case "$CS" in
    "") todo "Claude Code did not install: claude.ai could not be reached. Creatorize Suite is installed anyway and needs Claude Code to make videos: run this installer again once https://claude.ai opens in your browser." ;;
    *"<html"*|*"<HTML"*|"<"*) todo "Claude Code did not install: claude.ai sent a web page instead of its installer (a network that wants you to log in first, like hotel or office Wi-Fi, or a web filter). Creatorize Suite is installed anyway: run this installer again once https://claude.ai opens in your browser." ;;
    *) if printf '%s\n' "$CS" | bash && { have claude || [ -x "$HOME/.local/bin/claude" ]; }; then ok "Claude Code installed"
       else todo "Claude Code did not install. Creatorize Suite is installed anyway and needs Claude Code to make videos: run this installer again."; fi ;;
  esac
fi

# ---- Creatorize Suite: the newest version (or, when updates are paused / the launcher repairs, the installed one), with
# every file checked against the app's own list (files.json); anything missing = that exact version copied in again ----
step "Creatorize Suite"
if [ -n "${CZ_SKIP_APP:-}" ]; then note "(test: CZ_SKIP_APP set, app step skipped)"; else
RELEASES="https://github.com/$OWNER/$MAC_REPO/releases"
CURRENT=""
[ -d "$APP" ] && CURRENT=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
# files of an app that are missing or not at their size (the same check as the launcher's, releases.ts verifyBundle);
# "NOLIST" = an older version without files.json: only its main files
app_bad() {
  "$BREW_PY" - "$1/Contents/Resources" <<'PY'
import json, os, sys
res = sys.argv[1]
if not os.path.isfile(os.path.join(res, "app.asar")): print("app.asar")
try:
    m = json.load(open(os.path.join(res, "files.json"), encoding="utf-8"))
except Exception:
    # a version from before files.json (2026-10-27): its main files only (Stick stories came in 0.17.0)
    for must in ("templates/stickstory/engine.js", "templates/stickstory/models.js"):
        if os.path.isdir(os.path.join(res, "templates", "stickstory")) and not os.path.isfile(os.path.join(res, *must.split("/"))): print(must)
    print("NOLIST"); sys.exit(0)
for f in m.get("files", []):
    try:
        if os.path.getsize(os.path.join(res, *f["path"].split("/"))) != f["size"]: print(f["path"])
    except OSError:
        print(f["path"])
PY
}
BAD=""; NOLIST=""
if [ -n "$CURRENT" ]; then
  BAD=$(app_bad "$APP" || echo "app.asar")
  case "$BAD" in *NOLIST*) NOLIST=1; BAD=$(printf '%s\n' "$BAD" | grep -v '^NOLIST$' || true) ;; esac
fi
NBAD=0; [ -n "$BAD" ] && NBAD=$(printf '%s\n' "$BAD" | grep -c .)
# after Go back the launcher keeps updates paused (its updates-paused.json, the CZ_NO_UPDATE setting)
PAUSED=""; PJ="$HOME/Library/Application Support/Creatorize Launcher/updates-paused.json"
if [ -f "$PJ" ]; then PAUSED=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PJ" | head -1); [ -n "$PAUSED" ] || PAUSED="?"; fi
[ -z "$PAUSED" ] && [ -n "${CZ_NO_UPDATE:-}" ] && PAUSED="?"
LATEST=""; HELDV=""
if [ -n "$CURRENT" ] && { [ -n "$KEEP" ] || [ -n "$PAUSED" ]; }; then TARGET="$CURRENT"
elif [ -z "$CURRENT" ] && [ -n "$PAUSED" ] && [ "$PAUSED" != "?" ]; then TARGET="$PAUSED"
else
  # github.com's own "latest release" redirect, not the API (which allows 60 requests an hour per network)
  LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$RELEASES/latest" 2>/dev/null || true)
  case "$LATEST_URL" in
    */releases/tag/v*) LATEST="${LATEST_URL##*/tag/v}" ;;
    *) if curl -fsSI -o /dev/null https://github.com 2>/dev/null; then
         warn "The Mac version of Creatorize Suite isn't published yet. Everything it needs is installed now: run this command again once it's out."
         if [ "$NLEFT" -gt 0 ]; then printf '\n%s' "$LEFT"; [ -n "$OLD_LAUNCHER" ] || exit 3; fi
         exit 0
       fi
       die "could not reach GitHub ($RELEASES). Check your internet connection and run the installer again." ;;
  esac
  TARGET="$LATEST"
  if [ -n "$CURRENT" ] && [ "$(vercmp "$CURRENT" "$LATEST")" != "-1" ]; then TARGET="$CURRENT"; fi
  # a version the update gate tested on this Mac and did not install (the app's updates/held.json): a re-run of this
  # installer or Repair keeps the installed one instead of installing it untested (Fable review 2, P2-1)
  if [ -n "$CURRENT" ] && [ "$TARGET" != "$CURRENT" ] && [ -f "$SUPPORT/updates/held.json" ] && is_held "$TARGET"; then HELDV="$TARGET"; TARGET="$CURRENT"; fi
fi
if [ -n "$CURRENT" ] && [ "$TARGET" = "$CURRENT" ] && [ "$NBAD" = 0 ]; then
  if [ -n "$HELDV" ]; then ok "Creatorize Suite $CURRENT is complete. $HELDV didn't pass its test on this Mac, so it wasn't installed; a newer version is tested again by itself."
  elif [ -n "$PAUSED" ]; then ok "Creatorize Suite $CURRENT is complete. Updates are paused (you went back to it in the Creatorize Launcher): press Resume updates there to get newer versions."
  elif [ -n "$LATEST" ] && [ "$(vercmp "$CURRENT" "$LATEST")" = "1" ]; then ok "Creatorize Suite $CURRENT is installed (a test version, newer than $LATEST) and complete"
  elif [ -n "$KEEP" ]; then ok "Creatorize Suite $CURRENT is complete (every file checked)"
  else ok "Creatorize Suite $CURRENT is up to date"; fi
  [ -z "$NOLIST" ] || note "(this version has no list of its files, so only its main files were checked)"
else
  if [ -z "$CURRENT" ]; then WHAT="install Creatorize Suite $TARGET"
  elif [ "$TARGET" = "$CURRENT" ]; then WHAT="put back the missing files of Creatorize Suite $CURRENT"
  else WHAT="update Creatorize Suite $CURRENT to $TARGET"; fi
  if [ -n "$CURRENT" ] && [ "$TARGET" = "$CURRENT" ]; then warn "$NBAD file(s) of Creatorize Suite $CURRENT are missing or incomplete ($(printf '%s\n' "$BAD" | head -3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')): copying $CURRENT in again"; fi
  if pgrep -xq "Creatorize Suite"; then
    [ -z "${CZ_FROM_LAUNCHER:-}" ] || [ -n "$OLD_LAUNCHER" ] || die "Creatorize Suite is open, so the launcher could not $WHAT. Quit Creatorize Suite (Cmd+Q) and press Repair again."
    todo "Creatorize Suite $CURRENT is open, so the installer did not $WHAT. Quit it (Cmd+Q) and run the installer again."
  else
  URL="$RELEASES/download/v$TARGET/Creatorize-Suite-$TARGET-Mac-$CHIP.dmg"   # name set in .github/workflows/mac-build.yml
  if [ -n "$KEEP" ] && [ -z "$PAUSED" ] && ! curl -fsSLI -o /dev/null "$URL" 2>/dev/null; then
    # the launcher's Repair, and this version is no longer published (pulled): the newest one instead
    LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$RELEASES/latest" 2>/dev/null || true)
    case "$LATEST_URL" in */releases/tag/v*) warn "Creatorize Suite $TARGET is not published any more: installing the newest version instead"; TARGET="${LATEST_URL##*/tag/v}"; URL="$RELEASES/download/v$TARGET/Creatorize-Suite-$TARGET-Mac-$CHIP.dmg" ;; esac
    # (never a version the update gate held on this Mac, here either: Fable review 2, pass 3, P3-2)
    if is_held "$TARGET"; then todo "the newest version, $TARGET, didn't pass its test on this Mac, so it wasn't installed; Creatorize Suite $CURRENT stays as it is. A newer version is tested again by itself."; printf '\n%s' "$LEFT"; [ -n "$OLD_LAUNCHER" ] || exit 3; exit 0; fi
  fi
  note "Downloading Creatorize Suite $TARGET ..."
  TMP=$(mktemp -d); trap 'hdiutil detach -quiet "$TMP/mnt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
  curl -fL --progress-bar -o "$TMP/suite.dmg" "$URL" || die "the download failed ($URL). Nothing was changed: check the internet connection and run the installer again."
  # (a .dmg carries its own checksums: one damaged on the way does not open)
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/suite.dmg" || die "the download of Creatorize Suite $TARGET was damaged on the way (it does not open). Nothing was changed: run the installer again."
  [ -d "$TMP/mnt/Creatorize Suite.app" ] || die "the installer does not contain Creatorize Suite.app."
  # copied next to the app first, checked, then swapped: a half copy (or a leftover .new from an update that stopped)
  # never becomes the app (that once left New project saying the Stick stories files were missing)
  NEW="$APP.new"; OLD="$APP.old"
  pkill -f "ditto .*Creatorize Suite.app.new" 2>/dev/null || true
  chmod -R u+w "$NEW" 2>/dev/null || true; rm -rf "$NEW" 2>/dev/null || true
  [ -e "$NEW" ] && mv "$NEW" "$NEW.trash-$$" 2>/dev/null
  ditto "$TMP/mnt/Creatorize Suite.app" "$NEW" || die "could not copy the app into Applications."
  hdiutil detach -quiet "$TMP/mnt" || true
  NEWVER=$(defaults read "$NEW/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
  NB=$(app_bad "$NEW" || echo "app.asar")
  # (a version from before files.json, 0.19.2 and older: its main files; from 0.20.0 on its files.json must be there)
  case "$NB" in *NOLIST*) if [ "$(vercmp "$TARGET" 0.20.0)" != "-1" ]; then NB="files.json"; else NB=$(printf '%s\n' "$NB" | grep -v '^NOLIST$' || true); fi ;; esac
  [ -z "$NB" ] || { rm -rf "$NEW"; die "the copy of Creatorize Suite is incomplete ($(printf '%s\n' "$NB" | head -1)). Your current app was not changed: restart the Mac and run the installer again."; }
  [ "$NEWVER" = "$TARGET" ] || { rm -rf "$NEW"; die "the copied app says version '$NEWVER', not $TARGET. Your current app was not changed: run the installer again."; }
  xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true      # the app isn't signed with Apple yet
  rm -rf "$OLD" 2>/dev/null || true
  if [ -e "$APP" ]; then mv "$APP" "$OLD" || die "could not move the old app aside (is Creatorize Suite still open?)."; fi
  mv "$NEW" "$APP" || { [ -e "$OLD" ] && mv "$OLD" "$APP"; die "could not put the new app in place; the old one is back."; }
  rm -rf "$OLD" "$APP".new.trash-* 2>/dev/null || true
  if [ "$CURRENT" = "$TARGET" ]; then ok "Creatorize Suite $TARGET copied in again, every file checked"
  else ok "Creatorize Suite $TARGET installed in Applications${CURRENT:+ (was $CURRENT)}"; fi
  fi
fi
fi

# ---- Creatorize Launcher: watches every start and fixes a window that doesn't show; updates, goes back, repairs ----
step "Creatorize Launcher"
LAPP="/Applications/Creatorize Launcher.app"
if [ -n "${CZ_FROM_LAUNCHER:-}" ]; then ok "the launcher is running this repair, so it stays as it is"
elif [ -n "${CZ_SKIP_APP:-}" ]; then note "(test: CZ_SKIP_APP set, launcher step skipped)"
else
  LJ=$(curl -fsSL "https://github.com/$OWNER/creatorize/releases/latest/download/launcher.json" 2>/dev/null || true)
  LVER=$(printf '%s\n' "$LJ" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
  if [ "$CHIP" = "arm64" ]; then LKEY="macArm64"; else LKEY="macX64"; fi
  LZIP=$(printf '%s\n' "$LJ" | sed -n "s/.*\"$LKEY\": *\"\\([^\"]*\\)\".*/\\1/p" | head -1)
  LCUR=""; [ -d "$LAPP" ] && LCUR=$(defaults read "$LAPP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
  if [ -z "$LVER" ] || [ -z "$LZIP" ]; then
    if [ -n "$LCUR" ]; then ok "Creatorize Launcher $LCUR is installed"; else note "not published yet: Creatorize Suite installs it by itself later"; fi
  elif [ "$LCUR" = "$LVER" ]; then ok "Creatorize Launcher $LCUR is up to date"
  elif pgrep -fq "Creatorize Launcher.app/Contents/MacOS"; then warn "the launcher is open, so it was not updated: it updates itself later"   # (-x matches only 16 characters of a name)
  else
    LTMP=$(mktemp -d)
    if curl -fsSL -o "$LTMP/l.zip" "https://github.com/$OWNER/creatorize/releases/latest/download/$LZIP" && ditto -x -k "$LTMP/l.zip" "$LTMP/x" && [ -d "$LTMP/x/Creatorize Launcher.app" ]; then
      # copied next to the old one first, checked, then swapped (the same way as the app above and the launcher's own
      # update, src/shared/bundleSwap.ts): a copy that fails or is cut off never leaves the member without a launcher
      LNEW="$LAPP.new"; LOLD="$LAPP.trash-$$"
      chmod -R u+w "$LNEW" 2>/dev/null || true; rm -rf "$LNEW" 2>/dev/null || true
      [ -e "$LNEW" ] && mv "$LNEW" "$LAPP.trash-new-$$" 2>/dev/null
      if ditto "$LTMP/x/Creatorize Launcher.app" "$LNEW" \
         && [ -x "$LNEW/Contents/MacOS/Creatorize Launcher" ] && [ -s "$LNEW/Contents/Resources/app.asar" ] \
         && [ "$(defaults read "$LNEW/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)" = "$LVER" ]; then
        xattr -dr com.apple.quarantine "$LNEW" 2>/dev/null || true      # not signed with Apple yet, like the app
        if [ -e "$LAPP" ]; then mv "$LAPP" "$LOLD" || true; fi
        if [ ! -e "$LAPP" ] && mv "$LNEW" "$LAPP"; then
          ok "Creatorize Launcher $LVER installed in Applications"
        else
          { [ ! -e "$LAPP" ] && [ -e "$LOLD" ] && mv "$LOLD" "$LAPP"; } || true
          warn "the launcher could not be put in place; the one you had stays. Creatorize Suite tries again by itself later"
        fi
        chmod -R u+w "$LOLD" 2>/dev/null || true; rm -rf "$LOLD" "$LAPP".trash-* "$LNEW" 2>/dev/null || true
      else
        rm -rf "$LNEW" 2>/dev/null || true
        warn "the launcher could not be copied into Applications (the one you had stays); Creatorize Suite tries again by itself later"
      fi
    else warn "the launcher did not download; Creatorize Suite tries again by itself later"; fi
    rm -rf "$LTMP"
  fi
fi

step "Done"
note "Your projects will live in ~/Documents/Creatorize Suite."
if [ -z "${CZ_NO_OPEN:-}" ] && [ -d "$APP" ] && ! pgrep -xq "Creatorize Suite"; then open "$APP"; ok "Opening Creatorize Suite: log in with your Skool account, then sign in with Claude on the Home page."; fi
if [ "$NLEFT" -gt 0 ]; then
  printf '\n%sFinished, with %s thing(s) left to do:%s\n%s' "$yellow" "$NLEFT" "$off" "$LEFT"
  printf '%sRun the same command again any time to update or repair.%s\n' "$bold" "$off"
  [ -n "$OLD_LAUNCHER" ] || exit 3
  exit 0
fi
printf '\n%sAll set.%s Run the same command again any time to update or repair.\n' "$bold" "$off"
}

main "$@"
# CZ-INSTALLER-END (the Creatorize Launcher's Repair runs a fetched copy only when this last line arrived)
