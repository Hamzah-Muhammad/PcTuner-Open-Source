# 2S.4 — Fax -> Disabled. Services sector.
# Fax. It is not 1996.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Svc = 'Fax'; $Expected = 'Disabled'

Invoke-PrimeChange -Id '2S.4' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-ServiceStartMode $Svc $Expected } `
    -ApplyBlock { Set-ServiceStartModeTracked $Svc $Expected } `
    -UndoBlock  { param($Prev) Undo-ServiceStartModeTracked $Svc $Prev.PreviouslyExisted $Prev.PreviousValue }
