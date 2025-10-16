param(
  [Parameter(Position=0, ValueFromRemainingArguments=$true)]
  [string[]]$Items,
  [Parameter()] [string]$Target,
  [int]$Threads = 32,
  [switch]$Unbuffered, [switch]$Restartable, [switch]$IncludeSubdirs,
  [string]$LogDir = "$env:USERPROFILE\Documents\FastCopyLogs",
  [switch]$ForcePrompt             # <-- add this
)

$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'

# --- SendTo guardrails ---
$ExplicitTarget = $PSBoundParameters.ContainsKey('Target')
if (-not $Items) { $Items = @() }

# If Target was NOT explicitly named but looks like a path, treat it as source
if (-not $ExplicitTarget -and $Target -and (Test-Path -LiteralPath $Target)) {
  $Items += (Resolve-Path -LiteralPath $Target).Path
  $Target = $null
}

# Sweep any raw unbound args (extra SendTo paths) into Items
foreach ($a in $args) {
  if (Test-Path -LiteralPath $a) {
    $Items += (Resolve-Path -LiteralPath $a).Path
  }
}
$Items = $Items | Sort-Object -Unique

# --- Logging setup ---
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$stamp  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$logAll = Join-Path $LogDir ("FastCopy_{0}.log" -f $stamp)
$rcLog  = Join-Path $LogDir ("Robocopy_{0}.log" -f $stamp)
Start-Transcript -Path $logAll -Force | Out-Null
function Info($m){ Write-Host "[INFO] $m" }

try {
  Info "FastCopy started at $(Get-Date)"
  Info "Args: Items=$($Items -join ' | '); Target=$Target; Threads=$Threads; Unbuffered=$Unbuffered; Restartable=$Restartable; IncludeSubdirs=$IncludeSubdirs"

  Add-Type -AssemblyName System.Windows.Forms | Out-Null

  function Pick-Target {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose destination for Fast Copy (Robocopy)"
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    throw "Destination selection canceled."
  }

  if (-not $Target) {
  if (-not $ForcePrompt) {
    try {
      $last = Get-ItemProperty HKCU:\Software\FastCopy -Name LastTarget -ErrorAction SilentlyContinue
      if ($last -and (Test-Path -LiteralPath $last.LastTarget)) { $Target = $last.LastTarget }
    } catch {}
  }
  if (-not $Target) { $Target = Pick-Target }
}

  New-Item -Path HKCU:\Software\FastCopy -Force | Out-Null
  Set-ItemProperty -Path HKCU:\Software\FastCopy -Name LastTarget -Value $Target -Force

  if (-not (Test-Path -LiteralPath $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
  }

  if (-not $Items -or $Items.Count -eq 0) {
    # No sources captured? Let user pick files manually.
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Multiselect = $true
    $ofd.Title = "Pick files to Fast Copy (Ctrl/Shift for multiple)"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
      $Items = $ofd.FileNames
    } else {
      throw "No items selected."
    }
  }

  # Resolve to full paths
  $resolved = foreach ($i in $Items) {
    if (Test-Path -LiteralPath $i) { (Get-Item -LiteralPath $i).FullName }
  }
  $resolved = $resolved | Sort-Object -Unique
  if ($resolved.Count -eq 0) { throw "No valid source items were provided." }

  Info "Target: $Target"
  Info "Resolved items:`n - " + ($resolved -join "`n - ")

  # Common robocopy switches
  $switches = @("/R:1","/W:1","/MT:{0}" -f $Threads,"/ETA")
  if ($Unbuffered)  { $switches += "/J" }
  if ($Restartable) { $switches += "/Z" }

  foreach ($src in $resolved) {
    $item = Get-Item -LiteralPath $src
    if ($item.PSIsContainer) {
      # Folder → copy into Target\<foldername>
      $destFolder = Join-Path -Path $Target -ChildPath $item.Name
      if (-not (Test-Path -LiteralPath $destFolder)) { New-Item -ItemType Directory -Path $destFolder -Force | Out-Null }
      $args = @('"' + $item.FullName + '"', '"' + $destFolder + '"')
      if ($IncludeSubdirs) { $args += "/E" }
      $args += $switches
      $args += @('/LOG+:"{0}"' -f $rcLog)
      Info "Folder → $($item.FullName)  →  $destFolder"
      $p = Start-Process -FilePath robocopy.exe -ArgumentList ($args -join ' ') -NoNewWindow -PassThru
      $p.WaitForExit()
      if ($p.ExitCode -ge 8) { throw "Robocopy failed with exit code $($p.ExitCode). See $rcLog" }
    } else {
      # File → keep filename in Target
      $parent = $item.DirectoryName
      $args = @('"' + $parent + '"', '"' + $Target + '"', '"' + $item.Name + '"')
      $args += $switches
      $args += @('/LOG+:"{0}"' -f $rcLog)
      Info "File   → $($item.FullName)  →  $Target"
      $p = Start-Process -FilePath robocopy.exe -ArgumentList ($args -join ' ') -NoNewWindow -PassThru
      $p.WaitForExit()
      if ($p.ExitCode -ge 8) { throw "Robocopy failed with exit code $($p.ExitCode). See $rcLog" }
    }
  }

  Info "Fast Copy finished successfully."
  Info "Robocopy log: $rcLog"
}
catch {
  $err = $_
  Write-Error ("ERROR: " + $err.Exception.Message)
  if ($err.InvocationInfo) { Write-Error ("At: " + $err.InvocationInfo.PositionMessage) }
  Write-Error ("Full error: " + $err)
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    [System.Windows.Forms.MessageBox]::Show("Fast Copy failed. See log:`n$logAll","Fast Copy (Robocopy)",'OK','Error') | Out-Null
  } catch {}
  exit 1
}
finally {
  Stop-Transcript | Out-Null
}