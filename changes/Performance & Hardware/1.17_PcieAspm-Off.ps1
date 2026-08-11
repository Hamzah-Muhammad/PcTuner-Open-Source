# 1.17 — PCIe link-state power management off. Performance & Hardware sector.
# GPU PCIe link never down-clocks into a latency penalty.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$SubGuid = '501a4d13-42af-4429-9fd1-a8218c268e20'
$SettingGuid = 'ee12f906-d277-404b-b6da-e5fa1a576df5'

Invoke-PrimeChange -Id '1.17' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $v = Get-PowerAcValue $SubGuid $SettingGuid
        if ($null -eq $v) { return [pscustomobject]@{ Current = 'setting not readable on this scheme'; Compliant = $null } }
        [pscustomobject]@{ Current = "PCIe ASPM = $v (0=off)"; Compliant = ($v -eq 0) }
    } `
    -ApplyBlock { Set-PowerAcValueTracked $SubGuid $SettingGuid 0 } `
    -UndoBlock  { param($Prev) Undo-PowerAcValueTracked $SubGuid $SettingGuid $Prev.PreviouslyExisted $Prev.PreviousValue }
