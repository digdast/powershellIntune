<#
.SYNOPSIS
    Identifies and safely cleans up stale Entra ID (Azure AD) devices.
.DESCRIPTION
    Queries Microsoft Graph for devices that haven't signed in for a specified period (default: 180 days).
    Includes safety checks, logging, and -WhatIf support to prevent accidental bulk deletions.
.PARAMETER DaysInactive
    The threshold in days since the last approximate sign-in. Default is 180 days.
.PARAMETER Force
    Skips the interactive confirmation prompt.
.EXAMPLE
    .\stale-devices.ps1 -WhatIf
.EXAMPLE
    .\stale-devices.ps1 -DaysInactive 90
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$DaysInactive = 180,
    [switch]$Force
)

# Verify Graph Connection
$context = Get-MgContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Device.ReadWrite.All" -NoWelcome
}

# Calculate threshold date in UTC ISO 8601 format
$thresholdDate = (Get-Date).ToUniversalTime().AddDays(-$DaysInactive)
$formattedDate = $thresholdDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Querying Entra ID devices inactive since: $formattedDate ($DaysInactive days)..." -ForegroundColor Cyan
$devices = Get-MgDevice -Filter "approximateLastSignInDateTime le $formattedDate" -All -ErrorAction Stop

if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "No stale devices found inactive for more than $DaysInactive days." -ForegroundColor Green
    return
}

Write-Host "Found $($devices.Count) stale device(s)." -ForegroundColor Yellow
$devices | Select-Object Id, DisplayName, OperatingSystem, ApproximateLastSignInDateTime | Format-Table -AutoSize

if (-not $Force -and -not $WhatIfPreference) {
    $confirm = Read-Host "Are you sure you want to permanently delete these $($devices.Count) device(s)? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        return
    }
}

$successCount = 0
$failCount = 0

foreach ($device in $devices) {
    $deviceName = if ($device.DisplayName) { $device.DisplayName } else { $device.Id }
    if ($PSCmdlet.ShouldProcess("$deviceName (Last sign-in: $($device.ApproximateLastSignInDateTime))", "Remove device from Entra ID")) {
        try {
            Remove-MgDevice -DeviceId $device.Id -ErrorAction Stop
            Write-Host "[DELETED] $deviceName ($($device.Id))" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Warning "Failed to remove device '$deviceName': $($_.Exception.Message)"
            $failCount++
        }
    }
}

Write-Host "`nCleanup Complete: $successCount deleted, $failCount failed." -ForegroundColor Cyan