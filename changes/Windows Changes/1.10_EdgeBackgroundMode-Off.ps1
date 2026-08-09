# 1.10 — Block Edge background mode (policy). Windows Changes sector.
# Also covers the other half of what was Startup Optimizer's W.5 (see 1.9).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$RegName = 'BackgroundModeEnabled'

Invoke-PrimeChange -Id '1.10' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-RegValue $RegPath $RegName 0 } `
    -ApplyBlock { Set-RegValueTracked $RegPath $RegName 0 } `
    -UndoBlock  { param($Prev) Undo-RegValueTracked $RegPath $RegName $Prev.PreviouslyExisted $Prev.PreviousValue }
