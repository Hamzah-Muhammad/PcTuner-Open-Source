# 1.12 — Larger NTFS metadata cache. Performance & Hardware sector.
# Fewer metadata disk hits. Needs a reboot to take effect.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Query = 'memoryusage'

Invoke-PrimeChange -Id '1.12' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $v = Get-FsutilNumber $Query
        [pscustomobject]@{ Current = "memoryusage = $v"; Compliant = ($v -eq 2) }
    } `
    -ApplyBlock { Set-FsutilNumberTracked $Query 2 } `
    -UndoBlock  { param($Prev) Undo-FsutilNumberTracked $Query $Prev.PreviouslyExisted $Prev.PreviousValue }
