# ⚡ PowerShell Intune & Entra ID Automation Suite

A collection of PowerShell administration, security auditing, and automation scripts for **Microsoft Intune**, **Entra ID (Azure AD)**, and **Windows Endpoints**.

---

## 📁 Repository Structure & Modules

```text
├── AzureAD-EntraID/                              # Identity & Tenant Governance
│   ├── AAD-nested-groups.ps1                    # Recursive group traversal & bulk license/app assignment
│   ├── check-license.ps1                        # M365 license availability monitor & threshold alerts
│   ├── Get-AllSmsUsers.ps1                      # Thread-safe parallel MFA security audit (SMS-only vs Strong)
│   └── stale-devices.ps1                        # Safe inactive Entra device cleanup with -WhatIf support
├── intune scripts/                              # Device Management & Provisioning
│   ├── autopilot stuff/
│   │   └── Set-AutopilotTags.ps1                # Automated Autopilot GroupTag bulk assignment
│   └── windows activation/
│       ├── detection.ps1                        # Intune Proactive Remediation: KMS license detection
│       └── remediation.ps1                      # Intune Proactive Remediation: BIOS OEM key activation
├── random-scripts-for-techcommunity/            # Operational Tools
│   ├── event-email-alert.ps1                    # Event Log monitor & automated alert dispatch
│   ├── mg-audit-logs.ps1                        # Microsoft Graph audit log extractor
│   ├── rotating-apps-and-tabs.ps1               # Kiosk automation rotating active applications & browser tabs
│   └── services-not-run-by-localsystem.ps1      # Service account security audit (discovers non-SYSTEM services)
└── random-scripts/
    └── new-gitlabrunner.ps1                     # Unattended GitLab Runner setup & registration
```

---

## 🚀 Key Scripts Documentation

### 1. Entra ID License Availability Monitor (`check-license.ps1`)
Monitors all subscribed SKUs in the tenant and identifies licenses running out of available units:
```powershell
.\check-license.ps1 -Threshold 5
```

### 2. Inactive Device Lifecycle Cleanup (`stale-devices.ps1`)
Safely identifies and deletes stale Entra ID devices inactive for more than a given number of days. Supports `-WhatIf` to preview changes:
```powershell
# Preview what would be removed
.\stale-devices.ps1 -DaysInactive 180 -WhatIf

# Execute cleanup
.\stale-devices.ps1 -DaysInactive 180
```

### 3. SMS & Weak MFA Auditor (`Get-AllSmsUsers.ps1`)
Performs a high-speed, thread-safe parallel evaluation of user authentication methods and generates CSV reports in `C:\Temp`:
- `usersWithOnlySMS.csv` — Users relying solely on SMS (telephony) authentication.
- `usersWithNoMFA.csv` — Users with zero registered MFA methods.

```powershell
.\Get-AllSmsUsers.ps1 -OutputFolder "C:\Reports" -ThrottleLimit 10
```

### 4. Windows Activation Remediation (`windows activation/`)
Intune Proactive Remediation package designed to remediate machines mistakenly activated against KMS back to their digital BIOS/UEFI embedded OEM product key:
- **Detection**: Checks if the active licensing product is a KMS volume channel (`exit 1` to trigger remediation).
- **Remediation**: Retrieves OEM key via ACPI MSDM (`OA3xOriginalProductKey`), clears KMS server cache, registers the OEM key, activates online, and returns `exit 0`.

### 5. Nested Group License & App Roles (`AAD-nested-groups.ps1`)
Recursively traverses complex Entra group hierarchies down to active leaf groups and assigns licenses or Enterprise Application roles in batch:
```powershell
. .\AAD-nested-groups.ps1
Grant-LicenseToSubgroups -TopGroupName "All-Marketing-Hierarchy" -LicenseName "SPE_E5"
```

---

## 🔑 Prerequisites & Scopes
All Graph-enabled scripts automatically verify your session and request least-privilege scopes as needed:
- `Organization.Read.All`
- `Device.ReadWrite.All`
- `User.Read.All`
- `UserAuthenticationMethod.Read.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
