# 2S.19 — Anticheat/launcher services -> Manual (never Disabled). Services sector.
# HARD GUARDRAIL: EABackgroundService, EAAntiCheatService, BEService,
# EasyAntiCheat: Disabled silently breaks game launches (verified with EA
# titles); Manual keeps them dormant until their game runs. This script's
# target mode is hardcoded to 'Manual' — never parameterized to Disabled.
# Riot vgc/vgk are deliberately excluded (managed separately).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Names = @('EABackgroundService', 'EAAntiCheatService', 'BEService', 'EasyAntiCheat', 'EasyAntiCheat_EOS')
$Expected = 'Manual'   # hardcoded — this item may never target Disabled

Invoke-PrimeChange -Id '2S.19' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $found = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $Names -contains $_.Name })
        if (-not $found.Count) { return [pscustomobject]@{ Current = 'none present'; Compliant = $true } }
        $bad = @($found | Where-Object { $_.StartMode -ne $Expected })
        $cur = ($found | ForEach-Object { "$($_.Name)=$($_.StartMode)" }) -join '; '
        [pscustomobject]@{ Current = $cur; Compliant = ($bad.Count -eq 0) }
    } `
    -ApplyBlock {
        $found = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $Names -contains $_.Name })
        if (-not $found.Count) { return New-TrackedResult -Success $true -Note 'none present — nothing to do' }
        # A per-service try/catch, not a bare loop: one service throwing
        # (e.g. Access Denied) must not discard the Manual/undo data already
        # captured for services set earlier in this same loop.
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($svc in $found.Name) {
            try { $results[$svc] = Set-ServiceStartModeTracked $svc $Expected }
            catch { $failures.Add("$($svc): $($_.Exception.Message)") }
        }
        if (-not $results.Count) {
            return New-TrackedResult -Success $false -Note ("all services failed: " + ($failures -join '; '))
        }
        $note = if ($failures.Count) { "partially applied — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress -Depth 4) -Note $note
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'nothing was present at apply time' }
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($svc in $inner.PSObject.Properties.Name) {
            $r = $inner.$svc
            try { Undo-ServiceStartModeTracked $svc $r.PreviouslyExisted $r.PreviousValue | Out-Null }
            catch { $failures.Add("$($svc): $($_.Exception.Message)") }
        }
        $note = if ($failures.Count) { "partially undone — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success ($failures.Count -eq 0) -Note $note
    }
