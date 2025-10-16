<#
.SYNOPSIS
  SMB Performance Kit - Clean Version (Windows 10/11 build-safe)
.NOTES
  Run as Administrator
#>

# --- Safety Check ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Error "This script must be run as Administrator."
  exit 1
}

Write-Host "=== SMB Performance Kit (CLEAN) ===" -ForegroundColor Cyan

# --- System Info ---
Get-ComputerInfo | Select-Object WindowsProductName, OsVersion, OsBuildNumber | Format-List

# --- NIC performance features ---
Write-Host "`n[1/6] NIC Offloads (RSS/RSC/LSO)..." -ForegroundColor Yellow

Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
  try { Enable-NetAdapterRss -Name $_.Name -ErrorAction Stop } catch {}
}

Get-NetAdapterRsc | ForEach-Object {
  if (-not $_.IPv4Enabled) { try { Enable-NetAdapterRsc -Name $_.Name -IPv4 -ErrorAction Stop } catch {} }
  if (-not $_.IPv6Enabled) { try { Enable-NetAdapterRsc -Name $_.Name -IPv6 -ErrorAction Stop } catch {} }
}

Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled | Out-Null

# --- TCP Optimization (AutoTuning, Heuristics) ---
Write-Host "`n[2/6] TCP AutoTuning & Heuristics..." -ForegroundColor Yellow

try {
  Set-NetTCPSetting -SettingName Internet -AutoTuningLevel Normal -ScalingHeuristics Disabled -EcnCapability Disabled -Timestamps Disabled -ErrorAction Stop | Out-Null
} catch {
  Write-Host "Falling back to netsh..." -ForegroundColor DarkYellow
  netsh int tcp set global autotuninglevel=normal
  netsh int tcp set heuristics disabled
  netsh int tcp set global ecncapability=disabled timestamps=disabled
}

# --- SMB Client Tweaks ---
Write-Host "`n[3/6] SMB Client Tweaks..." -ForegroundColor Yellow

try { Set-SmbClientConfiguration -EnableLargeMtu $true -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
try { Set-SmbClientConfiguration -EnableSecuritySignature $false -Confirm:$false -ErrorAction Stop | Out-Null } catch {}

# --- SMB Server Tweaks (if applicable) ---
Write-Host "`n[4/6] SMB Server Tweaks..." -ForegroundColor Yellow

try { Set-SmbServerConfiguration -EnableMultiChannel $true -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
try { Set-SmbServerConfiguration -EncryptData $false -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
try { Set-SmbServerConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $false -Confirm:$false -ErrorAction Stop | Out-Null } catch {}

# --- Display SMB Status ---
Write-Host "`n[5/6] Current SMB Configuration..." -ForegroundColor Yellow

Get-SmbServerConfiguration | Select-Object EnableSMB2Protocol, EnableMultiChannel, EncryptData, RequireSecuritySignature, EnableSecuritySignature | Format-List
Get-SmbClientConfiguration | Select-Object EnableLargeMtu, EnableSecuritySignature, DirectoryCacheLifetime, FileInfoCacheLifetime | Format-List

# --- Multichannel Connections ---
Write-Host "`n[6/6] SMB Multichannel Connections..." -ForegroundColor Yellow
try { Get-SmbMultichannelConnection | Format-Table -AutoSize } catch {}

Write-Host "`nDONE. Use iperf3 and robocopy /MT to validate network." -ForegroundColor Green