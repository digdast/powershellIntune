<#
.SYNOPSIS
    Module for managing nested Entra ID (Azure AD) groups, license assignment, and Enterprise App role assignments.
.DESCRIPTION
    Provides recursive group traversal without redundant API calls, and supports batch license and enterprise app assignments.
#>

# Requires Microsoft.Graph.Groups, Microsoft.Graph.Applications, Microsoft.Graph.Users

function Get-Subgroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$GroupId
    )

    $group = Get-MgGroup -GroupId $GroupId -ErrorAction Stop
    $groups = [System.Collections.Generic.List[PSObject]]::new()

    if ($group) {
        $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction SilentlyContinue

        foreach ($member in $members) {
            $type = $member.AdditionalProperties['@odata.type']
            
            if ($type -match 'microsoft.graph.user') {
                # If member is a user, the current parent group contains active users
                if (-not ($groups | Where-Object { $_.Id -eq $group.Id })) {
                    $groups.Add([PSCustomObject]@{
                        Id          = $group.Id
                        DisplayName = $group.DisplayName
                    })
                }
            }
            elseif ($type -match 'microsoft.graph.group') {
                # If member is a group, recursively traverse
                $nested = Get-Subgroups -GroupId $member.Id
                foreach ($n in $nested) {
                    if (-not ($groups | Where-Object { $_.Id -eq $n.Id })) {
                        $groups.Add($n)
                    }
                }
            }
        }
    }

    return $groups
}

function Grant-LicenseToSubgroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TopGroupName,
        [Parameter(Mandatory = $true)]
        [string]$LicenseName
    )

    $topGroup = Get-MgGroup -Filter "displayName eq '$TopGroupName'" -ErrorAction Stop
    if (-not $topGroup) {
        Write-Error "Top-level group '$TopGroupName' not found."
        return
    }

    $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq $LicenseName
    if (-not $sku) {
        Write-Error "License SKU '$LicenseName' not found in tenant."
        return
    }

    $subgroups = Get-Subgroups -GroupId $topGroup.Id
    Write-Host "Found $($subgroups.Count) leaf subgroup(s) under '$TopGroupName'." -ForegroundColor Cyan

    foreach ($subgroup in $subgroups) {
        Write-Host "Assigning license '$LicenseName' to: $($subgroup.DisplayName)" -ForegroundColor Green
        try {
            Set-MgGroupLicense -GroupId $subgroup.Id -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @() -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to assign license to '$($subgroup.DisplayName)': $($_.Exception.Message)"
        }
    }
}

function Revoke-LicenseFromSubgroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TopGroupName,
        [Parameter(Mandatory = $true)]
        [string]$LicenseName
    )

    $topGroup = Get-MgGroup -Filter "displayName eq '$TopGroupName'" -ErrorAction Stop
    if (-not $topGroup) {
        Write-Error "Top-level group '$TopGroupName' not found."
        return
    }

    $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq $LicenseName
    if (-not $sku) {
        Write-Error "License SKU '$LicenseName' not found in tenant."
        return
    }

    $subgroups = Get-Subgroups -GroupId $topGroup.Id
    Write-Host "Found $($subgroups.Count) leaf subgroup(s) under '$TopGroupName'." -ForegroundColor Cyan

    foreach ($subgroup in $subgroups) {
        Write-Host "Revoking license '$LicenseName' from: $($subgroup.DisplayName)" -ForegroundColor Yellow
        try {
            Set-MgGroupLicense -GroupId $subgroup.Id -AddLicenses @() -RemoveLicenses @($sku.SkuId) -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to revoke license from '$($subgroup.DisplayName)': $($_.Exception.Message)"
        }
    }
}

