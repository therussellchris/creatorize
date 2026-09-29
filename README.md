# Creatorize Suite

Make explainer videos in pixel-art or Vox editorial style, edited by pointing at the video and asking Claude.
One command installs everything: the app and every tool it needs.

## Install

### Windows 10 / 11

Open **PowerShell** (Start menu, type `PowerShell`, press Enter) and paste:

```powershell
irm https://raw.githubusercontent.com/therussellchris/creatorize/main/install.ps1 | iex
```

### Mac (macOS 12 or newer, Apple Silicon or Intel)

Open **Terminal** (press Cmd + Space, type `Terminal`, press Enter) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/therussellchris/creatorize/main/install.sh | bash
```

On a Mac without Homebrew, it asks for your Mac login password once. Nothing shows while you type it; that's normal.

When it's done, Creatorize Suite opens. Click **Sign in** on the Home page to connect your Claude account.

## What it installs

Anything you already have is skipped.

| | Windows | Mac |
|---|---|---|
| Package manager | winget (built into Windows) | Homebrew |
| git (edit history, so every change can be undone) | ✓ | ✓ |
| ffmpeg (export with sound) | ✓ | ✓ |
| Python 3 + numpy, scipy, pillow, stable-ts (audio pipeline) | ✓ | ✓ (in the app's own Python environment) |
| Node.js (renders the animated intros Claude edits) | ✓ | ✓ |
| Claude Code (the AI that edits your videos, using your Claude plan) | ✓ | ✓ |
| Creatorize Suite | ✓ | ✓ |

It takes 5-20 minutes, mostly for the downloads. The audio tools bring PyTorch, a few hundred MB.

## Update or repair

Run the same command again. It updates Creatorize Suite if a newer version is out and puts back anything missing.
On Windows the app also updates itself. On a Mac it shows **Update available** when a new version is out.

## Manual downloads

- Windows: [latest release](https://github.com/therussellchris/creatorize-suite-releases/releases/latest)
- Mac: [latest release](https://github.com/therussellchris/creatorize-suite-mac-releases/releases/latest). The Mac
  app isn't signed with Apple yet. After dragging it into Applications, run this once in Terminal:
  `xattr -dr com.apple.quarantine "/Applications/Creatorize Suite.app"`

## Your data

Projects live in `Documents/Creatorize Suite` on your computer. Claude runs through your own Claude Code login.
Nothing is uploaded anywhere else.
