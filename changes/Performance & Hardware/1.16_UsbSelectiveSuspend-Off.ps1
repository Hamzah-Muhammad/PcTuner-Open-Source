# 1.16 — USB selective suspend off. Performance & Hardware sector.
# Prevents input-device latency/wake hitches.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$SubGuid = '2a737441-1930-4402-8d77-b2bebba308a3'
$SettingGuid = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

Invoke-PrimeChange -Id '1.16' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $v = Get-PowerAcValue $SubGuid $SettingGuid
        if ($null -eq $v) { return [pscustomobject]@{ Current = 'setting not readable on this scheme'; Compliant = $null } }
        [pscustomobject]@{ Current = "USB selective suspend = $v (0=off,1=on)"; Compliant = ($v -eq 0) }
    } `
    -ApplyBlock { Set-PowerAcValueTracked $SubGuid $SettingGuid 0 } `
    -UndoBlock  { param($Prev) Undo-PowerAcValueTracked $SubGuid $SettingGuid $Prev.PreviouslyExisted $Prev.PreviousValue }