function Add-SubgroupsToEnterpriseApp {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$EnterpriseAppId,
        [Parameter()]
        [string]$EnterpriseAppName,
        [Parameter()]
        [string]$TopGroupName,
        [Parameter()]
        [string]$TopGroupId
    )

    try {
        # Resolve Service Principal
        if ($EnterpriseAppId) {
            $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$EnterpriseAppId'" -ErrorAction Stop
        }
        elseif ($EnterpriseAppName) {
            $servicePrincipal = Get-MgServicePrincipal -Filter "displayName eq '$EnterpriseAppName'" -ErrorAction Stop
        }
        else {
            Write-Error "Must provide EnterpriseAppId or EnterpriseAppName."
            return
        }

        if (-not $servicePrincipal) {
            Write-Error "Service Principal not found."
            return
        }

        # Resolve Top Group
        if (-not $TopGroupId -and $TopGroupName) {
            $topGroup = Get-MgGroup -Filter "displayName eq '$TopGroupName'" -ErrorAction Stop
            $TopGroupId = $topGroup.Id
        }

        if (-not $TopGroupId) {
            Write-Error "Top-level group ID could not be resolved."
            return
        }

        $appRole = $servicePrincipal.AppRoles | Where-Object { $_.DisplayName -eq "User" -or $_.Value -eq "User" } | Select-Object -First 1
        $appRoleId = if ($appRole) { $appRole.Id } else { [Guid]::Empty.ToString() }

        $subgroups = Get-Subgroups -GroupId $TopGroupId
        Write-Host "Assigning $($subgroups.Count) subgroup(s) to Enterprise App '$($servicePrincipal.DisplayName)'..." -ForegroundColor Cyan

        foreach ($subgroup in $subgroups) {
            try {
                $params = @{
                    PrincipalId = $subgroup.Id
                    ResourceId  = $servicePrincipal.Id
                    AppRoleId   = $appRoleId
                }
                New-MgGroupAppRoleAssignment -GroupId $subgroup.Id -BodyParameter $params -ErrorAction Stop | Out-Null
                Write-Host "Assigned subgroup '$($subgroup.DisplayName)' to app '$($servicePrincipal.DisplayName)'." -ForegroundColor Green
            }
            catch {
                Write-Warning "Could not assign subgroup '$($subgroup.DisplayName)': $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Error "Error in Add-SubgroupsToEnterpriseApp: $($_.Exception.Message)"
    }
}

function Remove-SubgroupsFromEnterpriseApp {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$EnterpriseAppId,
        [Parameter()]
        [string]$EnterpriseAppName,
        [Parameter()]
        [string]$TopGroupName,
        [Parameter()]
        [string]$TopGroupId
    )

    try {
        if ($EnterpriseAppId) {
            $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$EnterpriseAppId'" -ErrorAction Stop
        }
        elseif ($EnterpriseAppName) {
            $servicePrincipal = Get-MgServicePrincipal -Filter "displayName eq '$EnterpriseAppName'" -ErrorAction Stop
        }
        else {
            Write-Error "Must provide EnterpriseAppId or EnterpriseAppName."
            return
        }

        if (-not $TopGroupId -and $TopGroupName) {
            $topGroup = Get-MgGroup -Filter "displayName eq '$TopGroupName'" -ErrorAction Stop
            $TopGroupId = $topGroup.Id
        }

        $subgroups = Get-Subgroups -GroupId $TopGroupId
        Write-Host "Removing assignments for $($subgroups.Count) subgroup(s) from '$($servicePrincipal.DisplayName)'..." -ForegroundColor Cyan

        foreach ($subgroup in $subgroups) {
            $assignments = Get-MgGroupAppRoleAssignment -GroupId $subgroup.Id -All | Where-Object { $_.ResourceId -eq $servicePrincipal.Id }
            foreach ($assignment in $assignments) {
                try {
                    Remove-MgGroupAppRoleAssignment -GroupId $subgroup.Id -AppRoleAssignmentId $assignment.Id -ErrorAction Stop
                    Write-Host "Removed assignment for subgroup '$($subgroup.DisplayName)' from '$($servicePrincipal.DisplayName)'." -ForegroundColor Yellow
                }
                catch {
                    Write-Warning "Failed removing assignment: $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        Write-Error "Error in Remove-SubgroupsFromEnterpriseApp: $($_.Exception.Message)"
    }
}
