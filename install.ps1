# Creatorize Suite installer for Windows: everything the app needs, then the app itself.
#   irm https://raw.githubusercontent.com/therussellchris/creatorize/main/install.ps1 | iex
# Safe to run again: it skips what is already there, updates Creatorize Suite if a newer version is out, and repairs
# anything missing. Source: installer/install.ps1 in the Creatorize Suite code repo (published by scripts/publish-installer.mjs).
# Keep this file plain ASCII: Windows PowerShell 5.1 runs it through `irm | iex`.

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Owner = 'therussellchris'
$Repo = 'creatorize-suite-releases'
$AppDir = Join-Path $env:LOCALAPPDATA 'Programs\creatorize-suite'
$AppExe = Join-Path $AppDir 'Creatorize Suite.exe'
$MacCmd = "curl -fsSL https://raw.githubusercontent.com/$Owner/creatorize/main/install.sh | bash"
$DryRun = [bool]$env:CZ_INSTALL_DRY    # test mode: detect and report, change nothing

function Step($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor White }
function Ok($t) { Write-Host "    [ok] $t" -ForegroundColor Green }
function Note($t) { Write-Host "    $t" -ForegroundColor DarkGray }
function Warn($t) { Write-Host "    [!] $t" -ForegroundColor Yellow }
function Stop-Install($t) { Write-Host ''; Write-Host "Install stopped: $t" -ForegroundColor Red; throw 'CZ_STOP' }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
function Find-Cmd($name) {
  # the Microsoft Store's python.exe / python3.exe aliases only open the Store: they don't count
  $c = Get-Command $name -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
  if ($c) { return $c.Source } else { return $null }
}
# native programs: their stderr must not count as a PowerShell error (5.1 turns it into one under 'Stop')
function Invoke-Native([scriptblock]$sb) { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $sb } finally { $ErrorActionPreference = $eap } }
function Install-Winget($id, $name) {
  if ($DryRun) { Note "(test mode) would install $name with winget"; return }
  Note "Installing $name ..."
  Invoke-Native { winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null }
  # 0 = installed; -1978335189 = already installed (winget's APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE / no newer)
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189 -and $LASTEXITCODE -ne -1978335212) { Stop-Install "winget could not install $name (code $LASTEXITCODE). Run the installer again, or install $name by hand." }
  Refresh-Path
  Ok "$name installed"
}

try {
Write-Host 'Creatorize Suite installer (Windows)' -ForegroundColor White
Note 'Installs git, ffmpeg, Python + packages, Node.js, Claude Code and Creatorize Suite. Takes 5-20 minutes.'
if ($DryRun) { Warn 'Test mode (CZ_INSTALL_DRY): nothing is installed or changed.' }

if ($env:OS -ne 'Windows_NT') { Stop-Install "this installer is for Windows. On a Mac, run this in Terminal: $MacCmd" }
if (-not [Environment]::Is64BitOperatingSystem) { Stop-Install 'Creatorize Suite needs 64-bit Windows 10 or 11.' }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 17763) { Stop-Install 'Creatorize Suite needs Windows 10 (version 1809) or newer.' }
Note "Windows build $build"

# ---- winget (App Installer): installs the tools below ----
Step 'Windows Package Manager (winget)'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Warn 'winget is missing. It comes with "App Installer" from the Microsoft Store.'
  if (-not $DryRun) { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
  Stop-Install 'install "App Installer" from the Store window that just opened, then run this installer again.'
}
Ok 'winget is available'

# ---- git, ffmpeg, Python ----
Step 'git, ffmpeg and Python'
Refresh-Path
if (Find-Cmd 'git') { Ok 'git already installed' } else { Install-Winget 'Git.Git' 'git' }
if (Find-Cmd 'ffmpeg') { Ok 'ffmpeg already installed' } else { Install-Winget 'Gyan.FFmpeg' 'ffmpeg' }
$py = Find-Cmd 'python'
if ($py) { Ok "Python already installed ($py)" } else { Install-Winget 'Python.Python.3.12' 'Python 3.12'; $py = Find-Cmd 'python' }
if (-not $py -and -not $DryRun) { Stop-Install 'Python was installed but is not found yet. Open a new PowerShell window and run the installer again.' }

# ---- Node.js: HyperFrames (the intro editor) runs on it ----
Step 'Node.js'
if (Find-Cmd 'node') { Ok 'Node.js already installed' } else { Install-Winget 'OpenJS.NodeJS.LTS' 'Node.js'; Refresh-Path }

