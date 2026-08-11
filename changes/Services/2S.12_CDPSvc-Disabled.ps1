# 2S.12 — CDPSvc -> Disabled. Services sector.
# Connected Devices Platform service (pairs with Windows Changes\1.4).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Svc = 'CDPSvc'; $Expected = 'Disabled'

Invoke-PrimeChange -Id '2S.12' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-ServiceStartMode $Svc $Expected } `
    -ApplyBlock { Set-ServiceStartModeTracked $Svc $Expected } `
    -UndoBlock  { param($Prev) Undo-ServiceStartModeTracked $Svc $Prev.PreviouslyExisted $Prev.PreviousValue }
