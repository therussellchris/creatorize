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
function Ver($v) { try { $p = @((($v -replace '-.*$', '') -split '\.') + @('0', '0', '0'))[0..2]; [version]($p -join '.') } catch { [version]'0.0.0' } }   # x.y.z (a 4th part dropped)
function Invoke-Native([scriptblock]$sb) { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $sb } finally { $ErrorActionPreference = $eap } }
# winget's codes in plain words (only the ones a member can act on)
function Why-Winget($code) {
  # 0x8A15005E PINNED_CERTIFICATE_MISMATCH: something re-signs the PC's web traffic
  if ($code -eq -1978335138) { return ': something on this PC checks your internet traffic, usually an antivirus with HTTPS or web scanning, a VPN or a proxy' }
  return ''
}
# --source winget: only the winget repository. Without it winget also asks the Microsoft Store source, whose pinned
# certificate fails behind antivirus HTTPS scanning / VPNs / proxies (0x8A15005E) though none of our tools come from it.
# $direct: the same tool from its official download when winget can't (no winget, no admin rights needed).
function Install-Winget($id, $name, [scriptblock]$direct) {
  if ($DryRun) { Note "(test mode) would install $name with winget"; return }
  Note "Installing $name ..."
  Invoke-Native { winget install --id $id -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null }
  $code = $LASTEXITCODE
  # 0 = installed; -1978335189 = already installed (winget's APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE / no newer)
  if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335212) { Refresh-Path; Ok "$name installed"; return }
  $why = Why-Winget $code
  if (-not $direct) { Stop-Install "winget could not install $name (code $code$why). Run the installer again, or install $name by hand." }
  Warn "winget could not install $name (code $code$why). Downloading it directly instead."
  try { & $direct } catch { Stop-Install "could not install $name (winget code $code$why; direct download: $($_.Exception.Message)). Turn off your antivirus's HTTPS/web scanning or any VPN for a moment and run the installer again." }
  Refresh-Path
  Ok "$name installed"
}

# ---- direct downloads (the winget fallback): per user, no admin rights ----
# CZ_INSTALL_TOOLS (tests): put tools in that folder and leave the user's PATH alone
$Tools = if ($env:CZ_INSTALL_TOOLS) { $env:CZ_INSTALL_TOOLS } else { Join-Path $env:LOCALAPPDATA 'Programs' }
function Add-UserPath($dir) {
  if (-not $env:CZ_INSTALL_TOOLS) {
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($u -split ';') -contains $dir)) { [Environment]::SetEnvironmentVariable('Path', $(if ($u) { "$u;$dir" } else { $dir }), 'User') }
    Refresh-Path
  }
  if (-not (($env:Path -split ';') -contains $dir)) { $env:Path = "$dir;$env:Path" }
}
function Get-Download($url, $name) {
  $f = Join-Path $env:TEMP "cz-$name"
  Invoke-WebRequest -Uri $url -OutFile $f -UseBasicParsing
  return $f
}
function Expand-Fresh($zip, $name) {
  $x = Join-Path $env:TEMP "cz-$name"
  if (Test-Path $x) { Remove-Item $x -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $x -Force
  return $x
}
function Get-Signed($url, $name) {
  # an installer we run must carry its publisher's valid signature
  $f = Get-Download $url $name
  $s = Get-AuthenticodeSignature $f
  if ($s.Status -ne 'Valid') { throw "$name is not validly signed ($($s.Status))" }
  return $f
}
function Direct-Ffmpeg {
  # Gyan's release essentials build: the same files the Gyan.FFmpeg winget package installs
  $x = Expand-Fresh (Get-Download 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' 'ffmpeg.zip') 'ffmpeg'
  $bin = Get-ChildItem $x -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
  if (-not $bin) { throw 'ffmpeg.exe not found in the download' }
  $dest = Join-Path $Tools 'ffmpeg\bin'
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item (Join-Path $bin.DirectoryName '*') $dest -Force
  Add-UserPath $dest
}
function Direct-Node {
  # the newest LTS from nodejs.org, as a zip (an .msi would need admin rights)
  $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json' -UseBasicParsing
  $v = ($idx | Where-Object { $_.lts } | Select-Object -First 1).version
  if (-not $v) { throw 'no Node.js LTS version found' }
  $x = Expand-Fresh (Get-Download "https://nodejs.org/dist/$v/node-$v-win-x64.zip" 'node.zip') 'node'
  $src = Get-ChildItem $x -Directory | Select-Object -First 1
  $dest = Join-Path $Tools 'nodejs'
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Move-Item $src.FullName $dest
  Add-UserPath $dest
}
function Direct-Git {
  $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing
  $a = $rel.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
  if (-not $a) { throw 'no Git for Windows installer found' }
  $f = Get-Signed $a.browser_download_url 'git-setup.exe'
  $p = Start-Process $f -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES', '/CURRENTUSER' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "the Git installer ended with code $($p.ExitCode)" }
  Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd')
}
function Direct-Python {
  # 3.12.10: the last 3.12 release with a Windows installer
  $f = Get-Signed 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' 'python-setup.exe'
  $p = Start-Process $f -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "the Python installer ended with code $($p.ExitCode)" }
  Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312')
  Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\Scripts')
}
function Direct-VCRedist {
  # Windows asks for admin rights here (the redistributable is per machine)
  $f = Get-Signed 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe'
  $p = Start-Process $f -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
  # 3010 = installed, restart later; 1638 = a newer one is already there
  if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010 -and $p.ExitCode -ne 1638) { throw "the installer ended with code $($p.ExitCode)" }
}

