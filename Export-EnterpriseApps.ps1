#Requires -Modules Microsoft.Graph.Applications

param(
    [Parameter(Mandatory)][string]$TenantId,
    [string]$OutputPath = ".\EA_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    [string]$Filter = "*"
)

Connect-MgGraph -TenantId $TenantId -Scopes "Application.Read.All","Directory.Read.All","Policy.Read.All" -NoWelcome

$sps = Get-MgServicePrincipal -All -Property Id,AppId,DisplayName,AccountEnabled,AppRoleAssignmentRequired,
    PreferredSingleSignOnMode,PreferredTokenSigningKeyThumbprint,SamlSingleSignOnSettings,
    LoginUrl,LogoutUrl,ReplyUrls,ServicePrincipalNames,Tags,Homepage,
    NotificationEmailAddresses,AppRoles,Oauth2PermissionScopes,KeyCredentials,PasswordCredentials,
    TokenEncryptionKeyId,Info |
    Where-Object { 
    $_.Tags -contains "WindowsAzureActiveDirectoryIntegratedApp" -and 
    $_.PreferredSingleSignOnMode -eq "saml" -and
    $_.AppOwnerOrganizationId -ne "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -and  # Microsoft
    $_.AppOwnerOrganizationId -ne "72f988bf-86f1-41af-91ab-2d7cd011db47" -and  # Microsoft
    $_.DisplayName -like $Filter 
}

Write-Host "$($sps.Count) apps found"

$sps | ForEach-Object {
    $sp = $_
 
    $assignments = try {
        Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All | ForEach-Object {
            $name = if ($_.PrincipalType -eq "User") {
                (Get-MgUser -UserId $_.PrincipalId -Property UserPrincipalName -EA SilentlyContinue).UserPrincipalName
            } else {
                (Get-MgGroup -GroupId $_.PrincipalId -Property DisplayName -EA SilentlyContinue).DisplayName
            }
            "$($_.PrincipalType):$name($($_.PrincipalId)):role=$($_.AppRoleId)"
        }
    } catch { @() }
 
    [PSCustomObject]@{
        AppId                     = $sp.AppId
        DisplayName               = $sp.DisplayName
        AccountEnabled            = $sp.AccountEnabled
        AppRoleAssignmentRequired = $sp.AppRoleAssignmentRequired
        SamlRelayState            = $sp.SamlSingleSignOnSettings?.RelayState
        Homepage                  = $sp.Homepage
        LoginUrl                  = $sp.LoginUrl
        LogoutUrl                 = $sp.LogoutUrl
        ReplyUrls                 = $sp.ReplyUrls -join "|"
        SPNs                      = $sp.ServicePrincipalNames -join "|"
        Tags                      = $sp.Tags -join "|"
        NotificationEmails        = $sp.NotificationEmailAddresses -join "|"
        AppRolesJson              = $sp.AppRoles | ConvertTo-Json -Compress -Depth 5
        OAuth2ScopesJson          = $sp.Oauth2PermissionScopes | ConvertTo-Json -Compress -Depth 5
        AssignedPrincipals        = $assignments -join "||"
    }
} | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Exported to $OutputPath"
Disconnect-MgGraph | Out-Null
