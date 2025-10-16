param(
  [string]$InstallPath = "$env:USERPROFILE\Scripts",
  [switch]$AddBackgroundMenu
)

$ErrorActionPreference = 'Stop'

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$fastCopySrc = Join-Path $srcDir "FastCopy.ps1"
if (-not (Test-Path -LiteralPath $fastCopySrc)) {
  throw "FastCopy.ps1 not found next to the installer: $fastCopySrc"
}

if (-not (Test-Path -LiteralPath $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null }
$fastCopyDst = Join-Path $InstallPath "FastCopy.ps1"
Copy-Item -LiteralPath $fastCopySrc -Destination $fastCopyDst -Force

$sendTo = Join-Path $env:APPDATA "Microsoft\Windows\SendTo"
if (-not (Test-Path -LiteralPath $sendTo)) { New-Item -ItemType Directory -Path $sendTo -Force | Out-Null }

$pwsh = (Get-Command pwsh).Source

# REGULAR shortcut (prompts every time)
$lnk1 = Join-Path $sendTo "Fast Copy (Robocopy).lnk"
$wsh  = New-Object -ComObject WScript.Shell
$sc1  = $wsh.CreateShortcut($lnk1)
$sc1.TargetPath  = $pwsh
$sc1.Arguments   = "-NoProfile -ExecutionPolicy Bypass -File `"$fastCopyDst`" -IncludeSubdirs -Unbuffered -ForcePrompt"
$sc1.WindowStyle = 1
$sc1.IconLocation= "shell32.dll,44"
$sc1.Save()

# DEBUG shortcut (keeps console open)
$lnk2 = Join-Path $sendTo "Fast Copy (DEBUG).lnk"
$sc2  = $wsh.CreateShortcut($lnk2)
$sc2.TargetPath  = $pwsh
$sc2.Arguments   = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$fastCopyDst`" -IncludeSubdirs -Unbuffered -ForcePrompt"
$sc2.WindowStyle = 1
$sc2.IconLocation= "shell32.dll,44"
$sc2.Save()

Write-Host "SendTo shortcuts installed:" -ForegroundColor Green
Write-Host "  - $lnk1" -ForegroundColor Green
Write-Host "  - $lnk2" -ForegroundColor Yellow

if ($AddBackgroundMenu) {
  $key = "HKCU:\Software\Classes\Directory\Background\shell\FastPasteRobocopy"
  $cmd = Join-Path $key "command"
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name "MUIVerb" -Value "Fast Paste here (Robocopy)" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name "Icon" -Value "shell32.dll,44" -PropertyType String -Force | Out-Null
  New-Item -Path $cmd -Force | Out-Null
    $command = ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Target "%V" -IncludeSubdirs -Unbuffered -Threads 32' -f $pwsh, $fastCopyDst)
  Set-ItemProperty -Path $cmd -Name "(default)" -Value $command -Force
  Write-Host "Background context menu installed: Fast Paste here (Robocopy)" -ForegroundColor Green
}

Write-Host "Done." -ForegroundColor Green
