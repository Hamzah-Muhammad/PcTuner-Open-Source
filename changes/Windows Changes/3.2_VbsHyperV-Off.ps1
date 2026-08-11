# 3.2 — VBS / Memory Integrity / Hyper-V OFF (Level 3, Security Trade-off). Windows Changes sector.
# TRADE-OFF: several % FPS for losing HVCI, Credential Guard, WSL2, Hyper-V,
# Windows Sandbox. Needs a reboot to fully take effect. Guard: Apply REFUSES
# if WSL2/Docker is detected (no interactive prompt available headless, so
# refuse rather than silently break someone's dev environment).
# Note: "Microsoft Hypervisor Service: Degraded" afterward is benign (= off on purpose).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$HvciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
$HvciName = 'Enabled'

function Get-Vbs32State {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $vbs = if ($dg) { $dg.VirtualizationBasedSecurityStatus } else { $null }
    $hvci = try { (Get-ItemProperty $HvciPath -Name $HvciName -ErrorAction Stop).$HvciName } catch { $null }
    $bcd = bcdedit /enum '{current}' 2>$null
    $hvl = if ($bcd) { $l = @($bcd) -match 'hypervisorlaunchtype'; if ($l) { ($l[0] -split '\s+')[-1] } else { 'Off (unset)' } } else { 'unreadable (needs elevation)' }
    [pscustomobject]@{ Vbs = $vbs; Hvci = $hvci; HypervisorLaunchType = $hvl }
}

Invoke-PrimeChange -Id '3.2' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $s = Get-Vbs32State
        $cur = "VBS status = $($s.Vbs) (0=off,2=running); HVCI Enabled = $($s.Hvci); hypervisorlaunchtype = $($s.HypervisorLaunchType)"
        if ($null -eq $s.Vbs) { return [pscustomobject]@{ Current = $cur; Compliant = $null } }
        [pscustomobject]@{ Current = $cur; Compliant = ($s.Vbs -eq 0 -and $s.Hvci -ne 1) }
    } `
    -ApplyBlock {
        $wsl = @(Get-Service -Name 'LxssManager' -ErrorAction SilentlyContinue) + @(Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue)
        if ($wsl.Count) { return New-TrackedResult -Success $false -Note 'refused: WSL2/Docker service detected — disabling Hyper-V would break it. Remove manually if you intend to proceed.' }
        $prev = Get-Vbs32State
        $regResult = Set-RegValueTracked $HvciPath $HvciName 0
        bcdedit /set hypervisorlaunchtype off | Out-Null
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue (@{ Reg = $regResult; PrevHvl = $prev.HypervisorLaunchType } | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'apply was refused — nothing to undo' }
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        # Captured, not left as bare pipeline output — unsuppressed, this
        # object becomes a SECOND item in the block's result alongside the
        # final New-TrackedResult below, turning the JSON into a 2-element
        # array instead of the single object PrimeHeadless/Pydantic expect.
        Undo-RegValueTracked $HvciPath $HvciName $inner.Reg.PreviouslyExisted $inner.Reg.PreviousValue | Out-Null
        bcdedit /set hypervisorlaunchtype auto | Out-Null
        New-TrackedResult -Success $true -Note 'reboot required for hypervisorlaunchtype change to take effect'
    }
