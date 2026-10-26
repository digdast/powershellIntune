<#
.SYNOPSIS
    Assigns an Autopilot GroupTag to Windows Autopilot enrolled devices that lack tags.
.DESCRIPTION
    Uses Microsoft Graph DeviceManagement module to query and update Autopilot Device Identities.
.PARAMETER GroupTag
    The group tag to assign to untagged devices. Default is "Standard".
.EXAMPLE
    .\Set-AutopilotTags.ps1 -GroupTag "Kiosk-Devices"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GroupTag = "Standard",
    [switch]$IncludeMissingPurchaseOrder
)

# Connect to Microsoft Graph
$context = Get-MgContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "DeviceManagementServiceConfig.ReadWrite.All" -NoWelcome
}

Write-Host "Retrieving Windows Autopilot enrolled devices..." -ForegroundColor Cyan
try {
    $devices = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -All -ErrorAction Stop
}
catch {
    Write-Error "Failed to retrieve Autopilot devices: $($_.Exception.Message)"
    return
}

if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "No Autopilot devices registered in this tenant." -ForegroundColor Yellow
    return
}

# Filter untagged devices
$targetDevices = $devices | Where-Object {
    $missingTag = [string]::IsNullOrWhiteSpace($_.GroupTag)
    if ($IncludeMissingPurchaseOrder) {
        $missingTag -or [string]::IsNullOrWhiteSpace($_.PurchaseOrderIdentifier)
    } else {
        $missingTag
    }
}

Write-Host "Found $($targetDevices.Count) device(s) requiring GroupTag assignment." -ForegroundColor Cyan

$updatedCount = 0
foreach ($dev in $targetDevices) {
    $devName = if ($dev.SerialNumber) { $dev.SerialNumber } else { $dev.Id }
    
    if ($PSCmdlet.ShouldProcess("Serial: $devName (Current Tag: '$($dev.GroupTag)')", "Set GroupTag to '$GroupTag'")) {
        try {
            Update-MgDeviceManagementWindowsAutopilotDeviceIdentity `
                -WindowsAutopilotDeviceIdentityId $dev.Id `
                -GroupTag $GroupTag `
                -ErrorAction Stop

            Write-Host "[UPDATED] Serial: $devName -> GroupTag: '$GroupTag'" -ForegroundColor Green
            $updatedCount++
        }
        catch {
            Write-Warning "Failed to update $devName : $($_.Exception.Message)"
        }
    }
}

Write-Host "`nCompleted: Successfully assigned GroupTag to $updatedCount device(s)." -ForegroundColor Green
