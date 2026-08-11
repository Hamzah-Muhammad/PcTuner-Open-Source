# 2B.2 — Hibernation + Fast Startup off. Performance & Hardware sector.
# Frees hiberfil.sys (GBs) and avoids stale-driver Fast Startup states.
# Note: this item's Desc (manifest.json) flags a laptop-caution warning —
# no runtime prompt here, see Services\2S.9's note on headless prompting.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$RegName = 'HibernateEnabled'

Invoke-PrimeChange -Id '2B.2' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-RegValue $RegPath $RegName 0 } `
    -ApplyBlock { Set-RegValueTracked $RegPath $RegName 0 } `
    -UndoBlock  { param($Prev) Undo-RegValueTracked $RegPath $RegName $Prev.PreviouslyExisted $Prev.PreviousValue }
