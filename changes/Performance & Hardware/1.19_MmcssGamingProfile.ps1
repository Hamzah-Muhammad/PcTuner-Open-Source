# 1.19 — MMCSS gaming profile. Performance & Hardware sector.
# Network throttling off + games get a fair CPU share from the multimedia
# scheduler. Registry DWORD 0xFFFFFFFF reads back as Int32 -1 — both
# representations are accepted as compliant.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$NameA = 'NetworkThrottlingIndex'
$NameB = 'SystemResponsiveness'

Invoke-PrimeChange -Id '1.19' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $sp = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
        $nti = if ($sp) { $sp.NetworkThrottlingIndex } else { $null }
        $sr  = if ($sp) { $sp.SystemResponsiveness }  else { $null }
        $ntiOk = ($nti -eq -1 -or $nti -eq 4294967295)
        [pscustomobject]@{ Current = "NetworkThrottlingIndex = $nti; SystemResponsiveness = $sr"; Compliant = ($ntiOk -and ($sr -eq 0 -or $sr -eq 10)) }
    } `
    -ApplyBlock {
        # Independent try/catch per value (NameB throwing must not discard
        # NameA's already-applied undo data), and both Undo-RegValueTracked
        # calls below are captured rather than left as bare pipeline output
        # (unsuppressed, they'd turn this block's result into a 2-element
        # array instead of the single object PrimeHeadless/Pydantic expect).
        $results = @{}; $failures = [System.Collections.Generic.List[string]]::new()
        try { $results['A'] = Set-RegValueTracked $RegPath $NameA 0xFFFFFFFF } catch { $failures.Add("A: $($_.Exception.Message)") }
        try { $results['B'] = Set-RegValueTracked $RegPath $NameB 0 } catch { $failures.Add("B: $($_.Exception.Message)") }
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
