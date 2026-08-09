# X.1 — Purge inert StartupApproved leftovers. Windows Changes sector.
# Old enable/disable toggle entries whose actual startup entry is long gone —
# registry clutter from uninstalled apps.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Pairs = @(
    @{ A = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   R = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    @{ A = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   R = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    @{ A = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; R = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' }
)

function Get-Orphans {
    $orphans = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($pair in $Pairs) {
        $ak = Get-Item -Path $pair.A -ErrorAction SilentlyContinue
        if (-not $ak) { continue }
        $rk = Get-Item -Path $pair.R -ErrorAction SilentlyContinue
        $live = if ($rk) { $rk.GetValueNames() } else { @() }
        foreach ($n in ($ak.GetValueNames() | Where-Object { $_ })) {
            if ($live -notcontains $n) { $orphans.Add([pscustomobject]@{ Path = $pair.A; Name = $n; Value = $ak.GetValue($n) }) }
        }
    }
    $orphans
}

Invoke-PrimeChange -Id 'X.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $orphans = @(Get-Orphans)
        if ($orphans.Count) {
            $preview = ($orphans.Name | Select-Object -First 6) -join ', '
            if ($orphans.Count -gt 6) { $preview += " (+$($orphans.Count - 6) more)" }
            [pscustomobject]@{ Current = "$($orphans.Count) orphaned: $preview"; Compliant = $false }
        } else {
            [pscustomobject]@{ Current = 'no orphaned entries'; Compliant = $true }
        }
    } `
    -ApplyBlock {
        $orphans = @(Get-Orphans)
        if (-not $orphans.Count) { return New-TrackedResult -Success $true -Note 'nothing to purge' }
        foreach ($o in $orphans) { Remove-ItemProperty -Path $o.Path -Name $o.Name -ErrorAction SilentlyContinue }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($orphans | ConvertTo-Json -Compress -Depth 4)
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'nothing was purged at apply time' }
        $inner = @($Prev.PreviousValue | ConvertFrom-Json)
        foreach ($o in $inner) { Set-ItemProperty -Path $o.Path -Name $o.Name -Value $o.Value -Type Binary -ErrorAction SilentlyContinue }
        New-TrackedResult -Success $true
    }
