# 2A.2 — Remove Copilot. Windows Changes sector.
# Also covers what was Startup Optimizer's W.3 — merged, identical package match.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Patterns = @('Copilot')

Invoke-PrimeChange -Id '2A.2' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-AppxPackageAbsent $Patterns } `
    -ApplyBlock { Remove-AppxPackageTracked $Patterns } `
    -UndoBlock  { param($Prev) Undo-AppxPackageTracked $Prev.PreviouslyExisted $Prev.PreviousValue }
