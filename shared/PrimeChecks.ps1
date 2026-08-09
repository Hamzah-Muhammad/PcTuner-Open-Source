# PrimeChecks.ps1 — shared I/O primitives for every individual change script
# under changes\<Sector>\*.ps1. Dot-source this before PrimeHeadless.ps1.
#
# Read-only Test-* functions predate this file (moved here unchanged from the
# old per-tool Catalog.ps1 files). Set-*Tracked functions are new: each reads
# the prior state itself, writes the new state, and returns enough raw/typed
# info to undo the change later — Test-*'s Current field is a display string,
# not something Undo can replay.

Set-StrictMode -Version 2

# All Set-*Tracked/Undo-*Tracked primitives return this exact shape (every
# field always present, defaulted to $null) so PrimeHeadless.ps1's
# strict-mode property access never fails just because a given call had
# nothing to say about PreviouslyExisted/PreviousValue/Note.
function New-TrackedResult {
    param([bool]$Success, [bool]$PreviouslyExisted = $false, $PreviousValue = $null, [string]$Note = $null)
    [pscustomobject]@{ Success = $Success; PreviouslyExisted = $PreviouslyExisted; PreviousValue = $PreviousValue; Note = $Note }
}

# ---------- registry ----------

function Test-RegValue {
    param($Path, $Name, $Expected, [switch]$MissingIsCompliant, [string]$MissingText = '(not set)')
    try {
        $val = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        [pscustomobject]@{ Current = "$Name = $val"; Compliant = ($val -eq $Expected) }
    } catch {
        [pscustomobject]@{ Current = "$Name $MissingText"; Compliant = [bool]$MissingIsCompliant }
    }
}

function Set-RegValueTracked {
    param($Path, $Name, $Value, [string]$Type = 'DWord')
    $existed = $false; $prev = $null
    try { $prev = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name; $existed = $true } catch {}
    # `New-Item -Force` on a key that ALREADY EXISTS does not no-op — it
    # recreates the key, silently deleting every OTHER value already stored
    # under it (confirmed directly: a disposable test key with two values
    # lost the untouched second value the moment -Force ran again on the
    # already-existing key). Only create when genuinely missing.
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
    New-TrackedResult -Success $true -PreviouslyExisted $existed -PreviousValue $prev
}

function Undo-RegValueTracked {
    param($Path, $Name, [bool]$PreviouslyExisted, $PreviousValue, [string]$Type = 'DWord')
    if ($PreviouslyExisted) {
        Set-ItemProperty -Path $Path -Name $Name -Value $PreviousValue -Type $Type
    } else {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    }
    New-TrackedResult -Success $true
}

# ---------- services ----------

function Test-ServiceStartMode {
    param($Svc, $Expected)   # Expected: 'Disabled' | 'Manual'
    $s = Get-CimInstance Win32_Service -Filter "Name='$Svc'" -ErrorAction SilentlyContinue
    if (-not $s) { return [pscustomobject]@{ Current = 'service not present on this PC'; Compliant = $true } }
    [pscustomobject]@{
        Current   = "StartMode = $($s.StartMode), State = $($s.State)"
        Compliant = ($s.StartMode -eq $Expected)
    }
}

function Resolve-ServiceStartupTypeValue {
    # Win32_Service.StartMode's CIM vocabulary (Boot/System/Auto/Manual/
    # Disabled) does not line up with Set-Service -StartupType's enum, whose
    # exact member set differs by host: Windows PowerShell 5.1's
    # System.ServiceProcess.ServiceStartMode has no delayed-start member at
    # all, while PowerShell 7's Microsoft.PowerShell.Commands.ServiceStartupType
    # adds AutomaticDelayedStart. Passing CIM's literal "Auto" straight
    # through either silently binds to the wrong member via partial-name
    # matching (5.1 quietly accepts "Auto" as a prefix of "Automatic") or
    # throws outright on an ambiguous prefix (7, now that AutomaticDelayedStart
    # also starts with "Auto") — resolving to a full, explicit member name
    # here removes the ambiguity on both hosts.
    param([string]$StartMode, [bool]$DelayedAutoStart)
    if ($StartMode -eq 'Auto') {
        if ($DelayedAutoStart) { return 'AutomaticDelayedStart' }
        return 'Automatic'
    }
    return $StartMode   # Boot / System / Manual / Disabled already match literally
}

