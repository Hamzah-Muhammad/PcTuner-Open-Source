# 2S.18 — DoSvc (Delivery Optimization) -> Manual. Services sector.
# Set-Service is Access-Denied on this service — the registry Start value is
# edited directly instead (3 = Manual).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc'
$RegName = 'Start'

Invoke-PrimeChange -Id '2S.18' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-RegValue $RegPath $RegName 3 } `
    -ApplyBlock { Set-RegValueTracked $RegPath $RegName 3 } `
    -UndoBlock  { param($Prev) Undo-RegValueTracked $RegPath $RegName $Prev.PreviouslyExisted $Prev.PreviousValue }