# ---- Python packages ----
Step 'Python packages for the audio pipeline'
if ($py) {
  # through stdin: PowerShell 5.1 mangles double quotes in arguments to native programs
  $check = "import importlib.util as u`nw = {'numpy': 'numpy', 'scipy': 'scipy', 'PIL': 'pillow', 'stable_whisper': 'stable-ts'}`nprint(' '.join(p for m, p in w.items() if u.find_spec(m) is None))"
  $missing = Invoke-Native { $check | & $py - 2>$null | Select-Object -Last 1 }
  if ($missing) { $missing = "$missing".Trim() }
  if (-not $missing) { Ok 'Python packages already installed' }
  elseif ($DryRun) { Note "(test mode) would install: $missing" }
  else {
    Note "Installing $missing (stable-ts brings PyTorch, a few hundred MB) ..."
    Invoke-Native { & $py -m pip install --quiet --upgrade pip 2>&1 | Out-Null }
    Invoke-Native { & $py -m pip install --quiet --upgrade $missing.Split(' ') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'ERROR' } | ForEach-Object { Warn $_ } }
    if ($LASTEXITCODE -ne 0) { Stop-Install "pip could not install: $missing" }
    Ok 'Python packages installed'
  }
}

# ---- Claude Code ----
Step 'Claude Code'
$claudeHome = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
if ((Find-Cmd 'claude') -or (Test-Path $claudeHome)) { Ok 'Claude Code already installed' }
elseif ($DryRun) { Note '(test mode) would install Claude Code' }
else {
  Note 'Installing Claude Code ...'
  Invoke-Native { & ([scriptblock]::Create((Invoke-RestMethod 'https://claude.ai/install.ps1'))) }
  Refresh-Path
  if ((Find-Cmd 'claude') -or (Test-Path $claudeHome)) { Ok 'Claude Code installed' } else { Warn 'Claude Code may need a new window to show up. Creatorize Suite finds it either way.' }
}

# ---- Creatorize Suite ----
Step 'Creatorize Suite'
if ($env:CZ_SKIP_APP) { Note '(test: CZ_SKIP_APP set, app step skipped)' } else {
# the release's own update file, not the GitHub API (which allows 60 requests an hour per network)
try { $yml = (Invoke-WebRequest "https://github.com/$Owner/$Repo/releases/latest/download/latest.yml" -UseBasicParsing).Content }
catch { Stop-Install "could not reach the Creatorize Suite releases (https://github.com/$Owner/$Repo/releases)." }
if ($yml -is [byte[]]) { $yml = [Text.Encoding]::UTF8.GetString($yml) }
$latest = [regex]::Match($yml, '(?m)^version:\s*(\S+)').Groups[1].Value
$file = [regex]::Match($yml, '(?m)^path:\s*(\S+)').Groups[1].Value
if (-not $latest -or -not $file) { Stop-Install 'the latest release has no Windows installer.' }
$asset = @{ name = $file; browser_download_url = "https://github.com/$Owner/$Repo/releases/download/v$latest/$file" }
$current = $null
if (Test-Path $AppExe) { $current = ((Get-Item $AppExe).VersionInfo.ProductVersion -replace '\.0$', '') }
$running = Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $AppExe }
if ($current -and [version]$current -ge [version]($latest -replace '-.*$', '')) { Ok "Creatorize Suite $current is up to date" }
elseif ($running) { Warn "Creatorize Suite $current is open, so it was not updated to $latest. It updates itself when you close it, or close it and run the installer again." }
elseif ($DryRun) { Note "(test mode) would install Creatorize Suite $latest$(if ($current) { " (installed: $current)" })" }
else {
  $setup = Join-Path $env:TEMP $asset.name
  Note "Downloading Creatorize Suite $latest ..."
  Invoke-WebRequest $asset.browser_download_url -OutFile $setup -UseBasicParsing
  Note 'Installing ...'
  $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru
  Remove-Item $setup -Force -ErrorAction SilentlyContinue
  if ($p.ExitCode -ne 0 -or -not (Test-Path $AppExe)) { Stop-Install "the Creatorize Suite installer did not finish (code $($p.ExitCode))." }
  Ok "Creatorize Suite $latest installed$(if ($current) { " (was $current)" })"
}
}

Step 'Done'
Note 'Your projects will live in Documents\Creatorize Suite.'
if (-not $DryRun -and -not $env:CZ_NO_OPEN -and (Test-Path $AppExe) -and -not (Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue)) {
  Start-Process $AppExe; Ok 'Opening Creatorize Suite: sign in with Claude on the Home page.'
}
Write-Host ''
Write-Host 'All set. Run the same command again any time to update or repair.' -ForegroundColor White
}
catch { if ("$_" -ne 'CZ_STOP') { Write-Host ''; Write-Host "Install stopped: $_" -ForegroundColor Red } }
}
