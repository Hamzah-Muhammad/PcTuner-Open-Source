# 3.3 — Defender scheduled scans OFF, real-time stays ON (Level 3, Security Trade-off). Windows Changes sector.
# Background full scans tank frame times mid-game. Real-time + tamper
# protection are NEVER touched here. Windows Update resets the schedule —
# audit re-checks.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

Invoke-PrimeChange -Id '3.3' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        try { $mp = Get-MpPreference -ErrorAction Stop } catch { return [pscustomobject]@{ Current = 'Defender preferences unreadable'; Compliant = $null } }
        $cur = "ScanScheduleDay = $($mp.ScanScheduleDay) (8=Never); CatchupQuick disabled = $($mp.DisableCatchupQuickScan); CatchupFull disabled = $($mp.DisableCatchupFullScan)"
        [pscustomobject]@{ Current = $cur; Compliant = ($mp.ScanScheduleDay -eq 8 -and $mp.DisableCatchupQuickScan -and $mp.DisableCatchupFullScan) }
    } `
    -ApplyBlock {
        $mp = Get-MpPreference -ErrorAction Stop
        $prev = @{ ScanScheduleDay = $mp.ScanScheduleDay; DisableCatchupQuickScan = $mp.DisableCatchupQuickScan; DisableCatchupFullScan = $mp.DisableCatchupFullScan }
        Set-MpPreference -ScanScheduleDay 8 -DisableCatchupQuickScan $true -DisableCatchupFullScan $true -ErrorAction Stop
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($prev | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        Set-MpPreference -ScanScheduleDay $inner.ScanScheduleDay -DisableCatchupQuickScan $inner.DisableCatchupQuickScan -DisableCatchupFullScan $inner.DisableCatchupFullScan -ErrorAction Stop
        New-TrackedResult -Success $true
    }
