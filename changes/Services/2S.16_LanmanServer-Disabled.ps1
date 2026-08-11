# 2S.16 — LanmanServer -> Disabled. Services sector.
# SMB share HOSTING. Guard: this item's Desc (manifest.json) warns it breaks
# sharing folders to other devices (NAS client access unaffected) — no
# runtime prompt, see 2S.9's note.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Svc = 'LanmanServer'; $Expected = 'Disabled'

Invoke-PrimeChange -Id '2S.16' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock { Test-ServiceStartMode $Svc $Expected } `
    -ApplyBlock { Set-ServiceStartModeTracked $Svc $Expected } `
    -UndoBlock  { param($Prev) Undo-ServiceStartModeTracked $Svc $Prev.PreviouslyExisted $Prev.PreviousValue }
