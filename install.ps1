# Creatorize Suite installer for Windows: everything the app needs, then the app itself.
#   irm https://raw.githubusercontent.com/therussellchris/creatorize/main/install.ps1 | iex
# Safe to run again: it skips what is already there, updates Creatorize Suite if a newer version is out, and repairs
# anything missing. Source: installer/install.ps1 in the Creatorize Suite code repo (published by scripts/publish-installer.mjs,
# after scripts/installer-test/run.mjs passed on exactly the files it publishes).
# Keep this file plain ASCII: Windows PowerShell 5.1 runs it through `irm | iex`.
# How it ends: 0 = all set; 3 = finished, with something left for you to do (listed at the end: Claude Code could not be
# reached, the Visual C++ Redistributable was declined, the app was open, ...); 1 = stopped (the reason is printed).
# Run as a file (the Creatorize Launcher's Repair, scripts) that is the exit code; through `irm | iex` it is
# $LASTEXITCODE and the window stays open.

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Owner = 'therussellchris'
$Repo = 'creatorize-suite-releases'
$AppDir = Join-Path $env:LOCALAPPDATA 'Programs\creatorize-suite'
$AppExe = Join-Path $AppDir 'Creatorize Suite.exe'
$AppConfig = Join-Path $env:APPDATA 'Creatorize Suite\config.json'
$MacCmd = "curl -fsSL https://raw.githubusercontent.com/$Owner/creatorize/main/install.sh | bash"
$DryRun = [bool]$env:CZ_INSTALL_DRY    # test mode: detect and report, change nothing
# CZ_INSTALL_KEEP=installed (the launcher's Repair): repair the version that is installed (every file checked, that exact
# version installed again when one is missing or changed), never update it; the launcher has its own Update
$Keep = $env:CZ_INSTALL_KEEP -eq 'installed'
# CZ_INSTALL_VERSION=x.y.z ("Update Creatorize for me", AGENTS.md section 13, which reads the number from update.json):
# exactly this release, a beta too. The member asked for it, so it wins over paused updates and a held version. Never goes
# backwards: a newer installed version stays.
$Want = if ($env:CZ_INSTALL_VERSION) { $env:CZ_INSTALL_VERSION.Trim().TrimStart('v') } else { '' }
# a launcher from before this installer (1.1.5 and older, no CZ_INSTALL_KEEP): it reads any code but 0 as "Repair
# stopped" and never closes an open Creatorize, so for it "left to do" ends with 0 and an open app is only a warning
$OldLauncher = $env:CZ_FROM_LAUNCHER -and -not $env:CZ_INSTALL_KEEP
$Left = New-Object System.Collections.ArrayList   # what is left for the member: the run ends with code 3
# the launcher reads this script's lines as UTF-8 (a path with an accent in its Details)
if ($env:CZ_FROM_LAUNCHER) { try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { } }

