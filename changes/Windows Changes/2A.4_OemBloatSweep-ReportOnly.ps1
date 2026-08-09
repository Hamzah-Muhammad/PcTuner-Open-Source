# 2A.4 — OEM vendor bloat sweep (report-only). Windows Changes sector.
# Lists known OEM utility leftovers; never auto-removes — Apply is
# deliberately not implemented, this is a REVIEW-only item by design.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

Invoke-PrimeChange -Id '2A.4' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match 'HPInc|Hewlett|Lenovo|DellInc|ASUSTeK|AcerIncorporated|McAfee|Norton' })
        if ($pkg.Count) { [pscustomobject]@{ Current = "found: $($pkg.Name -join ', ')"; Compliant = $null } }
        else            { [pscustomobject]@{ Current = 'none found'; Compliant = $true } }
    }
