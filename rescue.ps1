# Creatorize Suite rescue for Windows: for a Creatorize window that stays dark or empty (or won't open at all).
#   irm https://raw.githubusercontent.com/therussellchris/creatorize/main/rescue.ps1 | iex
# Closes Creatorize Suite, updates it if a newer version is out, then starts it in Safe display mode (3D previews and
# exports still run on the graphics card, only the window is shown a safer way). Projects, settings and the Skool login
# are not touched. Still dark after that? Run it with software graphics (slower, always shows):
#   $env:CZ_RESCUE='software'; irm https://raw.githubusercontent.com/therussellchris/creatorize/main/rescue.ps1 | iex
# Source: installer/rescue.ps1 in the Creatorize Suite code repo (published by scripts/publish-installer.mjs).
# Keep this file plain ASCII: Windows PowerShell 5.1 runs it through `irm | iex`.

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Owner = 'therussellchris'
$Repo = 'creatorize-suite-releases'
$AppDir = Join-Path $env:LOCALAPPDATA 'Programs\creatorize-suite'
$AppExe = Join-Path $AppDir 'Creatorize Suite.exe'
$DryRun = [bool]$env:CZ_INSTALL_DRY    # test mode: detect and report, change nothing
$Software = $env:CZ_RESCUE -eq 'software'

function Step($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor White }
function Ok($t) { Write-Host "    [ok] $t" -ForegroundColor Green }
function Note($t) { Write-Host "    $t" -ForegroundColor DarkGray }
function Warn($t) { Write-Host "    [!] $t" -ForegroundColor Yellow }
function Ver($v) { try { [version](($v -replace '-.*$', '') -replace '\.0$', '') } catch { $null } }

try {
Write-Host 'Creatorize Suite rescue' -ForegroundColor White
Note 'Your projects, settings and Skool login stay as they are.'
if ($DryRun) { Warn 'Test mode (CZ_INSTALL_DRY): nothing is closed, installed or changed.' }
if (-not (Test-Path $AppExe) -and -not $DryRun) {
  Write-Host ''; Write-Host 'Creatorize Suite is not installed on this computer. Install it with:' -ForegroundColor Red
  Write-Host "  irm https://raw.githubusercontent.com/$Owner/creatorize/main/install.ps1 | iex"; throw 'CZ_STOP'
}

Step 'Closing Creatorize Suite'
$procs = @(Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue)
if (-not $procs.Count) { Ok 'it was not running' }
elseif ($DryRun) { Note "(test mode) would close $($procs.Count) Creatorize Suite process(es)" }
else {
  $procs | Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 20 -and (Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
  if (Get-Process -Name 'Creatorize Suite' -ErrorAction SilentlyContinue) { Warn 'it is still closing; restart the computer if the next steps fail' } else { Ok 'closed' }
}

Step 'Updating Creatorize Suite'
$current = $null
if (Test-Path $AppExe) { $current = ((Get-Item $AppExe).VersionInfo.ProductVersion -replace '\.0$', '') }
try {
  $yml = (Invoke-WebRequest "https://github.com/$Owner/$Repo/releases/latest/download/latest.yml" -UseBasicParsing).Content
  if ($yml -is [byte[]]) { $yml = [Text.Encoding]::UTF8.GetString($yml) }
  $latest = [regex]::Match($yml, '(?m)^version:\s*(\S+)').Groups[1].Value
  $file = [regex]::Match($yml, '(?m)^path:\s*(\S+)').Groups[1].Value
} catch { $latest = $null; Warn 'could not reach the Creatorize Suite releases, so it was not updated (it is started anyway)' }
if ($latest -and $file) {
  if ($current -and (Ver $current) -ge (Ver $latest)) { Ok "Creatorize Suite $current is up to date" }
  elseif ($DryRun) { Note "(test mode) would install Creatorize Suite $latest (installed: $current)" }
  else {
    $dl = Join-Path $env:LOCALAPPDATA ('Creatorize Setup\' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $setup = Join-Path $dl $file
    Note "Downloading Creatorize Suite $latest ..."
    Invoke-WebRequest "https://github.com/$Owner/$Repo/releases/download/v$latest/$file" -OutFile $setup -UseBasicParsing
    Note 'Installing ...'
    $p = Start-Process $setup -ArgumentList '/S' -Wait -PassThru
    Remove-Item $dl -Recurse -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -eq 0 -and (Test-Path $AppExe)) { $current = ((Get-Item $AppExe).VersionInfo.ProductVersion -replace '\.0$', ''); Ok "Creatorize Suite $current installed" }
    else { Warn "the update did not finish (code $($p.ExitCode)); starting the installed version" }
  }
}

Step 'Starting Creatorize Suite'
# Safe display (--safe-graphics) exists from 0.15.2, software graphics (--software-graphics) from 0.15.0
$v = Ver $current
if ($Software -or ($v -and $v -lt [version]'0.15.2')) { $flag = '--software-graphics'; $how = 'software graphics (slower, but it always shows; switch back in Settings > System > Graphics)' }
else { $flag = '--safe-graphics'; $how = 'Safe display (3D still on your graphics card)' }
if ($v -and $v -lt [version]'0.15.0') { Warn "this version ($current) is too old for the rescue start: run this again when you are online to update it"; $flag = $null; $how = 'normal mode' }
if ($DryRun) { Note "(test mode) would start Creatorize Suite $(if ($flag) { $flag })" }
else {
  if ($flag) { Start-Process $AppExe -ArgumentList $flag } else { Start-Process $AppExe }
  Ok "Started in $how"
}
Write-Host ''
Write-Host 'Done. Still dark or empty after a minute? Close it and run this instead (slower graphics that always show):' -ForegroundColor White
Write-Host "  `$env:CZ_RESCUE='software'; irm https://raw.githubusercontent.com/$Owner/creatorize/main/rescue.ps1 | iex"
}
catch { if ("$_" -ne 'CZ_STOP') { Write-Host ''; Write-Host "Rescue stopped: $_" -ForegroundColor Red } }
}
