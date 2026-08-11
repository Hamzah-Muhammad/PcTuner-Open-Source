# 1.2 — Start-menu ads & suggestions off. Windows Changes sector.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$NameA = 'SubscribedContent-338388Enabled'
$NameB = 'SubscribedContent-338389Enabled'

Invoke-PrimeChange -Id '1.2' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $a = Test-RegValue $RegPath $NameA 0
        $b = Test-RegValue $RegPath $NameB 0
        [pscustomobject]@{ Current = "$($a.Current); $($b.Current)"; Compliant = ($a.Compliant -and $b.Compliant) }
    } `
    -ApplyBlock {
        # Independent try/catch per value: NameB throwing must not discard
        # NameA's already-applied undo data. Also: both Undo-RegValueTracked
        # calls below are captured, never left as bare pipeline output — an
        # unsuppressed call's return object becomes a SECOND item in this
        # block's output, turning the JSON result into a 2-element array
        # instead of the single object PrimeHeadless/Pydantic expect.
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        try { $results['A'] = Set-RegValueTracked $RegPath $NameA 0 } catch { $failures.Add("A: $($_.Exception.Message)") }
        try { $results['B'] = Set-RegValueTracked $RegPath $NameB 0 } catch { $failures.Add("B: $($_.Exception.Message)") }
        if (-not $results.Count) {
            return New-TrackedResult -Success $false -Note ("both values failed: " + ($failures -join '; '))
        }
        $note = if ($failures.Count) { "partially applied — failed: " + ($failures -join '; ') } else { $null }
        New-TrackedResult -Success $true -PreviousValue ($results | ConvertTo-Json -Compress) -PreviouslyExisted $true -Note $note
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
