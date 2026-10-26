<#
.SYNOPSIS
    Automated installation, registration, and service configuration of GitLab Runner on Windows.
.DESCRIPTION
    Installs GitLab Runner, Git, required PowerShell modules, registers the runner with GitLab,
    and starts the service under local system or a dedicated service account.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitLabUrl,
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$RunnerName = "$($env:COMPUTERNAME)-runner",
    [string]$Tags = "windows,powershell",
    [string]$InstallPath = "C:\GitLab-Runner",
    [string]$ServiceUser,
    [string]$ServicePassword,
    [string[]]$Modules = @("Az", "SqlServer", "Microsoft.Graph", "Microsoft.PowerShell.SecretManagement")
)

# 1. Administrator Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# 2. Setup Directory
if (-not (Test-Path $InstallPath)) {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}
Set-Location $InstallPath

# 3. Install Git if missing
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Git for Windows..." -ForegroundColor Cyan
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git --silent --accept-source-agreements --accept-package-agreements
    } else {
        $gitInstaller = "$env:TEMP\git-setup.exe"
        Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" -OutFile $gitInstaller
        Start-Process $gitInstaller -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-" -Wait
        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
    }
}

# 4. Download GitLab Runner Binary
$runnerExe = Join-Path $InstallPath "gitlab-runner.exe"
if (-not (Test-Path $runnerExe)) {
    Write-Host "Downloading latest 64-bit GitLab Runner..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe" -OutFile $runnerExe
}

# 5. Register the Runner FIRST before service install
Write-Host "Registering Runner with GitLab ($GitLabUrl)..." -ForegroundColor Cyan
& $runnerExe register `
    --non-interactive `
    --url $GitLabUrl `
    --registration-token $RegistrationToken `
    --name $RunnerName `
    --tag-list $Tags `
    --executor "shell" `
    --shell "powershell"

# 6. Install and Start the Service
Write-Host "Configuring GitLab Runner Windows Service..." -ForegroundColor Cyan
if ($ServiceUser -and $ServicePassword) {
    & $runnerExe install --user $ServiceUser --password $ServicePassword
} else {
    & $runnerExe install
}

Start-Sleep -Seconds 2
& $runnerExe start
Write-Host "GitLab Runner service started successfully!" -ForegroundColor Green

# 7. Install Required Modules
Write-Host "Verifying PowerShell modules..." -ForegroundColor Cyan
foreach ($mod in $Modules) {
    if (-not (Get-Module -Name $mod -ListAvailable)) {
        Write-Host "Installing module '$mod'..." -ForegroundColor Yellow
        Install-Module -Name $mod -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue
    }
}

Write-Host "GitLab Runner setup complete." -ForegroundColor Green