# CZ_INSTALL_FALLBACK_TEST (tests): only run the direct downloads into CZ_INSTALL_TOOLS (installers are downloaded and
# their signatures checked, not run), then stop
if ($env:CZ_INSTALL_FALLBACK_TEST -and $env:CZ_INSTALL_TOOLS) {
  Direct-Ffmpeg; & (Join-Path $Tools 'ffmpeg\bin\ffmpeg.exe') -hide_banner -version | Select-Object -First 1
  Direct-Node; & (Join-Path $Tools 'nodejs\node.exe') --version
  $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing
  $a = $rel.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
  Get-Signed $a.browser_download_url 'git-setup.exe' | Out-Null; Write-Host "git installer signed: $($a.name)"
  Get-Signed 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' 'python-setup.exe' | Out-Null; Write-Host 'python installer signed'
  Get-Signed 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' | Out-Null; Write-Host 'vc_redist signed'
  Write-Host 'FALLBACK TEST OK'
  return
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

# ---- Smart App Control: when On it blocks Python's packages (WinError 4551, "blocked by application control policy") ----
# HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy VerifiedAndReputablePolicyState: 0 off, 1 on, 2 evaluation
$sac = $null
try { $sac = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name 'VerifiedAndReputablePolicyState' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState } catch { $sac = $null }
if ($sac -eq 1) {
  Warn 'Smart App Control is On. It blocks the Python packages Creatorize Suite uses (transcription stops with WinError 4551).'
  Warn 'To turn it off: Windows Security > App & browser control > Smart App Control settings > Off, then run this installer again.'
  Warn 'Note: once it is Off, Windows can only turn it back on by resetting or reinstalling Windows.'
}

# ---- git, ffmpeg, Python ----
Step 'git, ffmpeg and Python'
Refresh-Path
if (Find-Cmd 'git') { Ok 'git already installed' } else { Install-Winget 'Git.Git' 'git' { Direct-Git } }
if (Find-Cmd 'ffmpeg') { Ok 'ffmpeg already installed' } else { Install-Winget 'Gyan.FFmpeg' 'ffmpeg' { Direct-Ffmpeg } }
$py = Find-Cmd 'python'
if ($py) { Ok "Python already installed ($py)" } else { Install-Winget 'Python.Python.3.12' 'Python 3.12' { Direct-Python }; $py = Find-Cmd 'python' }
if (-not $py -and -not $DryRun) { Stop-Install 'Python was installed but is not found yet. Open a new PowerShell window and run the installer again.' }

# ---- Microsoft Visual C++ Redistributable (x64): PyTorch (transcription) fails without it (WinError 1114 on c10.dll) ----
Step 'Microsoft Visual C++ Redistributable'
if ($DryRun) { Note '(test mode) would install it with winget' } else {
  Invoke-Native { winget install --id Microsoft.VCRedist.2015+.x64 -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null }
  $code = $LASTEXITCODE
  if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335212) { Ok 'Visual C++ Redistributable (x64) is installed' }
  else {
    Warn "winget could not install it (code $code$(Why-Winget $code)). Downloading it directly instead (Windows asks for permission)."
    try { Direct-VCRedist; Ok 'Visual C++ Redistributable (x64) is installed' }
    catch { Warn "it did not install ($($_.Exception.Message)). Install it from https://aka.ms/vs/17/release/vc_redist.x64.exe" }
  }
}