function Set-ServiceStartModeTracked {
    param($Svc, $Expected)
    $s = Get-CimInstance Win32_Service -Filter "Name='$Svc'" -ErrorAction SilentlyContinue
    if (-not $s) { return New-TrackedResult -Success $true -Note 'service not present — nothing to do' }
    $prevMode = $s.StartMode
    $prevDelayed = [bool]$s.DelayedAutoStart
    Set-Service -Name $Svc -StartupType $Expected -ErrorAction Stop
    New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue @{ StartMode = $prevMode; DelayedAutoStart = $prevDelayed }
}

function Undo-ServiceStartModeTracked {
    param($Svc, [bool]$PreviouslyExisted, $PreviousValue)
    if (-not $PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'was not present at apply time — nothing to restore' }
    $target = Resolve-ServiceStartupTypeValue -StartMode $PreviousValue.StartMode -DelayedAutoStart ([bool]$PreviousValue.DelayedAutoStart)
    try {
        Set-Service -Name $Svc -StartupType $target -ErrorAction Stop
    } catch {
        if ($target -ne 'AutomaticDelayedStart') { throw }
        # Delayed-start isn't representable on every host (Windows PowerShell
        # 5.1 has no such enum member) — fall back to plain Automatic rather
        # than failing the whole undo over losing just that nuance.
        Set-Service -Name $Svc -StartupType 'Automatic' -ErrorAction Stop
    }
    New-TrackedResult -Success $true
}

# ---------- fsutil ----------

function Get-FsutilNumber {
    param($Query)   # e.g. 'disablelastaccess'
    $out = fsutil behavior query $Query 2>$null
    if ($out -join ' ' -match '=\s*(\d+)') { [int]$Matches[1] } else { $null }
}

function Set-FsutilNumberTracked {
    param($Query, [int]$Value)
    $prev = Get-FsutilNumber $Query
    fsutil behavior set $Query $Value | Out-Null
    New-TrackedResult -Success $true -PreviouslyExisted ($null -ne $prev) -PreviousValue $prev
}

function Undo-FsutilNumberTracked {
    param($Query, [bool]$PreviouslyExisted, $PreviousValue)
    if (-not $PreviouslyExisted -or $null -eq $PreviousValue) { return New-TrackedResult -Success $true -Note 'no previous value recorded — leaving as-is' }
    fsutil behavior set $Query $PreviousValue | Out-Null
    New-TrackedResult -Success $true
}

# ---------- power scheme (AC values) ----------

function Get-PowerAcValue {
    param($SubGuid, $SettingGuid)
    $out = powercfg /query SCHEME_CURRENT $SubGuid $SettingGuid 2>$null
    $line = @($out) -match 'Current AC Power Setting Index'
    if ($line -and $line[0] -match '0x([0-9a-fA-F]+)') { [Convert]::ToInt32($Matches[1], 16) } else { $null }
}

function Set-PowerAcValueTracked {
    param($SubGuid, $SettingGuid, [int]$Value)
    $prev = Get-PowerAcValue $SubGuid $SettingGuid
    powercfg /setacvalueindex SCHEME_CURRENT $SubGuid $SettingGuid $Value | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    New-TrackedResult -Success $true -PreviouslyExisted ($null -ne $prev) -PreviousValue $prev
}

function Undo-PowerAcValueTracked {
    param($SubGuid, $SettingGuid, [bool]$PreviouslyExisted, $PreviousValue)
    if (-not $PreviouslyExisted -or $null -eq $PreviousValue) { return New-TrackedResult -Success $true -Note 'no previous value recorded — leaving as-is' }
    powercfg /setacvalueindex SCHEME_CURRENT $SubGuid $SettingGuid $PreviousValue | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    New-TrackedResult -Success $true
}

# ---------- scheduled tasks ----------

function Test-ScheduledTaskState {
    param($TaskPath, $TaskName, [string]$Expected = 'Disabled')
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return [pscustomobject]@{ Current = 'task not present on this PC'; Compliant = $true } }
    [pscustomobject]@{ Current = "State = $($t.State)"; Compliant = ($t.State -eq $Expected) }
}

function Disable-ScheduledTaskTracked {
    param($TaskPath, $TaskName)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return New-TrackedResult -Success $true -Note 'task not present — nothing to do' }
    # .State is a StateEnum, not a string — ConvertTo-Json serializes an
    # unstringified enum as its underlying INTEGER, which then can never
    # -eq 'Disabled' again on the undo side. Stringify at the source instead
    # of trying to compare around the problem later.
    $prevState = $t.State.ToString()
    if ($prevState -eq 'Disabled') {
        # Already compliant — applying again would be a false "we changed
        # this" that then makes Undo re-enable a task the tool never
        # actually touched.
        return New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $prevState -Note 'already Disabled — no action taken'
    }
    Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
    New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $prevState
}

