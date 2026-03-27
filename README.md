## What it does
```markdown
Exports SAML Enterprise Apps from a source tenant to CSV, then imports them into a destination tenant. User and group assignments are captured in the CSV for reference but not re-applied on import — you can't assume the same principals exist on the other side.

**Note:** SAML token signing certs aren't exportable via Graph (no private key). The destination tenant generates a new one automatically per app. After import, grab the new cert from the SSO blade and upload it to your service provider.

## Requirements

```powershell
Install-Module Microsoft.Graph.Applications -Scope CurrentUser
```

## Export

```powershell
.\Export-EnterpriseApps.ps1 -TenantId "source.onmicrosoft.com"
```

Optional: `-OutputPath` to specify the CSV location, `-Filter` to scope by display name (e.g. `-Filter "SAP*"`).

## Import

```powershell
.\Import-EnterpriseApps.ps1 -TenantId "destination.onmicrosoft.com" -CsvPath ".\EA_Export_20250101.csv"
```

Skips apps that already exist unless you pass `-Update`. Use `-WhatIf` to dry run first.

## After import

- Download the new signing cert for each app (Portal > Enterprise Apps > Single sign-on > Certificates) and upload to your SP
- Re-assign users/groups — use the `AssignedPrincipals` column in the CSV as your reference
- Check any Conditional Access policies that referenced the old SP object IDs
```
