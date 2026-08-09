# 2B.4 — System Restore shadow storage capped at 10 GB. Performance & Hardware sector.
# Bounds background VSS disk usage while keeping restore points. Requires
# elevation to read/write.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-ShadowStorageLine {
    $out = vssadmin list shadowstorage 2>$null
    if (-not $out) { return $null }
    $line = @($out) -match 'Maximum Shadow Copy Storage space'
    if ($line) { $line[0].Trim() } else { $null }
}

Invoke-PrimeChange -Id '2B.4' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $txt = Get-ShadowStorageLine
        if ($null -eq $txt) { return [pscustomobject]@{ Current = 'vssadmin unavailable (needs elevation?)'; Compliant = $null } }
        if ($txt -eq '') { return [pscustomobject]@{ Current = 'no shadow storage configured'; Compliant = $true } }
        if ($txt -match 'UNBOUNDED') { return [pscustomobject]@{ Current = $txt; Compliant = $false } }
        if ($txt -match '([\d\.]+)\s*GB') { return [pscustomobject]@{ Current = $txt; Compliant = ([double]$Matches[1] -le 10) } }
        if ($txt -match '([\d\.]+)\s*MB') { return [pscustomobject]@{ Current = $txt; Compliant = $true } }
        [pscustomobject]@{ Current = $txt; Compliant = $null }
    } `
    -ApplyBlock {
        $prevLine = Get-ShadowStorageLine
        vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10GB | Out-Null
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $prevLine
    } `
    -UndoBlock {
        param($Prev)
        if ($Prev.PreviousValue -match 'UNBOUNDED') {
            vssadmin resize shadowstorage /for=C: /on=C: /maxsize=UNBOUNDED | Out-Null
        } elseif ($Prev.PreviousValue -match '([\d\.]+)\s*GB') {
            vssadmin resize shadowstorage /for=C: /on=C: /maxsize="$($Matches[1])GB" | Out-Null
        }
        New-TrackedResult -Success $true
    }
