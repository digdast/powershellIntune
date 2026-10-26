<#
.SYNOPSIS
    Intune Proactive Remediation - Detection Script for Windows Activation
.DESCRIPTION
    Checks whether Windows is activated using KMS or lacks valid digital license.
    Exits with 1 if remediation is required; exits with 0 if already properly licensed.
#>

try {
    # Query active licensing product with partial key
    $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction Stop |
               Where-Object { $_.Name -like "*Windows*" } | Select-Object -First 1

    if (-not $license) {
        Write-Output "No active Windows license product detected. Triggering remediation."
        exit 1
    }

    # LicenseStatus 1 = Licensed
    $isLicensed = ($license.LicenseStatus -eq 1)
    $isKms = ($license.Description -like "*KMS*" -or $license.Description -like "*VOLUME_KMS*")

    if ($isKms) {
        Write-Output "KMS Volume license detected ($($license.Description)). Remediation needed to switch to Digital/OEM."
        exit 1
    }

    if (-not $isLicensed) {
        Write-Output "Windows is not in a licensed state (Status: $($license.LicenseStatus)). Remediation required."
        exit 1
    }

    Write-Output "Windows is permanently activated with non-KMS license: $($license.Description)"
    exit 0
}
catch {
    Write-Output "Error querying activation status: $($_.Exception.Message)"
    exit 1
}