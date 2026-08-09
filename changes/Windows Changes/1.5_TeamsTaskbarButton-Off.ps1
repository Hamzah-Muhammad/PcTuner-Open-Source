# 1.5 — Teams taskbar button hidden. Windows Changes sector.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$RegName = 'TaskbarMn'

Invoke-PrimeChange -Id '1.5' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-RegValue $RegPath $RegName 0 } `
    -ApplyBlock { Set-RegValueTracked $RegPath $RegName 0 } `
    -UndoBlock  { param($Prev) Undo-RegValueTracked $RegPath $RegName $Prev.PreviouslyExisted $Prev.PreviousValue }
