# 3.5 — MSI interrupt mode for GPU + NIC (Level 3, Security Trade-off catalog — hardware tuning, low risk). Windows Changes sector.
# Message-signaled interrupts = lower interrupt latency than legacy line-based.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-MsiDevices {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | Select-Object -First 1
    $nic = Get-ActiveNic
    @(
        @{ Label = 'GPU'; Pnp = if ($gpu) { $gpu.PNPDeviceID } else { $null } }
        @{ Label = 'NIC'; Pnp = if ($nic) { $nic.PnpDeviceID } else { $null } }
    )
}

Invoke-PrimeChange -Id '3.5' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $parts = [System.Collections.Generic.List[string]]::new(); $ok = $true
        foreach ($dev in Get-MsiDevices) {
            if (-not $dev.Pnp) { $parts.Add("$($dev.Label): not found"); continue }
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Pnp)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $v = (Get-ItemProperty -Path $reg -Name MSISupported -ErrorAction SilentlyContinue).MSISupported
            if ($v -eq 1) { $parts.Add("$($dev.Label): MSI on") } else { $parts.Add("$($dev.Label): MSI off/unset"); $ok = $false }
        }
        [pscustomobject]@{ Current = $parts -join '; '; Compliant = $ok }
    } `
    -ApplyBlock {
        # Per-device try/catch: GPU throwing (e.g. driver holds the key open)
        # must not discard the NIC's already-applied undo data, or vice versa.
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($dev in Get-MsiDevices) {
            if (-not $dev.Pnp) { continue }
            $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Pnp)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            try { $results[$dev.Label] = @{ Reg = $reg; Result = (Set-RegValueTracked $reg 'MSISupported' 1) } }
            catch { $failures.Add("$($dev.Label): $($_.Exception.Message)") }
        }
        if (-not $results.Count) {
            return New-TrackedResult -Success $false -Note ("all devices failed: " + ($failures -join '; '))
        }
        $note = if ($failures.Count) { "partially applied — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress -Depth 5) -Note $note
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($label in $inner.PSObject.Properties.Name) {
            $d = $inner.$label
            try { Undo-RegValueTracked $d.Reg 'MSISupported' $d.Result.PreviouslyExisted $d.Result.PreviousValue | Out-Null }
            catch { $failures.Add("$($label): $($_.Exception.Message)") }
        }
        $note = 'device reset (~2s) applies the change — never run mid-game'
        if ($failures.Count) { $note += ' — partially undone, failed: ' + ($failures -join '; ') }
        New-TrackedResult -Success ($failures.Count -eq 0) -Note $note
    }
