# 1.8 — Remove Edge autolaunch from startup. Windows Changes sector.
# Edge re-adds a MicrosoftEdgeAutoLaunch_* Run entry after updates — the
# value NAME is dynamic (includes a hash suffix), so Apply enumerates and
# removes all matches rather than targeting one fixed name.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Invoke-PrimeChange -Id '1.8' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $run = Get-Item -Path $RegPath -ErrorAction SilentlyContinue
        $hits = @($run.GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })
        if ($hits.Count) { [pscustomobject]@{ Current = "present: $($hits -join ', ')"; Compliant = $false } }
        else             { [pscustomobject]@{ Current = 'no autolaunch entry';          Compliant = $true } }
    } `
    -ApplyBlock {
        $run = Get-Item -Path $RegPath -ErrorAction SilentlyContinue
        $hits = @($run.GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })
        if (-not $hits.Count) { return New-TrackedResult -Success $true -Note 'no autolaunch entry — nothing to do' }
        # Captures the raw (unexpanded) value AND its real registry kind, not
        # just the expanded string — the old code always wrote back
        # -Type String on undo regardless of the original type, which would
        # silently corrupt an %VAR%-style REG_EXPAND_SZ entry into a literal
        # REG_SZ path.
        $removed = @{}
        foreach ($n in $hits) {
            $removed[$n] = @{
                Value = $run.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Kind  = $run.GetValueKind($n).ToString()
            }
            Remove-ItemProperty -Path $RegPath -Name $n -ErrorAction SilentlyContinue
        }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($removed | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'nothing was removed at apply time' }
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        foreach ($n in $inner.PSObject.Properties.Name) {
            $entry = $inner.$n
            Set-ItemProperty -Path $RegPath -Name $n -Value $entry.Value -Type $entry.Kind
        }
        New-TrackedResult -Success $true
    }