# ---- Node.js: HyperFrames (the intro editor) runs on it ----
Step 'Node.js'
if (Find-Cmd 'node') { Ok 'Node.js already installed' } else { Install-Winget 'OpenJS.NodeJS.LTS' 'Node.js' { Direct-Node }; Refresh-Path }

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
    Invoke-Native { & $py -m pip install --quiet --no-cache-dir --upgrade $missing.Split(' ') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'ERROR' } | ForEach-Object { Warn $_ } }
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
  # a fresh folder of its own each time (not a fixed name in Temp): an antivirus that blocked or locked an earlier copy
  # can't make this download fail with 'access denied', and an .exe run from Temp is what antiviruses distrust most
  $dl = Join-Path $env:LOCALAPPDATA ('Creatorize Setup\' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dl | Out-Null
  $setup = Join-Path $dl $asset.name
  Note "Downloading Creatorize Suite $latest ..."
  Invoke-WebRequest $asset.browser_download_url -OutFile $setup -UseBasicParsing
  Note 'Installing ...'
  $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru
  Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue
  if ($p.ExitCode -ne 0 -or -not (Test-Path $AppExe)) { Stop-Install "the Creatorize Suite installer did not finish (code $($p.ExitCode))." }
  Ok "Creatorize Suite $latest installed$(if ($current) { " (was $current)" })"
}
}

# ---- Creatorize Launcher: watches every start and fixes a window that doesn't show; update, go back, repair ----
Step 'Creatorize Launcher'
$LExe = Join-Path $env:LOCALAPPDATA 'Programs\creatorize-launcher\Creatorize Launcher.exe'
if ($env:CZ_FROM_LAUNCHER) { Ok 'the launcher is running this repair, so it stays as it is' }
elseif ($env:CZ_SKIP_APP) { Note '(test: CZ_SKIP_APP set, launcher step skipped)' }
else {
  $info = $null
  try { $lj = (Invoke-WebRequest "https://github.com/$Owner/creatorize/releases/latest/download/launcher.json" -UseBasicParsing).Content; if ($lj -is [byte[]]) { $lj = [Text.Encoding]::UTF8.GetString($lj) }; $info = $lj | ConvertFrom-Json } catch { $info = $null }
  $have = $null
  if (Test-Path $LExe) { $have = (Get-Item $LExe).VersionInfo.ProductVersion }   # "1.0.0.0": Ver compares it as 1.0.0
  if (-not $info -or -not $info.windows) { if ($have) { Ok "Creatorize Launcher $have is installed" } else { Note 'not published yet: Creatorize Suite installs it by itself later' } }
  elseif ($have -and (Ver $have) -ge (Ver $info.version)) { Ok "Creatorize Launcher $have is up to date" }
  elseif (Get-Process -Name 'Creatorize Launcher' -ErrorAction SilentlyContinue) { Warn 'the launcher is open, so it was not updated: it updates itself later' }
  elseif ($DryRun) { Note "(test mode) would install Creatorize Launcher $($info.version)" }
  else {
    $dl = Join-Path $env:LOCALAPPDATA ('Creatorize Setup\' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $setup = Join-Path $dl $info.windows
    try {
      Note "Downloading Creatorize Launcher $($info.version) ..."
      Invoke-WebRequest "https://github.com/$Owner/creatorize/releases/latest/download/$($info.windows)" -OutFile $setup -UseBasicParsing
      $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru
      if ($p.ExitCode -eq 0 -and (Test-Path $LExe)) { Ok "Creatorize Launcher $($info.version) installed (Start menu: Creatorize Launcher)" } else { Warn "the launcher did not install (code $($p.ExitCode)); Creatorize Suite tries again by itself later" }
    } catch { Warn "the launcher did not install ($_); Creatorize Suite tries again by itself later" }
    Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Step 'Done'
Note 'Your projects will live in Documents\Creatorize Suite.'
if (-not $DryRun -and -not $env:CZ_NO_OPEN -and (Test-Path $AppExe) -and -not (Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue)) {
  Start-Process $AppExe; Ok 'Opening Creatorize Suite: log in with your Skool account, then sign in with Claude on the Home page.'
}
Write-Host ''
Write-Host 'All set. Run the same command again any time to update or repair.' -ForegroundColor White
}
catch {
  if ("$_" -ne 'CZ_STOP') { Write-Host ''; Write-Host "Install stopped: $_" -ForegroundColor Red }
  # the launcher's Repair runs this as a script and reads its exit code (never `exit` under irm | iex: it would close the
  # member's PowerShell window)
  if ($env:CZ_FROM_LAUNCHER) { exit 1 }
}
}
