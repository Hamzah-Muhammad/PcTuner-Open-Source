# 1.T — Disable 10 telemetry/compat-census scheduled tasks. Windows Changes sector.
# Skips TrustedInstaller-protected SdbinstMergeDbTask; never touches \Shell\CreateObjectTask.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Targets = @(
    @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'MareBackup' }
    @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'Microsoft Compatibility Appraiser Exp' }
    @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'PcaPatchDbTask' }
    @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' }
    @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' }
    @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClient' }
    @{ P = '\Microsoft\Windows\Feedback\Siuf\';                           N = 'DmClientOnScenarioDownload' }
    @{ P = '\Microsoft\Windows\Windows Error Reporting\';                 N = 'QueueReporting' }
    @{ P = '\Microsoft\Windows\Maps\';                                    N = 'MapsToastTask' }
    @{ P = '\Microsoft\Windows\CloudExperienceHost\';                     N = 'CreateObjectTask' }
)

Invoke-PrimeChange -Id '1.T' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $enabled = [System.Collections.Generic.List[string]]::new(); $missing = 0
        foreach ($t in $Targets) {
            $task = Get-ScheduledTask -TaskPath $t.P -TaskName $t.N -ErrorAction SilentlyContinue
            if (-not $task) { $missing++; continue }
            if ($task.State -ne 'Disabled') { $enabled.Add($t.N) }
        }
        if ($enabled.Count -eq 0) { [pscustomobject]@{ Current = "all present tasks disabled ($missing not present)"; Compliant = $true } }
        else { [pscustomobject]@{ Current = "still enabled: $($enabled -join ', ')"; Compliant = $false } }
    } `
    -ApplyBlock {
        # One protected task (e.g. TrustedInstaller-owned) throwing here must
        # not discard the tasks already disabled earlier in this same loop —
        # $ErrorActionPreference is 'Stop' for this whole block, so without a
        # per-target try/catch, sub-item #5 failing would abort before
        # $results ever reaches New-TrackedResult, losing undo data for
        # sub-items #1-4 that already changed for real.
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $Targets) {
            try { $results[$t.N] = Disable-ScheduledTaskTracked $t.P $t.N }
            catch { $failures.Add("$($t.N): $($_.Exception.Message)") }
        }
        if (-not $results.Count) {
            return New-TrackedResult -Success $false -Note ("all targets failed: " + ($failures -join '; '))
        }
        $note = if ($failures.Count) { "partially applied — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress -Depth 4) -Note $note
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $Targets) {
            $r = $inner.($t.N)
            if (-not $r) { continue }
            try { Undo-ScheduledTaskTracked $t.P $t.N $r.PreviouslyExisted $r.PreviousValue | Out-Null }
            catch { $failures.Add("$($t.N): $($_.Exception.Message)") }
        }
        $note = if ($failures.Count) { "partially undone — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success ($failures.Count -eq 0) -Note $note
    }
