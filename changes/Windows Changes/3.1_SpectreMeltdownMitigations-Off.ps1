# 3.1 — Spectre/Meltdown mitigations OFF (Level 3, Security Trade-off). Windows Changes sector.
# TRADE-OFF: ~1-3% CPU-bound gain for disabled speculative-execution hardening.
# Major Windows updates can re-enable — audit re-checks.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$NameA = 'FeatureSettingsOverride'
$NameB = 'FeatureSettingsOverrideMask'

Invoke-PrimeChange -Id '3.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $a = Test-RegValue $RegPath $NameA 3 -MissingText '(not set — mitigations ACTIVE, Windows default)'
        $b = Test-RegValue $RegPath $NameB 3 -MissingText '(not set)'
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    } `
    -ApplyBlock {
        # Same defect class as 1.2: independent try/catch per value so NameB
        # throwing can't discard NameA's already-applied undo data, and both
        # Undo-RegValueTracked calls below are captured rather than left as
        # bare pipeline output (which would otherwise turn this block's
        # result into a 2-element array instead of one object).
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        try { $results['A'] = Set-RegValueTracked $RegPath $NameA 3 } catch { $failures.Add("A: $($_.Exception.Message)") }
        try { $results['B'] = Set-RegValueTracked $RegPath $NameB 3 } catch { $failures.Add("B: $($_.Exception.Message)") }
        if (-not $results.Count) {
            return New-TrackedResult -Success $false -Note ("both values failed: " + ($failures -join '; '))
        }
        $note = if ($failures.Count) { "partially applied — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($results | ConvertTo-Json -Compress) -Note $note
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        if ($inner.A) { try { Undo-RegValueTracked $RegPath $NameA $inner.A.PreviouslyExisted $inner.A.PreviousValue | Out-Null } catch { $failures.Add("A: $($_.Exception.Message)") } }
        if ($inner.B) { try { Undo-RegValueTracked $RegPath $NameB $inner.B.PreviouslyExisted $inner.B.PreviousValue | Out-Null } catch { $failures.Add("B: $($_.Exception.Message)") } }
        $note = if ($failures.Count) { "partially undone — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success ($failures.Count -eq 0) -Note $note
    }