function Step($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor White }
function Ok($t) { Write-Host "    [ok] $t" -ForegroundColor Green }
function Note($t) { Write-Host "    $t" -ForegroundColor DarkGray }
function Warn($t) { Write-Host "    [!] $t" -ForegroundColor Yellow }
function Todo($t) { [void]$Left.Add($t); Warn $t }
function Stop-Install($t) { Write-Host ''; Write-Host "Install stopped: $t" -ForegroundColor Red; throw 'CZ_STOP' }
# CZ_INSTALL_TOOLS (tests): the test's PATH stays as the test made it (never the computer's own PATH)
function Refresh-Path { if (-not $env:CZ_INSTALL_TOOLS) { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') } }
# CZ_INSTALL_MIRROR (tests, scripts/installer-test/run.mjs): every download from a local server instead
# (https://host/path -> <mirror>/host/path), so a test never reaches the internet
function Net-Url($u) { if ($env:CZ_INSTALL_MIRROR) { return $env:CZ_INSTALL_MIRROR.TrimEnd('/') + '/' + ($u -replace '^https?://', '') } return $u }
function Find-Cmd($name) {
  # the Microsoft Store's python.exe / python3.exe aliases only open the Store: they don't count
  # (-All: without it PowerShell gives only the first on PATH, so a Store alias in front hid a real Python behind it)
  $c = Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
  if ($c) { return $c.Source } else { return $null }
}
# versions: x.y.z (a 4th part dropped); a test build (0.24.0-beta.1) is older than 0.24.0 and newer than 0.23.x
function Ver($v) { try { $p = @((("$v" -replace '-.*$', '') -split '\.') + @('0', '0', '0'))[0..2]; [version]($p -join '.') } catch { [version]'0.0.0' } }
function Cmp-Ver($a, $b) {
  $c = (Ver $a).CompareTo((Ver $b)); if ($c -ne 0) { return [Math]::Sign($c) }
  $pa = "$a" -replace '^[^-]*-?', ''; $pb = "$b" -replace '^[^-]*-?', ''
  if ($pa -eq $pb) { return 0 }
  if (-not $pa) { return 1 }
  if (-not $pb) { return -1 }
  $na = [regex]::Match($pa, '\d+$').Value; $nb = [regex]::Match($pb, '\d+$').Value
  if ($na -and $nb -and ($pa -replace '\d+$', '') -eq ($pb -replace '\d+$', '')) { return [Math]::Sign([long]$na - [long]$nb) }
  return [Math]::Sign([string]::CompareOrdinal($pa, $pb))
}
# native programs: their stderr must not count as a PowerShell error (5.1 turns it into one under 'Stop')
function Invoke-Native([scriptblock]$sb) { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $sb } finally { $ErrorActionPreference = $eap } }
# winget's codes in plain words (only the ones a member can act on)
function Why-Winget($code) {
  # 0x8A15005E PINNED_CERTIFICATE_MISMATCH: something re-signs the PC's web traffic
  if ($code -eq -1978335138) { return ': something on this PC checks your internet traffic, usually an antivirus with HTTPS or web scanning, a VPN or a proxy' }
  return ''
}

# ---- a proxy: HTTPS_PROXY / HTTP_PROXY / ALL_PROXY (http://user:password@host:port works: the password URL-encoded),
# else Windows' own proxy with this account's login (a company proxy answers 407 "proxy authentication required"
# to a request without it). Every download below goes through Web-Get / Web-File. ----
$PX = @{}
function Use-Proxy {
  $p = @($env:HTTPS_PROXY, $env:HTTP_PROXY, $env:ALL_PROXY) | Where-Object { $_ } | Select-Object -First 1
  if (-not $p) {
    try { $d = [Net.WebRequest]::DefaultWebProxy; if ($d) { $d.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } } catch { }
    return
  }
  if ($p -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $p = "http://$p" }
  try { $u = [Uri]$p } catch { Warn "the proxy setting ($($p -replace '//[^@/]*@', '//')) is not an address: going without it"; return }
  $addr = "$($u.Scheme)://$($u.Host):$($u.Port)"
  $wp = New-Object Net.WebProxy($addr, $true)
  if ($u.UserInfo) {
    $i = $u.UserInfo.IndexOf(':')
    $user = [Uri]::UnescapeDataString($(if ($i -ge 0) { $u.UserInfo.Substring(0, $i) } else { $u.UserInfo }))
    $pass = [Uri]::UnescapeDataString($(if ($i -ge 0) { $u.UserInfo.Substring($i + 1) } else { '' }))
    $wp.Credentials = New-Object Net.NetworkCredential($user, $pass)
    $PX.Proxy = $addr
    $sec = if ($pass) { ConvertTo-SecureString $pass -AsPlainText -Force } else { New-Object Security.SecureString }   # (a login without a password)
    $PX.ProxyCredential = New-Object Management.Automation.PSCredential($user, $sec)
    Note "Using the proxy $($u.Host):$($u.Port) with its user name and password"
  } else {
    $wp.UseDefaultCredentials = $true
    $PX.Proxy = $addr; $PX.ProxyUseDefaultCredentials = $true
    Note "Using the proxy $($u.Host):$($u.Port)"
  }
  [Net.WebRequest]::DefaultWebProxy = $wp   # (also for Claude Code's own installer, which downloads by itself)
}
function Web-Get($url) {
  $c = (Invoke-WebRequest -Uri (Net-Url $url) -UseBasicParsing @PX).Content
  if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
  return [string]$c
}
function Web-File($url, $out) {
  # a network hiccup half way doesn't end the install: three tries
  for ($i = 1; ; $i++) {
    try { Invoke-WebRequest -Uri (Net-Url $url) -OutFile $out -UseBasicParsing @PX; return }
    catch {
      $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
      if ($i -ge 3 -or $code -eq 404) { throw }
      Note 'The download stopped half way. Trying again ...'
      if (-not $env:CZ_INSTALL_MIRROR) { Start-Sleep -Seconds 3 }
    }
  }
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
  Web-File $url $f
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
function Install-Winget($id, $name, [scriptblock]$direct) {
  if ($DryRun) { Note "(test mode) would install $name with winget"; return }
  Note "Installing $name ..."
  # --source winget: only the winget repository. Without it winget also asks the Microsoft Store source, whose pinned
  # certificate fails behind antivirus HTTPS scanning / VPNs / proxies (0x8A15005E) though none of our tools come from it.
  Invoke-Native { winget install --id $id -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null }
  $code = $LASTEXITCODE
  # 0 = installed; -1978335189 (0x8A15002B, no newer version) and -1978335135 (0x8A150061) = already installed.
  # (-1978335212, 0x8A150014, is "no package found": a broken winget source, never "installed")
  if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { Refresh-Path; Ok "$name installed"; return }
  $why = Why-Winget $code
  if (-not $direct) { Stop-Install "winget could not install $name (code $code$why). Run the installer again, or install $name by hand." }
  # $direct: the same tool from its official download when winget can't (no winget, no admin rights needed)
  Warn "winget could not install $name (code $code$why). Downloading it directly instead."
  try { & $direct } catch { Stop-Install "could not install $name (winget code $code$why; direct download: $($_.Exception.Message)). Allow the installer in your antivirus's web protection (or pause a VPN or proxy for a moment) and run the installer again." }
  Refresh-Path
  Ok "$name installed"
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
  $idx = Web-Get 'https://nodejs.org/dist/index.json' | ConvertFrom-Json
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
  $rel = Web-Get 'https://api.github.com/repos/git-for-windows/git/releases/latest' | ConvertFrom-Json
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
# the Microsoft Visual C++ Redistributable (x64): PyTorch (transcription) fails without it (WinError 1114 on c10.dll).
# $true = installed (or already there)
function VC-Installed {
  # Windows' own record of the x64 runtime (so a PC that has it never gets an admin question). Tests (CZ_INSTALL_TOOLS)
  # never read this PC's registry: their stand-in winget plays it
  if ($env:CZ_INSTALL_TOOLS) { return $false }
  foreach ($k in @('HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64')) {
    try { if ((Get-ItemProperty -Path $k -Name Installed -ErrorAction SilentlyContinue).Installed -eq 1) { return $true } } catch { }
  }
  return $false
}
function Install-VC {
  Invoke-Native { winget install --id Microsoft.VCRedist.2015+.x64 -e --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null }
  $code = $LASTEXITCODE
  if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { return $true }
  Warn "winget could not install it (code $code$(Why-Winget $code)). Downloading it directly instead (Windows asks for permission: press Yes)."
  try { Direct-VCRedist; return $true } catch { Warn "it did not install ($($_.Exception.Message))."; return $false }
}

# ---- Python: one PyTorch (transcription) runs on: 3.9 to 3.12, 64-bit, not conda. Another Python on this computer
# (3.13 / 3.14, conda, 32-bit, Python 2, one that is broken or blocked) stays as it is: Python 3.12 is installed next
# to it and Creatorize Suite is set to use that one (its Settings > System > Tool paths > Python). A Python that can't
# even run the check below never counts as installed. ----
# (the program's path as UTF-8 hex: through a pipe Python writes the ANSI code page and PowerShell reads the OEM one, so
# a user name like Jose with an accent would come back garbled and be written into the app's settings)
$PyProbe = "import sys, struct, os, binascii`nprint('CZPY %d.%d %d %s %s' % (sys.version_info[0], sys.version_info[1], struct.calcsize('P') * 8, 'conda' if os.path.exists(os.path.join(sys.prefix, 'conda-meta')) else 'ok', binascii.hexlify(sys.executable.encode('utf-8')).decode('ascii')))"
$PkgCheck = "import importlib.util as u`nw = {'numpy': 'numpy', 'scipy': 'scipy', 'PIL': 'pillow', 'stable_whisper': 'stable-ts'}`nprint('CZPKG ' + ' '.join(p for m, p in w.items() if u.find_spec(m) is None))"
$TorchCheck = "try:`n    import torch`n    print('CZTORCH ok ' + torch.__version__)`nexcept Exception as e:`n    print('CZTORCH fail ' + repr(e))"
# a script through stdin (PowerShell 5.1 mangles double quotes in arguments to native programs); its lines as text
function Py-Run($exe, [string[]]$pre, $code, [switch]$All) {
  try {
    if ($All) { return @(Invoke-Native { $code | & $exe @pre - 2>&1 | ForEach-Object { "$_" } }) }
    return @(Invoke-Native { $code | & $exe @pre - 2>$null | ForEach-Object { "$_" } })
  } catch { return @("could not start $exe ($($_.Exception.Message))") }
}
function Probe-Python($exe, [string[]]$pre = @()) {
  $l = Py-Run $exe $pre $PyProbe | Where-Object { $_ -match '^CZPY ' } | Select-Object -Last 1
  if (-not $l) { return $null }
  $f = $l.Trim() -split ' ', 5
  $v = Ver $f[1]
  $why = $null
  if ($v.Major -ne 3 -or $v.Minor -lt 9 -or $v.Minor -gt 12) { $why = "Python $($f[1])" }
  elseif ($f[2] -ne '64') { $why = "32-bit Python $($f[1])" }
  elseif ($f[3] -eq 'conda') { $why = "a conda Python ($($f[1]))" }
  $hex = "$($f[4])".Trim(); $b = New-Object byte[] ([int]($hex.Length / 2))
  try { for ($k = 0; $k -lt $b.Length; $k++) { $b[$k] = [Convert]::ToByte($hex.Substring(2 * $k, 2), 16) } } catch { return $null }
  return @{ ver = $f[1]; exe = [Text.Encoding]::UTF8.GetString($b); why = $why }
}
function App-Python {
  # the Python the app's settings name (null: none set, or the plain default)
  try { if (Test-Path -LiteralPath $AppConfig) { $p = ([IO.File]::ReadAllText($AppConfig) | ConvertFrom-Json).tools.python; if ($p -and $p -notin @('python', 'python3', 'python.exe')) { return [string]$p } } } catch { }
  return $null
}
$PySeen = @{}
function Find-GoodPython {
  # @{ exe; ver; how } of the first Python PyTorch runs on: the app's own setting, `python` on PATH, Python 3.12 where
  # its installers put it, the py launcher's 3.12. $null = none
  $c = @()
  $set = App-Python; if ($set) { $c += , @($set, @(), 'setting') }
  # (the app runs the FIRST `python` on PATH: when that is the Microsoft Store's alias, which only opens the Store, the
  # real one behind it must be written into the app's setting)
  $first = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $onPath = Find-Cmd 'python'; if ($onPath) { $c += , @($onPath, @(), $(if ($first -and $first.Source -like '*\WindowsApps\*') { 'other' } else { 'path' })) }
  foreach ($k in @((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'), (Join-Path $env:ProgramFiles 'Python312\python.exe'))) { if (Test-Path -LiteralPath $k) { $c += , @($k, @(), 'other') } }
  if (Find-Cmd 'py') { $c += , @('py', @('-3.12'), 'other') }
  foreach ($x in $c) {
    $r = Probe-Python $x[0] $x[1]
    $key = "$($x[0]) $($x[1])".ToLower()
    if (-not $r) { if (-not $PySeen[$key]) { $PySeen[$key] = 1; if ($x[0] -ne 'py') { Note "$($x[0]) does not run (broken, blocked by Windows, or not a Python 3): not used" } } ; continue }
    if ($r.why) { if (-not $PySeen[$key]) { $PySeen[$key] = 1; Note "$($r.exe) is $($r.why): PyTorch (transcription) does not run on it, so it is not used (it stays as it is)" } ; continue }
    # (the path it said must be a file here; else the one it was started as, when that is a full path)
    $exe = $null
    if (Test-Path -LiteralPath $r.exe -PathType Leaf) { $exe = $r.exe } elseif ($x[0] -ne 'py') { $exe = $x[0] }
    if (-not $exe) { continue }
    return @{ exe = $exe; ver = $r.ver; how = $x[2] }
  }
  return $null
}
function Set-AppPython($exe) {
  # only the Python setting changes; every other setting stays exactly as it is. A config.json that can't be read is
  # never overwritten (the app has its own way back for it)
  if ($DryRun) { Note "(test mode) would set Creatorize Suite to use $exe"; return }
  try {
    $cfg = $null
    if (Test-Path -LiteralPath $AppConfig) { $t = [IO.File]::ReadAllText($AppConfig); if ($t.Trim()) { $cfg = $t | ConvertFrom-Json } }
    if (-not $cfg) { $cfg = New-Object PSObject }
    if (-not $cfg.tools) { $cfg | Add-Member -NotePropertyName tools -NotePropertyValue (New-Object PSObject) -Force }
    $cfg.tools | Add-Member -NotePropertyName python -NotePropertyValue $exe -Force
    $json = ConvertTo-Json -InputObject $cfg -Depth 64
    New-Item -ItemType Directory -Force -Path (Split-Path $AppConfig) | Out-Null
    $tmp = "$AppConfig.cz-tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $AppConfig -Force
    Ok "Creatorize Suite is set to use this Python ($exe)"
    if (Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue) { Todo 'Creatorize Suite is open: close it and run the installer again, so it keeps the new Python setting.' }
  } catch { Todo "could not set Creatorize Suite to use $exe ($($_.Exception.Message)). In the app: Settings > System > Tool paths > Python, and paste $exe" }
}
function Missing-Pkgs($py) {
  # the missing packages' names ('' = none); $null = the check could not run in this Python
  $l = Py-Run $py @() $PkgCheck | Where-Object { $_ -match '^CZPKG' } | Select-Object -Last 1
  if ($null -eq $l) { return $null }
  return ($l -replace '^CZPKG', '').Trim()
}
function Torch-Fail($py) {
  # $null = PyTorch starts; else what it said
  $o = (Py-Run $py @() $TorchCheck -All) -join ' '
  if ($o -match 'CZTORCH ok') { return $null }
  return $o.Trim()
}

# ---- what Creatorize Suite is installed, and is every file of it there ----
function Read-Manifest($f) {
  # files.json (every release writes it: scripts/after-pack.cjs): the exact version, beta included, and every file under
  # resources\ with its size and SHA-256. Read with .NET: ConvertFrom-Json in 5.1 stops at 2 MB
  Add-Type -AssemblyName System.Web.Extensions
  $s = New-Object Web.Script.Serialization.JavaScriptSerializer
  $s.MaxJsonLength = [int]::MaxValue
  return $s.DeserializeObject([IO.File]::ReadAllText($f))
}
function Installed-App {
  $m = $null
  $mf = Join-Path $AppDir 'resources\files.json'
  if (Test-Path -LiteralPath $mf) { try { $m = Read-Manifest $mf } catch { $m = $null } }
  $v = $null
  if ($m -and $m['version']) { $v = [string]$m['version'] }
  elseif (Test-Path -LiteralPath $AppExe) {
    $v = (Get-Item -LiteralPath $AppExe).VersionInfo.ProductVersion
    if ($v -match '^\d+\.\d+\.\d+\.\d+$') { $v = $v -replace '\.\d+$', '' }
    if ($v -eq '0.0.0' -or -not $v) { $v = $null }
  }
  return @{ version = $v; manifest = $m }
}
function Test-AppFiles($m) {
  # the files that are missing or differ from the release's own list (an antivirus took or changed them, an update
  # stopped half way). Without a list (an older version): the program files Electron can't start without
  $bad = New-Object System.Collections.ArrayList
  foreach ($t in @('Creatorize Suite.exe', 'resources.pak', 'icudtl.dat', 'v8_context_snapshot.bin', 'ffmpeg.dll', 'resources\app.asar')) { if (-not (Test-Path -LiteralPath (Join-Path $AppDir $t))) { [void]$bad.Add(($t -replace '\\', '/')) } }
  if (-not $m) { return $bad.ToArray() }
  $res = Join-Path $AppDir 'resources'
  $sha = [Security.Cryptography.SHA256]::Create()
  foreach ($f in $m['files']) {
    $rel = [string]$f['path']
    if ($rel -eq 'app.asar' -and $bad.Contains('resources/app.asar')) { continue }
    $p = [IO.Path]::Combine($res, $rel.Replace('/', '\'))
    $i = [IO.FileInfo]::new($p)   # (.NET, not cmdlets: 3500 files (a real install) are checked and hashed in under a second)
    if (-not $i.Exists -or $i.Length -ne [long]$f['size']) { [void]$bad.Add("resources/$rel"); continue }
    try { $s = [IO.File]::OpenRead($p); try { $h = [BitConverter]::ToString($sha.ComputeHash($s)).Replace('-', '').ToLower() } finally { $s.Dispose() } }
    catch { $h = '' }
    if ($h -ne [string]$f['sha256']) { [void]$bad.Add("resources/$rel") }
  }
  return $bad.ToArray()
}
function Held-Versions {
  # the versions the app's update gate held on this computer (they did not pass their test here): updates\held.json next
  # to the app's config.json, keyed by version
  $f = Join-Path (Split-Path $AppConfig) 'updates\held.json'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  try { return @((Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name) } catch { return @() }
}
function Paused-Version {
  # after Go back in the Creatorize Launcher updates stay paused (its updates-paused.json, the CZ_NO_UPDATE setting):
  # the version gone back to; '' = paused, version not known; $null = not paused
  $f = Join-Path $env:APPDATA 'Creatorize Launcher\updates-paused.json'
  try { if (Test-Path -LiteralPath $f) { $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json; if ($j.version) { return [string]$j.version } } } catch { }
  if ($env:CZ_NO_UPDATE) { return '' }
  return $null
}
function Release-Info($v) {
  # a release's own update file (not the GitHub API, which allows 60 requests an hour per network): version, Setup, sha512
  $urls = if ($v) { @("https://github.com/$Owner/$Repo/releases/download/v$v/latest.yml", "https://github.com/$Owner/$Repo/releases/download/v$v/beta.yml") } else { @("https://github.com/$Owner/$Repo/releases/latest/download/latest.yml") }
  foreach ($u in $urls) {
    try { $yml = Web-Get $u } catch { continue }
    $r = @{ version = [regex]::Match($yml, '(?m)^version:\s*(\S+)').Groups[1].Value; file = [regex]::Match($yml, '(?m)^path:\s*(\S+)').Groups[1].Value; sha512 = [regex]::Match($yml, '(?m)^sha512:\s*(\S+)').Groups[1].Value }
    if ($r.version -and $r.file) { return $r }
  }
  return $null
}
function Install-Suite($rel, $was) {
  # a fresh folder of its own each time (not a fixed name in Temp): an antivirus that blocked or locked an earlier copy
  # can't make this download fail with 'access denied', and an .exe run from Temp is what antiviruses distrust most
  $v = $rel.version
  $dl = Join-Path $env:LOCALAPPDATA ('Creatorize Setup\' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dl | Out-Null
  $setup = Join-Path $dl $rel.file
  try {
    Note "Downloading Creatorize Suite $v ..."
    try { Web-File "https://github.com/$Owner/$Repo/releases/download/v$v/$($rel.file)" $setup }
    catch { Stop-Install "the download of Creatorize Suite $v failed ($($_.Exception.Message)). Nothing was changed. Check the internet connection and run the installer again." }
    # the download must be exactly the release's file (its sha512 in the release's update file)
    if ($rel.sha512) {
      $h512 = [Security.Cryptography.SHA512]::Create(); $s = [IO.File]::OpenRead($setup)
      try { $got = [Convert]::ToBase64String($h512.ComputeHash($s)) } finally { $s.Dispose() }
      if ($got -ne $rel.sha512) { Stop-Install "the download of Creatorize Suite $v was damaged on the way (it did not match the release), so it was not run. Nothing was changed. Run the installer again; if this shows again, something on this computer or network changes downloads (an antivirus's web scanning, a proxy): pause it for a moment." }
    }
    Note 'Installing ...'
    $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $AppExe)) { Stop-Install "the Creatorize Suite installer did not finish (code $($p.ExitCode)). Restart the computer and run the installer again." }
  } finally { Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue }
  # checked again: the version it says, and every file of it
  $now = Installed-App
  if ($now.version -and (Cmp-Ver $now.version $v) -ne 0) { Stop-Install "Creatorize Suite says version $($now.version) after installing $v. Restart the computer and run the installer again." }
  $bad = @(Test-AppFiles $now.manifest)
  if ($bad.Count) { Stop-Install "Creatorize Suite $v was installed, but $($bad.Count) of its files are missing again right after ($(@($bad)[0..2] -join ', ')). An antivirus most likely removed them: allow Creatorize Suite in it, then run the installer again." }
  Ok "Creatorize Suite $v installed$(if ($was) { if ($was -eq $v) { ' again, every file checked' } else { " (was $was)" } })"
}

# CZ_INSTALL_FALLBACK_TEST (tests): only run the direct downloads into CZ_INSTALL_TOOLS (installers are downloaded and
# their signatures checked, not run), then stop
if ($env:CZ_INSTALL_FALLBACK_TEST -and $env:CZ_INSTALL_TOOLS) {
  Use-Proxy
  Direct-Ffmpeg; & (Join-Path $Tools 'ffmpeg\bin\ffmpeg.exe') -hide_banner -version | Select-Object -First 1
  Direct-Node; & (Join-Path $Tools 'nodejs\node.exe') --version
  $rel = Web-Get 'https://api.github.com/repos/git-for-windows/git/releases/latest' | ConvertFrom-Json
  $a = $rel.assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
  Get-Signed $a.browser_download_url 'git-setup.exe' | Out-Null; Write-Host "git installer signed: $($a.name)"
  Get-Signed 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' 'python-setup.exe' | Out-Null; Write-Host 'python installer signed'
  Get-Signed 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' | Out-Null; Write-Host 'vc_redist signed'
  Write-Host 'FALLBACK TEST OK'
  return
}

$stopped = $false
try {
Write-Host 'Creatorize Suite installer (Windows)' -ForegroundColor White
Note 'Installs git, ffmpeg, Python + packages, Node.js, Claude Code and Creatorize Suite. Takes 5-20 minutes.'
if ($DryRun) { Warn 'Test mode (CZ_INSTALL_DRY): nothing is installed or changed.' }

if ($env:OS -ne 'Windows_NT') { Stop-Install "this installer is for Windows. On a Mac, run this in Terminal: $MacCmd" }
if (-not [Environment]::Is64BitOperatingSystem) { Stop-Install 'Creatorize Suite needs 64-bit Windows 10 or 11.' }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 17763) { Stop-Install 'Creatorize Suite needs Windows 10 (version 1809) or newer.' }
Note "Windows build $build"
Use-Proxy

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
$good = Find-GoodPython
if ($good) { Ok "Python $($good.ver) already installed ($($good.exe))" }
else {
  Note 'Installing Python 3.12 (next to any other Python on this computer, which stays as it is) ...'
  Install-Winget 'Python.Python.3.12' 'Python 3.12' { Direct-Python }
  $good = Find-GoodPython
  if (-not $good -and -not $DryRun) {
    # winget said "already installed" or put it somewhere else: the direct download once more
    try { Direct-Python } catch { Warn "Python 3.12 from python.org did not install ($($_.Exception.Message))" }
    $good = Find-GoodPython
  }
  if (-not $good -and -not $DryRun) { Stop-Install 'Python 3.12 was installed but does not start. Open a new PowerShell window and run the installer again; if this shows again, restart the computer first.' }
}
$py = $null
if ($good) {
  $py = $good.exe
  # the app runs `python` from PATH unless its setting names another: point it at this one when that is not the same
  if ($good.how -eq 'other') { Set-AppPython $good.exe }
  elseif ($good.how -eq 'path' -and (App-Python)) { Set-AppPython $good.exe }
}

# ---- Microsoft Visual C++ Redistributable (x64): PyTorch (transcription) fails without it (WinError 1114 on c10.dll) ----
Step 'Microsoft Visual C++ Redistributable'
if ($DryRun) { Note '(test mode) would install it with winget' }
elseif (VC-Installed) { Ok 'Visual C++ Redistributable (x64) already installed' }
elseif (Install-VC) { Ok 'Visual C++ Redistributable (x64) is installed' }
else { Note 'Checked again below, once the Python packages are in: transcription needs it.' }

# ---- Node.js: HyperFrames (the intro editor) runs on it ----
Step 'Node.js'
if (Find-Cmd 'node') { Ok 'Node.js already installed' } else { Install-Winget 'OpenJS.NodeJS.LTS' 'Node.js' { Direct-Node }; Refresh-Path }

# ---- Python packages ----
Step 'Python packages for the audio pipeline'
if ($py) {
  $missing = Missing-Pkgs $py
  if ($null -eq $missing) { Warn "$py could not check its packages: installing all of them"; $missing = 'numpy scipy pillow stable-ts' }
  if (-not $missing) { Ok 'Python packages already installed' }
  elseif ($DryRun) { Note "(test mode) would install: $missing" }
  else {
    Note "Installing $missing (stable-ts brings PyTorch, a few hundred MB) ..."
    Invoke-Native { & $py -m pip install --quiet --upgrade pip 2>&1 | Out-Null }
    $pipOut = @(Invoke-Native { & $py -m pip install --quiet --no-cache-dir --upgrade $missing.Split(' ') 2>&1 | ForEach-Object { "$_" } })
    $after = Missing-Pkgs $py
    if ($null -eq $after -or $after) {
      foreach ($l in ($pipOut | Where-Object { $_ -match 'ERROR' } | Select-Object -First 3)) { Note $l }
      Todo "pip could not install: $(if ($after) { $after } else { $missing }) (internet connection, a proxy or the disk full?). Transcription and the audio steps need them: run the installer again, or Repair in the Creatorize Launcher."
    } else { Ok 'Python packages installed' }
  }
  # PyTorch must really start (the VC++ redistributable declined at Windows' question, Smart App Control, a broken wheel)
  $now = Missing-Pkgs $py
  if (-not $DryRun -and $null -ne $now -and $now -notmatch 'stable-ts') {
    $tf = Torch-Fail $py
    if (-not $tf) { Ok 'PyTorch starts: transcription is ready' }
    elseif ($tf -match '1114|c10\.dll|DLL initialization') {
      Warn 'PyTorch (transcription) cannot start: Windows is missing the Microsoft Visual C++ Redistributable. Asking for it once more: press Yes when Windows asks for permission.'
      if ((Install-VC) -and -not (Torch-Fail $py)) { Ok 'Visual C++ Redistributable installed: PyTorch starts, transcription is ready' }
      else { Todo 'Transcription will not work until the Microsoft Visual C++ Redistributable (x64) is installed: open https://aka.ms/vs/17/release/vc_redist.x64.exe, run it and press Yes, then press Repair in the Creatorize Launcher (or run this installer again).' }
    }
    elseif ($tf -match '4551|[Aa]pplication [Cc]ontrol') { Todo 'PyTorch (transcription) is blocked by Smart App Control (see above): turn it off, then run the installer again.' }
    else { Todo "PyTorch (transcription) does not start in $py ($(if ($tf.Length -gt 200) { $tf.Substring(0, 200) } else { $tf })). Press Repair in the Creatorize Launcher, or ask in the community with this line." }
  }
}

# ---- Claude Code: a warning when it can't be installed (claude.ai blocked, a Wi-Fi login page): the app still installs ----
Step 'Claude Code'
$claudeHome = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
if ((Find-Cmd 'claude') -or (Test-Path $claudeHome)) { Ok 'Claude Code already installed' }
elseif ($DryRun) { Note '(test mode) would install Claude Code' }
else {
  Note 'Installing Claude Code ...'
  $why = $null
  try {
    $cs = Web-Get 'https://claude.ai/install.ps1'
    if ($cs -match '^\s*<' -or $cs -match '(?i)<html') { $why = 'claude.ai sent a web page instead of its installer (a network that wants you to log in first, like hotel or office Wi-Fi, or a web filter)' }
    else {
      # in a process of its own: an `exit` in it can't end this installer (or close the member's window under irm | iex).
      # Its one-line starter comes on stdin (`-Command -`), so that process never waits on a stdin left open (the
      # launcher's), and its script runs as a script block, as with irm | iex (no file for an execution policy to refuse).
      # It gets this run's proxy (a login in HTTPS_PROXY) for its own downloads, through its environment only
      $cf = Join-Path $env:TEMP ('cz-claude-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
      [IO.File]::WriteAllText($cf, $cs, (New-Object Text.UTF8Encoding $false))
      $wrap = "`$ProgressPreference = 'SilentlyContinue'; if (`$env:CZ_CHILD_PROXY) { `$wp = New-Object Net.WebProxy(`$env:CZ_CHILD_PROXY, `$true); if (`$env:CZ_CHILD_PROXY_USER) { `$wp.Credentials = New-Object Net.NetworkCredential([string]`$env:CZ_CHILD_PROXY_USER, [string]`$env:CZ_CHILD_PROXY_PASS) } else { `$wp.UseDefaultCredentials = `$true }; [Net.WebRequest]::DefaultWebProxy = `$wp } else { try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch { } }; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create([IO.File]::ReadAllText(`$env:CZ_CHILD_SCRIPT)))"
      $env:CZ_CHILD_SCRIPT = $cf
      if ($PX.Proxy) { $env:CZ_CHILD_PROXY = $PX.Proxy; if ($PX.ProxyCredential) { $nc = $PX.ProxyCredential.GetNetworkCredential(); $env:CZ_CHILD_PROXY_USER = $nc.UserName; $env:CZ_CHILD_PROXY_PASS = $nc.Password } }
      $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
      try { Invoke-Native { $wrap | & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^#< CLIXML|^<Objs ' } | ForEach-Object { Note $_ } } }
      finally { foreach ($n in @('CZ_CHILD_SCRIPT', 'CZ_CHILD_PROXY', 'CZ_CHILD_PROXY_USER', 'CZ_CHILD_PROXY_PASS')) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }; Remove-Item -LiteralPath $cf -Force -ErrorAction SilentlyContinue }
    }
  } catch { $why = "claude.ai could not be reached ($($_.Exception.Message))" }
  Refresh-Path
  if ((Find-Cmd 'claude') -or (Test-Path $claudeHome)) { Ok 'Claude Code installed' }
  elseif ($why) { Todo "Claude Code did not install: $why. Creatorize Suite is installed anyway and needs Claude Code to make videos: run this installer again once https://claude.ai opens in your browser." }
  else { Todo 'Claude Code did not install (its own installer ended without it; its lines are above). Creatorize Suite is installed anyway and needs Claude Code to make videos: run this installer again.' }
}

# ---- Creatorize Suite: the newest version (or, when updates are paused / the launcher repairs, the installed one), with
# every file checked against the release's own list; anything missing or changed = that exact version installed again ----
Step 'Creatorize Suite'
if ($env:CZ_SKIP_APP) { Note '(test: CZ_SKIP_APP set, app step skipped)' } else {
$inst = Installed-App
$current = $inst.version
$paused = Paused-Version
$bad = @()
if ($current) { $bad = @(Test-AppFiles $inst.manifest) }
$latest = $null; $heldTarget = $null
if ($Want -and $Want -notmatch '^\d+\.\d+\.\d+(-beta\.\d+)?$') { Stop-Install "CZ_INSTALL_VERSION is '$Want', which is not a version number like 0.26.0. Nothing was changed." }
if ($Want) { $target = if ($current -and (Cmp-Ver $current $Want) -ge 0) { $current } else { $Want } }
elseif ($current -and ($Keep -or $null -ne $paused)) { $target = $current }
elseif (-not $current -and $paused) { $target = $paused }
else {
  $latest = Release-Info $null
  if (-not $latest) { Stop-Install "could not reach the Creatorize Suite releases (https://github.com/$Owner/$Repo/releases). Check the internet connection and run the installer again." }
  $target = if ($current -and (Cmp-Ver $current $latest.version) -ge 0) { $current } else { $latest.version }
  # a version the update gate tested on this computer and did not install (the app's updates\held.json): a re-run of
  # this installer or Repair keeps the installed one instead of installing it untested (Fable review 2, P2-1)
  if ($current -and $target -ne $current -and (Held-Versions) -contains $target) { $heldTarget = $target; $target = $current }
}
$running = Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $AppExe }
if ($current -and $target -eq $current -and -not $bad.Count) {
  if ($Want) { Ok "Creatorize Suite $current is installed and complete (every file checked; the update you asked for is $Want)" }
  elseif ($heldTarget) { Ok "Creatorize Suite $current is complete. $heldTarget didn't pass its test on this computer, so it wasn't installed; a newer version is tested again by itself." }
  elseif ($null -ne $paused) { Ok "Creatorize Suite $current is complete. Updates are paused (you went back to it in the Creatorize Launcher): press Resume updates there to get newer versions." }
  elseif ($latest -and (Cmp-Ver $current $latest.version) -gt 0) { Ok "Creatorize Suite $current is installed (a test version, newer than $($latest.version)) and complete" }
  elseif ($Keep) { Ok "Creatorize Suite $current is complete (every file checked)" }
  else { Ok "Creatorize Suite $current is up to date" }
  if (-not $inst.manifest) { Note '(this version has no list of its files, so only its main files were checked)' }
} else {
  $what = if (-not $current) { "install Creatorize Suite $target" } elseif ($target -eq $current) { "put back the missing files of Creatorize Suite $current" } else { "update Creatorize Suite $current to $target" }
  if ($current -and $target -eq $current) { Warn "$($bad.Count) file(s) of Creatorize Suite $current are missing or changed ($(@($bad)[0..2] -join ', ')$(if ($bad.Count -gt 3) { ', ...' })): installing $current again" }
  if (-not $Want -and $null -ne $paused -and $target -eq $paused) { Note "Updates are paused (you went back to $paused in the Creatorize Launcher), so $paused it stays." }
  if ($running) {
    if ($env:CZ_FROM_LAUNCHER -and -not $OldLauncher) { Stop-Install "Creatorize Suite is open, so the launcher could not $what. Close Creatorize Suite and press Repair again." }
    Todo "Creatorize Suite $current is open, so the installer did not $what. Close it and run the installer again$(if ($target -ne $current) { ' (or it updates itself when you close it)' })."
  }
  elseif ($DryRun) { Note "(test mode) would $what" }
  else {
    $rel = if ($latest -and $latest.version -eq $target) { $latest } else { Release-Info $target }
    if (-not $rel -and $Keep -and $null -eq $paused) {
      # the launcher's Repair, and this version is no longer published (pulled): the newest one instead
      Warn "Creatorize Suite $target is not published any more: installing the newest version instead"
      $rel = Release-Info $null
      # (never a version the update gate held on this computer, here either: Fable review 2, pass 3, P3-2)
      if ($rel -and (Held-Versions) -contains $rel.version) { Todo "the newest version, $($rel.version), didn't pass its test on this computer, so it wasn't installed; Creatorize Suite $current stays as it is. A newer version is tested again by itself."; $rel = 'held' }
    }
    if ($rel -eq 'held') { }
    elseif (-not $rel) { Stop-Install "could not find Creatorize Suite $target on https://github.com/$Owner/$Repo/releases. Check the internet connection and run the installer again." }
    else { Install-Suite $rel $current }
  }
}
}

# ---- Creatorize Launcher: watches every start and fixes a window that doesn't show; update, go back, repair ----
Step 'Creatorize Launcher'
$LExe = Join-Path $env:LOCALAPPDATA 'Programs\creatorize-launcher\Creatorize Launcher.exe'
if ($env:CZ_FROM_LAUNCHER) { Ok 'the launcher is running this repair, so it stays as it is' }
elseif ($env:CZ_SKIP_APP) { Note '(test: CZ_SKIP_APP set, launcher step skipped)' }
else {
  $info = $null
  try { $info = Web-Get "https://github.com/$Owner/creatorize/releases/latest/download/launcher.json" | ConvertFrom-Json } catch { $info = $null }
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
      Web-File "https://github.com/$Owner/creatorize/releases/latest/download/$($info.windows)" $setup
      $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
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
if ($Left.Count) {
  Write-Host "Finished, with $($Left.Count) thing(s) left to do:" -ForegroundColor Yellow
  foreach ($t in $Left) { Write-Host "  - $t" -ForegroundColor Yellow }
  Write-Host 'Run the same command again any time to update or repair.' -ForegroundColor White
} else { Write-Host 'All set. Run the same command again any time to update or repair.' -ForegroundColor White }
}
catch {
  $stopped = $true
  if ("$_" -ne 'CZ_STOP') { Write-Host ''; Write-Host "Install stopped: $_" -ForegroundColor Red }
}
# (a launcher from before this installer reads any code but 0 as "Repair stopped": its "left to do" ends with 0)
$code = if ($stopped) { 1 } elseif ($Left.Count -and -not $OldLauncher) { 3 } else { 0 }
# run as a file (the launcher's Repair, scripts, CI): the exit code. Through irm | iex: $LASTEXITCODE only (`exit` there
# would close the member's PowerShell window)
if ($PSCommandPath -or $env:CZ_FROM_LAUNCHER) { exit $code }
$global:LASTEXITCODE = $code
}
# CZ-INSTALLER-END (the Creatorize Launcher's Repair runs a fetched copy only when this last line arrived)
