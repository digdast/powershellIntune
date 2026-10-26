<#
.SYNOPSIS
    Monitors Entra ID / Microsoft 365 license consumption and alerts on low availability.
.PARAMETER Threshold
    Number of remaining available licenses that triggers a warning. Default is 3.
.PARAMETER Exclude
    List of SkuPartNumbers to exclude from the check.
.EXAMPLE
    .\check-license.ps1 -Threshold 5
#>
[CmdletBinding()]
param(
    [int]$Threshold = 3,
    [string[]]$Exclude = @("VISIOCLIENT", "PROJECTPREMIUM", "MEETING_ROOM", "EMSPREMIUM_EDU_FACULTY", "PROJECTPROFESSIONAL", "RMSBASIC")
)

# Verify Graph Connection
$context = Get-MgContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Organization.Read.All" -NoWelcome
}

Write-Host "Checking tenant license availability (Alert threshold: <= $Threshold remaining)..." -ForegroundColor Cyan
$licenses = Get-MgSubscribedSku -All -ErrorAction Stop

$results = foreach ($sku in $licenses) {
    if ($sku.SkuPartNumber -in $Exclude) {
        continue
    }

    $enabled = [int]($sku.PrepaidUnits.Enabled)
    $consumed = [int]($sku.ConsumedUnits)
    $remaining = $enabled - $consumed
    $percentUsed = if ($enabled -gt 0) { [math]::Round(($consumed / $enabled) * 100, 1) } else { 0 }

    [PSCustomObject]@{
        SkuPartNumber = $sku.SkuPartNumber
        SkuId         = $sku.SkuId
        TotalEnabled  = $enabled
        Consumed      = $consumed
        Remaining     = $remaining
        PercentUsed   = "$percentUsed%"
        Status        = if ($remaining -le 0) { "EXHAUSTED" } elseif ($remaining -le $Threshold) { "CRITICAL" } else { "OK" }
    }
}

$runningOut = $results | Where-Object { $_.Remaining -le $Threshold }

Write-Host "`n=== All Monitored Tenant Licenses ===" -ForegroundColor Cyan
$results | Format-Table SkuPartNumber, TotalEnabled, Consumed, Remaining, PercentUsed, Status -AutoSize

if ($runningOut) {
    Write-Host "`n[WARNING] The following licenses are running low (<= $Threshold remaining):" -ForegroundColor Red
    $runningOut | Format-Table SkuPartNumber, Remaining, Consumed, TotalEnabled, Status -AutoSize
    return $runningOut
} else {
    Write-Host "`nAll licenses have sufficient headroom (> $Threshold remaining)." -ForegroundColor Green
}