# 1.11 — NTFS last-access updates off. Performance & Hardware sector.
# One less metadata write per file read.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Query = 'disablelastaccess'

Invoke-PrimeChange -Id '1.11' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $v = Get-FsutilNumber $Query
        [pscustomobject]@{ Current = "disablelastaccess = $v"; Compliant = ($v -eq 1 -or $v -eq 3) }
    } `
    -ApplyBlock { Set-FsutilNumberTracked $Query 1 } `
    -UndoBlock  { param($Prev) Undo-FsutilNumberTracked $Query $Prev.PreviouslyExisted $Prev.PreviousValue }
