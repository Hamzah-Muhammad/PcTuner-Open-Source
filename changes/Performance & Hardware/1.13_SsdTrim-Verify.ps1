# 1.13 — SSD TRIM enabled (verify). Performance & Hardware sector.
# TRIM keeps SSD write performance healthy. DisableDeleteNotify's fsutil
# output is per-filesystem text, not a single "= N" value like the other
# fsutil settings, so this uses its own parse/apply instead of the shared
# Get/Set-FsutilNumberTracked primitives.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-NtfsTrimLine {
    $out = fsutil behavior query DisableDeleteNotify 2>$null
    $ntfs = @($out) -match 'NTFS'
    if ($ntfs) { $ntfs[0].Trim() } else { $null }
}

Invoke-PrimeChange -Id '1.13' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $line = Get-NtfsTrimLine
        if ($line -and $line -match '(\d)') { [pscustomobject]@{ Current = $line; Compliant = ($Matches[1] -eq '0') } }
        else { [pscustomobject]@{ Current = (if ($line) { $line } else { 'unreadable' }); Compliant = $null } }
    } `
    -ApplyBlock {
        $prevLine = Get-NtfsTrimLine
        fsutil behavior set DisableDeleteNotify NTFS 0 | Out-Null
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $prevLine
    } `
    -UndoBlock {
        param($Prev)
        if ($Prev.PreviousValue -and $Prev.PreviousValue -match '(\d)' -and $Matches[1] -eq '1') {
            fsutil behavior set DisableDeleteNotify NTFS 1 | Out-Null
        }
        New-TrackedResult -Success $true
    }
