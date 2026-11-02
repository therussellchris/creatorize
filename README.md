# Creatorize Suite

Make explainer videos in pixel art, Vox or a style of your own, edited by pointing at the video and asking Claude.
One command installs everything: the app and every tool it needs.

## Set up with Claude Code

Have Claude Code installed and signed in? Paste this into it and it does the whole setup for you:

```
Set up Creatorize for me: https://github.com/therussellchris/creatorize
```

Already installed but broken (won't open, stays dark, an update or export keeps failing)? Paste this instead:

```
Fix Creatorize for me: https://github.com/therussellchris/creatorize
```

**Claude: your instructions are in [AGENTS.md](AGENTS.md). Read all of it before you run anything.** Download it as a
file and read every line (a summarising web fetch drops the exact commands):
`curl -fsSL -o creatorize-AGENTS.md https://raw.githubusercontent.com/therussellchris/creatorize/main/AGENTS.md`
(in Windows PowerShell type `curl.exe`).

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

## Creatorize Launcher

The installer also puts the **Creatorize Launcher** on your computer (Windows: Start menu > Creatorize Launcher; Mac:
Applications). You don't need to open it: every time Creatorize Suite starts, the launcher checks from the outside
that its window really shows. If it stays dark, the launcher asks once and restarts Creatorize in a mode that shows,
with no command and nothing to find in Settings.

Open it yourself when Creatorize won't start, or to:
- **Update** Creatorize Suite (on a Mac it installs the update for you, no dragging into Applications);
- **Go back to an earlier version** if a new one gives you trouble (your settings and projects from that version come back,
  and updates pause until you resume them);
- **Repair** everything Creatorize needs (it runs this same installer for you);
- **Copy diagnostics** or **Report a problem** when the app itself won't open.

## Window stays dark or empty?

The launcher fixes this by itself. Without the launcher, or if it doesn't help: on some graphics cards the Creatorize
window opens but stays dark. This command closes Creatorize, updates it and starts it in a mode that shows on those
computers. Your projects, settings and Skool login are not touched.

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/therussellchris/creatorize/main/rescue.ps1 | iex
```

Mac (Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/therussellchris/creatorize/main/rescue.sh | bash
```

On Windows it starts in **Safe display** (3D still runs on your graphics card, full speed). Still dark after that? Close it
and run `$env:CZ_RESCUE='software'; irm https://raw.githubusercontent.com/therussellchris/creatorize/main/rescue.ps1 | iex`
(software graphics: slower, always shows). On a Mac the rescue starts software graphics. You can switch back any time in
Settings > System > Graphics.

## What it installs

Anything you already have is skipped.

| | Windows | Mac |
|---|---|---|
| Package manager | winget (built into Windows) | Homebrew |
| git (edit history, so every change can be undone) | ✓ | ✓ |
| ffmpeg (export with sound) | ✓ | ✓ |
| Python 3 + numpy, scipy, pillow, stable-ts (audio pipeline) | ✓ | ✓ (in the app's own Python environment) |
| The app's own ffmpeg + Python 3.12 (the app downloads and checks them itself the first time it runs) | ✓ | ✓ |
| Node.js (renders the animated intros Claude edits) | ✓ | ✓ |
| Claude Code (the AI that edits your videos, using your Claude plan) | ✓ | ✓ |
| Creatorize Suite | ✓ | ✓ |
| Creatorize Launcher (fixes a window that doesn't show; update, go back, repair) | ✓ | ✓ |

It takes 5-20 minutes, mostly for the downloads. The audio tools bring PyTorch, a few hundred MB.

## Update or repair

Run the same command again. It updates Creatorize Suite if a newer version is out and puts back anything missing:
every file of the installed app is checked, and when one is missing or changed the same version is installed again.
Close Creatorize first. If you went back to an earlier version in the Creatorize Launcher, that version stays.
On Windows the app also updates itself. On a Mac it shows **Update available** when a new version is out.

When something can't be done (for example claude.ai can't be reached right now), everything else is still installed
and the end of the run lists what is left and what to do. Behind a proxy that wants a login, set `HTTPS_PROXY` to
`http://<user>:<password>@<host>:<port>` before the command.

## Manual downloads

- Windows: [latest release](https://github.com/therussellchris/creatorize-suite-releases/releases/latest)
- Mac: [latest release](https://github.com/therussellchris/creatorize-suite-mac-releases/releases/latest). The Mac
  app isn't signed with Apple yet. After dragging it into Applications, run this once in Terminal:
  `xattr -dr com.apple.quarantine "/Applications/Creatorize Suite.app"`

## Your data

Projects live in `Documents/Creatorize Suite` on your computer. Claude runs through your own Claude Code login.
Vox and custom-style videos (and Thumbnails) make their pictures on your own Higgsfield or Fal.ai account, with your
own API key (about a cent per picture): those services receive the picture prompts and any reference images. Nothing
else is uploaded.
