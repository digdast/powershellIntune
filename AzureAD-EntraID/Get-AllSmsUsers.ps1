<#
.SYNOPSIS
    Identifies active Entra ID users configured with SMS-only MFA or missing MFA entirely.
.DESCRIPTION
    Uses Microsoft Graph to audit user authentication methods. Uses thread-safe collections
    for fast parallel evaluation across large tenants and exports reports to CSV.
.PARAMETER OutputFolder
    Destination directory for audit CSV reports. Defaults to C:\Temp.
.PARAMETER ThrottleLimit
    Concurrency limit for parallel processing. Default is 8.
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = "C:\Temp",
    [int]$ThrottleLimit = 8
)

# Verify Graph Connection
$context = Get-MgContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "Connecting to Microsoft Graph with authentication method scopes..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "User.Read.All", "UserAuthenticationMethod.Read.All" -NoWelcome
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Write-Host "Fetching all active Entra ID users..." -ForegroundColor Cyan
$users = Get-MgUser -All -Filter "accountEnabled eq true" -Property Id, DisplayName, UserPrincipalName, MobilePhone -ErrorAction Stop

Write-Host "Evaluating authentication methods for $($users.Count) active users (ThrottleLimit: $ThrottleLimit)..." -ForegroundColor Cyan

# Use thread-safe ConcurrentBags for parallel aggregation
$usersWithOnlySMS = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
$usersWithNoMFA   = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

$total = $users.Count
$counter = [System.Threading.CountdownEvent]::new($total)

$users | ForEach-Object -Parallel {
    $user = $_
    $smsBag = $using:usersWithOnlySMS
    $noMfaBag = $using:usersWithNoMFA

    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop
        
        $hasAuthenticator = $false
        $hasPhone = $false
        $hasFido2 = $false
        $hasWindowsHello = $false

        foreach ($m in $methods) {
            $type = $m.AdditionalProperties['@odata.type']
            if ($type -match 'microsoftAuthenticatorAuthenticationMethod') { $hasAuthenticator = $true }
            elseif ($type -match 'phoneAuthenticationMethod') { $hasPhone = $true }
            elseif ($type -match 'fido2AuthenticationMethod') { $hasFido2 = $true }
            elseif ($type -match 'windowsHelloForBusinessAuthenticationMethod') { $hasWindowsHello = $true }
        }

        # Determine MFA posture
        $hasStrongMfa = $hasAuthenticator -or $hasFido2 -or $hasWindowsHello

        if (-not $hasPhone -and -not $hasStrongMfa) {
            $noMfaBag.Add([PSCustomObject]@{
                Id                = $user.Id
                UserPrincipalName = $user.UserPrincipalName
                DisplayName       = $user.DisplayName
                MobilePhone       = $user.MobilePhone
                MfaStatus         = "No MFA Configured"
            })
        }
        elseif ($hasPhone -and -not $hasStrongMfa) {
            $smsBag.Add([PSCustomObject]@{
                Id                = $user.Id
                UserPrincipalName = $user.UserPrincipalName
                DisplayName       = $user.DisplayName
                MobilePhone       = $user.MobilePhone
                MfaStatus         = "SMS Only (Weak MFA)"
            })
        }
    }
    catch {
        # Catch individual user permission or retrieval errors
    }
} -ThrottleLimit $ThrottleLimit

$smsCsv = Join-Path $OutputFolder "usersWithOnlySMS.csv"
$noMfaCsv = Join-Path $OutputFolder "usersWithNoMFA.csv"

$usersWithOnlySMS | Export-Csv -Path $smsCsv -NoTypeInformation -Encoding utf8
$usersWithNoMFA | Export-Csv -Path $noMfaCsv -NoTypeInformation -Encoding utf8

Write-Host "`n=== Audit Complete ===" -ForegroundColor Green
Write-Host "Users with SMS-only MFA: $($usersWithOnlySMS.Count) -> $smsCsv" -ForegroundColor Yellow
Write-Host "Users with NO MFA:       $($usersWithNoMFA.Count) -> $noMfaCsv" -ForegroundColor Red
