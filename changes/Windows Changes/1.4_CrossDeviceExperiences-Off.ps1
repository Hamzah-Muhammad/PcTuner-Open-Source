# 1.4 — Cross-device experiences off. Windows Changes sector.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP'
$RegName = 'EnableCdp'

Invoke-PrimeChange -Id '1.4' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-RegValue $RegPath $RegName 0 -MissingText '(key missing — Windows Update likely removed it)' } `
    -ApplyBlock { Set-RegValueTracked $RegPath $RegName 0 } `
    -UndoBlock  { param($Prev) Undo-RegValueTracked $RegPath $RegName $Prev.PreviouslyExisted $Prev.PreviousValue }
