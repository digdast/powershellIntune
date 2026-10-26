<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation Script for Windows Activation
.DESCRIPTION
    Switches KMS-activated or unactivated Windows machines to OEM embedded digital license
    (from BIOS/UEFI MSDM table) or a provided MAK/Retail key, clearing KMS configuration
    and activating online against Microsoft activation servers.
.PARAMETER ProductKey
    Optional product key. If omitted, queries the hardware firmware MSDM embedded key.
#>
[CmdletBinding()]
param(
    [string]$ProductKey
)

try {
    # 1. Determine Product Key to use
    $keyToUse = $ProductKey

    if ([string]::IsNullOrWhiteSpace($keyToUse) -or $keyToUse -like "*<*>*") {
        Write-Output "Retrieving OEM product key embedded in UEFI/BIOS firmware..."
        $keyToUse = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
    }

    if ([string]::IsNullOrWhiteSpace($keyToUse)) {
        Write-Output "Error: No OEM firmware key found and no custom ProductKey specified."
        exit 1
    }

    Write-Output "Clearing KMS server cache and registry..."
    & slmgr.vbs //b /ckms
    Start-Sleep -Seconds 2

    Write-Output "Installing product key..."
    & slmgr.vbs //b /ipk $keyToUse
    Start-Sleep -Seconds 3

    Write-Output "Attempting online activation against Microsoft servers..."
    & slmgr.vbs //b /ato
    Start-Sleep -Seconds 5

    # Verify final activation status
    $activeProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
                     Where-Object { $_.Name -like "*Windows*" } | Select-Object -First 1

    if ($activeProduct -and $activeProduct.LicenseStatus -eq 1) {
        Write-Output "Windows successfully activated ($($activeProduct.Description))."
        exit 0
    } else {
        Write-Output "Activation attempted but system is not in a licensed state (Status: $($activeProduct.LicenseStatus))."
        exit 1
    }
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}