function Undo-ScheduledTaskTracked {
    param($TaskPath, $TaskName, [bool]$PreviouslyExisted, $PreviousValue)
    if (-not $PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'was not present at apply time — nothing to restore' }
    if ("$PreviousValue" -eq 'Disabled') { return New-TrackedResult -Success $true -Note 'was already Disabled — nothing to restore' }
    Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
    New-TrackedResult -Success $true
}

# ---------- Appx packages ----------
# NOTE: Undo here is best-effort. Windows has no clean "restore a removed Appx
# package" primitive short of re-provisioning from a DISM image or redownloading
# from the Store — Remove-AppxPackage is not symmetrically reversible the way a
# registry value or service start-mode is. Add-AppxPackage -Register can restore
# a package that's still DE-PROVISIONED-but-staged for the current user, which
# covers the common case (package removed for the current user only), but will
# fail if the package was fully removed for all users / de-provisioned from the
# image. Undo reports success/failure honestly rather than pretending it always
# works — this is a real, documented limitation, not a bug.

function Test-AppxPackageAbsent {
    param([string[]]$NamePatterns)
    $pattern = ($NamePatterns -join '|')
    $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern })
    if ($pkg.Count) { [pscustomobject]@{ Current = "installed: $(($pkg.Name | Select-Object -Unique) -join ', ')"; Compliant = $false } }
    else            { [pscustomobject]@{ Current = 'not installed'; Compliant = $true } }
}

function Remove-AppxPackageTracked {
    param([string[]]$NamePatterns)
    $pattern = ($NamePatterns -join '|')
    $pkg = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern })
    if (-not $pkg.Count) { return New-TrackedResult -Success $true -Note 'not installed — nothing to do' }
    $families = $pkg | Select-Object -ExpandProperty PackageFamilyName -Unique
    foreach ($p in $pkg) { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop }
    New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($families -join ',')
}

function Undo-AppxPackageTracked {
    param([bool]$PreviouslyExisted, $PreviousValue)
    if (-not $PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'was not installed at apply time — nothing to restore' }
    $families = @("$PreviousValue" -split ',' | Where-Object { $_ })
    $restored = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($fam in $families) {
        try { Add-AppxPackage -Register -DisableDevelopmentMode -Path "$env:SystemRoot\WinStore\$fam" -ErrorAction Stop
              $restored.Add($fam) }
        catch { $failed.Add($fam) }
    }
    if ($failed.Count) {
        New-TrackedResult -Success ($restored.Count -gt 0) -Note "could not restore: $($failed -join ', ') — package likely fully de-provisioned; reinstall from Microsoft Store if needed"
    } else {
        New-TrackedResult -Success $true
    }
}

# ---------- game-detection (apply-time safety pre-flight — §8.5) ----------
# ALWAYS queries live. Never reads the cached "Scan PC" process list (§6.7) —
# that data can be minutes/hours stale by the time an apply run actually
# fires, and a false "no game running" read here would be unsafe, not just
# imprecise.

$Script:KnownGameProcessNames = @(
    'RainbowSix', 'r5apex', 'VALORANT-Win64-Shipping', 'csgo', 'cs2',
    'FortniteClient-Win64-Shipping', 'League of Legends', 'RiotClientServices',
    'GTA5', 'RDR2', 'eldenring', 'overwatch'
)

function Test-GameRunningTracked {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $Script:KnownGameProcessNames })
    if ($running.Count) {
        [pscustomobject]@{ GameRunning = $true; Names = ($running.ProcessName -join ', ') }
    } else {
        [pscustomobject]@{ GameRunning = $false; Names = $null }
    }
}

# ---------- NIC (also duplicated in shared\Invoke-SystemScan.ps1 — a
# handful of lines — so each caller stays self-contained rather than
# dot-sourcing a shared helper file just for this) ----------

function Get-ActiveNic {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object Status -eq 'Up' |
        Sort-Object -Property Speed -Descending |
        Select-Object -First 1
}

# ---------- "Scan PC" cached inventory (§6.7) ----------
# Always optional. Every caller must tolerate $null and fall back to
# querying the one piece of information it actually needs itself — the file
# won't exist at all under Pester (§8.7) or before the user ever clicks
# "Scan PC", and scripts must stay independently invokable regardless.

function Get-CachedSystemScan {
    $path = Join-Path $PSScriptRoot 'cache\SystemScan.json'
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { $null }
}
