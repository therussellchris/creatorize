#!/bin/bash
# Creatorize Suite installer for macOS: everything the app needs, then the app itself.
#   curl -fsSL https://raw.githubusercontent.com/therussellchris/creatorize/main/install.sh | bash
# Safe to run again: it skips what is already there, updates Creatorize Suite if a newer version is out, and repairs
# anything missing. Source: installer/install.sh in the Creatorize Suite code repo (published by scripts/publish-installer.mjs).
set -euo pipefail

OWNER="therussellchris"
MAC_REPO="creatorize-suite-mac-releases"
APP="/Applications/Creatorize Suite.app"
SUPPORT="$HOME/Library/Application Support/Creatorize Suite"
VENV="$SUPPORT/python"
PY_PACKAGES="numpy scipy pillow stable-ts"
WIN_CMD="irm https://raw.githubusercontent.com/$OWNER/creatorize/main/install.ps1 | iex"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
ok()   { printf '    %s[ok]%s %s\n' "$green" "$off" "$1"; }
note() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }
warn() { printf '    %s[!]%s %s\n' "$yellow" "$off" "$1"; }
die()  { printf '\n%sInstall stopped:%s %s\n' "$red" "$off" "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

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

# ---- Homebrew (also brings Apple's Command Line Tools, which include git) ----
step "Homebrew"
BREW=""
for b in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -n "$b" ] && [ -x "$b" ] && { BREW="$b"; break; }; done
if [ -z "$BREW" ]; then
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
if [ ! -x "$VENV/bin/python3" ]; then mkdir -p "$SUPPORT"; "$BREW_PY" -m venv "$VENV" || die "could not create the Python environment in $VENV"; fi
MISSING=$("$VENV/bin/python3" - <<'PY'
import importlib.util as u
want = {"numpy": "numpy", "scipy": "scipy", "PIL": "pillow", "stable_whisper": "stable-ts"}
print(" ".join(p for m, p in want.items() if u.find_spec(m) is None))
PY
)
if [ -n "$MISSING" ]; then
  note "Installing $MISSING (stable-ts brings PyTorch, a few hundred MB) ..."
  "$VENV/bin/python3" -m pip install --quiet --upgrade pip >/dev/null
  "$VENV/bin/python3" -m pip install --quiet --upgrade $MISSING || die "pip could not install: $MISSING"
  ok "Python packages installed"
else
  ok "Python packages already installed"
fi

# ---- Claude Code ----
step "Claude Code"
if have claude || [ -x "$HOME/.local/bin/claude" ]; then ok "Claude Code already installed"
else
  note "Installing Claude Code ..."
  curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code did not install. Check your internet connection and run the installer again."
  ok "Claude Code installed"
fi

# ---- Creatorize Suite ----
step "Creatorize Suite"
if [ -n "${CZ_SKIP_APP:-}" ]; then note "(test: CZ_SKIP_APP set, app step skipped)"; else
# github.com's own "latest release" redirect, not the API (which allows 60 requests an hour per network)
RELEASES="https://github.com/$OWNER/$MAC_REPO/releases"
LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$RELEASES/latest" 2>/dev/null || true)
case "$LATEST_URL" in
  */releases/tag/v*) TAG="${LATEST_URL##*/tag/}" ;;
  *) if curl -fsSI -o /dev/null https://github.com 2>/dev/null; then
       warn "The Mac version of Creatorize Suite isn't published yet. Everything it needs is installed now: run this command again once it's out."
       exit 0
     fi
     die "could not reach GitHub ($RELEASES). Check your internet connection and run the installer again." ;;
esac
LATEST="${TAG#v}"
URL="$RELEASES/download/$TAG/Creatorize-Suite-$LATEST-Mac-$CHIP.dmg"   # name set in .github/workflows/mac-build.yml
CURRENT=""
[ -d "$APP" ] && CURRENT=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
if [ "$CURRENT" = "$LATEST" ]; then
  ok "Creatorize Suite $CURRENT is up to date"
elif pgrep -xq "Creatorize Suite"; then
  warn "Creatorize Suite $CURRENT is open, so it was not replaced with $LATEST. Quit it (Cmd+Q) and run the installer again."
else
  note "Downloading Creatorize Suite $LATEST ..."
  TMP=$(mktemp -d); trap 'hdiutil detach -quiet "$TMP/mnt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
  curl -fL --progress-bar -o "$TMP/suite.dmg" "$URL" || die "the download failed ($URL)."
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/suite.dmg" || die "could not open the downloaded installer."
  [ -d "$TMP/mnt/Creatorize Suite.app" ] || die "the installer does not contain Creatorize Suite.app."
  rm -rf "$APP"
  ditto "$TMP/mnt/Creatorize Suite.app" "$APP" || die "could not copy the app into Applications."
  hdiutil detach -quiet "$TMP/mnt" || true
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true      # the app isn't signed with Apple yet
  ok "Creatorize Suite $LATEST installed in Applications${CURRENT:+ (was $CURRENT)}"
fi
fi

step "Done"
note "Your projects will live in ~/Documents/Creatorize Suite."
if [ -z "${CZ_NO_OPEN:-}" ] && [ -d "$APP" ] && ! pgrep -xq "Creatorize Suite"; then open "$APP"; ok "Opening Creatorize Suite: sign in with Claude on the Home page."; fi
printf '\n%sAll set.%s Run the same command again any time to update or repair.\n' "$bold" "$off"
