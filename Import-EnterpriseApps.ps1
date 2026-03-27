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
    $existing = Get-MgServicePrincipal -Filter "appId eq '$($row.AppId)'" -EA SilentlyContinue

    if ($existing -and -not $Update) {
        Write-Host "SKIP $($row.DisplayName) (exists)" -ForegroundColor DarkGray
        continue
    }

    $body = @{
        appId                      = $row.AppId
        displayName                = $row.DisplayName
        accountEnabled             = [bool]::Parse($row.AccountEnabled)
        appRoleAssignmentRequired  = [bool]::Parse($row.AppRoleAssignmentRequired)
        preferredSingleSignOnMode  = "saml"
        replyUrls                  = @($row.ReplyUrls -split "\|" | Where-Object { $_ })
        tags                       = @($row.Tags -split "\|" | Where-Object { $_ })
        servicePrincipalNames      = @($row.SPNs -split "\|" | Where-Object { $_ })
        notificationEmailAddresses = @($row.NotificationEmails -split "\|" | Where-Object { $_ })
    }

    if ($row.Homepage)       { $body.homepage  = $row.Homepage }
    if ($row.LoginUrl)       { $body.loginUrl  = $row.LoginUrl }
    if ($row.LogoutUrl)      { $body.logoutUrl = $row.LogoutUrl }
    if ($row.SamlRelayState) { $body.samlSingleSignOnSettings = @{ relayState = $row.SamlRelayState } }

    if ($row.AppRolesJson)     { $body.appRoles               = $row.AppRolesJson | ConvertFrom-Json }
    if ($row.OAuth2ScopesJson) { $body.oauth2PermissionScopes = $row.OAuth2ScopesJson | ConvertFrom-Json }

    if ($WhatIf) {
        Write-Host "WHATIF: $( if ($existing) {'UPDATE'} else {'CREATE'} ) $($row.DisplayName)" -ForegroundColor Cyan
        continue
    }

    try {
        if ($existing -and $Update) {
            Update-MgServicePrincipal -ServicePrincipalId $existing.Id -BodyParameter $body
            Write-Host "UPDATED $($row.DisplayName)" -ForegroundColor Green
        } else {
            $new = New-MgServicePrincipal -BodyParameter $body
            Write-Host "CREATED $($row.DisplayName) ($($new.Id))" -ForegroundColor Green
        }
    } catch {
        Write-Host "ERROR $($row.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Disconnect-MgGraph | Out-Null
