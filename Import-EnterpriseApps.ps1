#Requires -Modules Microsoft.Graph.Applications

param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Filter = "*",
    [switch]$Update,
    [switch]$WhatIf
)

Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome

$rows = Import-Csv $CsvPath | Where-Object { $_.DisplayName -like $Filter }
Write-Host "$($rows.Count) apps to process"

foreach ($row in $rows) {
    $existingSP  = Get-MgServicePrincipal -Filter "appId eq '$($row.AppId)'" -EA SilentlyContinue
    $existingApp = Get-MgApplication -Filter "appId eq '$($row.AppId)'" -EA SilentlyContinue

    if ($existingSP -and -not $Update) {
        Write-Host "SKIP $($row.DisplayName) (exists)" -ForegroundColor DarkGray
        continue
    }

    # homepage must be set on app reg, not SP
    $appBody = @{
        displayName    = $row.DisplayName
        signInAudience = "AzureADMyOrg"
    }
    if ($row.Homepage)         { $appBody.web = @{ homePageUrl = $row.Homepage } }
    if ($row.AppRolesJson)     { $appBody.appRoles = $row.AppRolesJson | ConvertFrom-Json }
    if ($row.OAuth2ScopesJson) { $appBody.api = @{ oauth2PermissionScopes = $row.OAuth2ScopesJson | ConvertFrom-Json } }

    $spBody = @{
        accountEnabled             = [bool]::Parse($row.AccountEnabled)
        appRoleAssignmentRequired  = [bool]::Parse($row.AppRoleAssignmentRequired)
        preferredSingleSignOnMode  = "saml"
        tags                       = @($row.Tags -split "\|" | Where-Object { $_ })
        notificationEmailAddresses = @($row.NotificationEmails -split "\|" | Where-Object { $_ })
    }
    if ($row.LoginUrl)       { $spBody.loginUrl  = $row.LoginUrl }
    if ($row.LogoutUrl)      { $spBody.logoutUrl = $row.LogoutUrl }
    if ($row.SamlRelayState) { $spBody.samlSingleSignOnSettings = @{ relayState = $row.SamlRelayState } }

    if ($WhatIf) {
        Write-Host "WHATIF: $( if ($existingSP) {'UPDATE'} else {'CREATE'} ) $($row.DisplayName)" -ForegroundColor Cyan
        continue
    }

    try {
        if ($existingSP -and $Update) {
            Update-MgServicePrincipal -ServicePrincipalId $existingSP.Id -BodyParameter $spBody
            Write-Host "UPDATED $($row.DisplayName)" -ForegroundColor Green
            continue
        }

        # Create app reg if needed
        if (-not $existingApp) {
            $newApp = New-MgApplication -BodyParameter $appBody
            Write-Host "CREATED app reg $($row.DisplayName) ($($newApp.Id))" -ForegroundColor Cyan
        } else {
            $newApp = $existingApp
        }

        # Poll for SP - Entra creates it async after app reg
        $newSP = $null
        $tries = 0
        while (-not $newSP -and $tries -lt 10) {
            Start-Sleep -Seconds 3
            $newSP = Get-MgServicePrincipal -Filter "appId eq '$($newApp.AppId)'" -EA SilentlyContinue
            $tries++
        }

        # If still nothing, create it explicitly
        if (-not $newSP) {
            $newSP = New-MgServicePrincipal -BodyParameter @{ appId = $newApp.AppId }
        }

        Update-MgServicePrincipal -ServicePrincipalId $newSP.Id -BodyParameter $spBody
        Write-Host "CREATED SP $($row.DisplayName) ($($newSP.Id))" -ForegroundColor Green

    } catch {
        Write-Host "ERROR $($row.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Disconnect-MgGraph | Out-Null
