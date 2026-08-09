# 3.4 — Defender exclusions for game folders (review). Windows Changes sector.
# Human-review item — Apply is deliberately not implemented (which folders to
# exclude is a per-item human choice, not automatable). HARD RULE reflected
# in the check itself: flags (never silently accepts) Temp/profile-root/
# drive-root exclusions as non-compliant, since those would be dangerous.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

Invoke-PrimeChange -Id '3.4' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        try { $mp = Get-MpPreference -ErrorAction Stop } catch { return [pscustomobject]@{ Current = 'Defender preferences unreadable'; Compliant = $null } }
        $excl = @($mp.ExclusionPath)
        $danger = @($excl | Where-Object { $_ -match 'Temp|Downloads' -or $_ -match '^[A-Z]:\\?$' })
        $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
        $libs = [System.Collections.Generic.List[string]]::new()
        if ($steam -and (Test-Path "$steam\steamapps\libraryfolders.vdf")) {
            foreach ($m in [regex]::Matches((Get-Content "$steam\steamapps\libraryfolders.vdf" -Raw), '"path"\s+"([^"]+)"')) {
                $libs.Add($m.Groups[1].Value.Replace('\\', '\'))
            }
        }
        $cur = "$($excl.Count) exclusions; Steam libraries: $(if ($libs.Count) { $libs -join ', ' } else { 'none detected' })"
        if ($danger.Count) { return [pscustomobject]@{ Current = "$cur — DANGEROUS exclusion present: $($danger -join ', ')"; Compliant = $false } }
        [pscustomobject]@{ Current = $cur; Compliant = $null }
    }
