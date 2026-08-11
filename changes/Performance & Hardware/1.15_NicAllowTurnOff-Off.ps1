# 1.15 — "Allow computer to turn off this device" off (NIC). Performance & Hardware sector.
# OS-initiated NIC power-down causes stutter. Applied via the
# MSPower_DeviceEnable CIM method (root\WMI) — the only one that reliably
# works; verified via Get-NetAdapterPowerManagement, never via a CIM re-read
# of MSPower_DeviceEnable itself (it lies about its own state after a set).
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

function Get-NicPowerDeviceEnableInstance {
    param($PnpDeviceID)
    $needle = $PnpDeviceID -replace '\\', '\\\\'
    Get-CimInstance -Namespace root\WMI -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceName -match [regex]::Escape($PnpDeviceID) }
}

Invoke-PrimeChange -Id '1.15' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $nic = Get-ActiveNic
        if (-not $nic) { return [pscustomobject]@{ Current = 'no active physical adapter'; Compliant = $null } }
        $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
        if (-not $pm) { return [pscustomobject]@{ Current = 'power management info unavailable'; Compliant = $null } }
        $v = "$($pm.AllowComputerToTurnOffDevice)"
        [pscustomobject]@{ Current = "AllowComputerToTurnOffDevice = $v"; Compliant = ($v -in 'Disabled', 'Unsupported') }
    } `
    -ApplyBlock {
        $nic = Get-ActiveNic
        if (-not $nic) { return New-TrackedResult -Success $false -Note 'no active physical adapter' }
        $pmBefore = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction SilentlyContinue
        $inst = Get-NicPowerDeviceEnableInstance $nic.PnpDeviceID
        if (-not $inst) { return New-TrackedResult -Success $false -Note 'no MSPower_DeviceEnable instance found for this adapter' }
        Invoke-CimMethod -InputObject $inst -MethodName SetPowerFieldEnable -Arguments @{ Enable = $false } -ErrorAction Stop | Out-Null
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue "$($pmBefore.AllowComputerToTurnOffDevice)"
    } `
    -UndoBlock {
        param($Prev)
        $nic = Get-ActiveNic
        if (-not $nic) { return New-TrackedResult -Success $false -Note 'no active physical adapter' }
        $wasAllowed = $Prev.PreviousValue -eq 'Enabled'
        $inst = Get-NicPowerDeviceEnableInstance $nic.PnpDeviceID
        if (-not $inst) { return New-TrackedResult -Success $false -Note 'no MSPower_DeviceEnable instance found for this adapter' }
        Invoke-CimMethod -InputObject $inst -MethodName SetPowerFieldEnable -Arguments @{ Enable = $wasAllowed } -ErrorAction Stop | Out-Null
        New-TrackedResult -Success $true
    }
