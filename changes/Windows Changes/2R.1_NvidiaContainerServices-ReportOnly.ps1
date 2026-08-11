# 2R.1 — NVIDIA container services (report-only). Windows Changes sector.
# NvContainerLocalSystem / NVDisplay.ContainerLocalSystem host real NVIDIA
# Control Panel / driver-settings functionality, not just telemetry — unlike
# DiagTrack/SysMain, there's no version of this that's safe to auto-disable.
# Apply is deliberately not implemented, this is a REVIEW-only item by design
# (same pattern as 2A.4).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

Invoke-PrimeChange -Id '2R.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $svcNames = 'NvContainerLocalSystem', 'NVDisplay.ContainerLocalSystem'
        $found = @(Get-Service -Name $svcNames -ErrorAction SilentlyContinue)
        if ($found.Count) {
            $summary = ($found | ForEach-Object { "$($_.Name)=$($_.Status)/$($_.StartType)" }) -join '; '
            [pscustomobject]@{ Current = $summary; Compliant = $null }
        } else {
            [pscustomobject]@{ Current = 'not present (no NVIDIA driver container services found)'; Compliant = $null }
        }
    }
