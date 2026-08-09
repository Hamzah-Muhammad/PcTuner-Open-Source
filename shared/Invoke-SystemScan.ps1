# Invoke-SystemScan.ps1 — the "Scan PC" broad system inventory (§6.7).
# One coherent read, not a per-item "change" script — no -Check/-Apply/-Undo
# modes, just gathers and reports. Writes shared\cache\SystemScan.json (read
# by individual change scripts via Get-CachedSystemScan in PrimeChecks.ps1,
# always as an optional fallback, never a hard dependency) AND prints the
# same JSON to stdout for the Python caller.
#
# Usage:  .\Invoke-SystemScan.ps1 -Json
#
# Deliberately does NOT use Get-CimInstance Win32_Product for installed
# software — it's known to trigger MSI self-repairs on every call and is
# slow enough to be a real anti-pattern. Installed software is read from the
# registry Uninstall keys instead (the same source Programs & Features uses).

param([switch]$Json)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir 'PrimeChecks.ps1')

# ---------- PC specs (kept self-contained here rather than dot-sourcing a
# shared helper file, so this stays a standalone, independently-invokable
# script) ----------
function Get-ScanPCSpecs {
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpu  = Get-CimInstance Win32_VideoController |
                Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $dimm = Get-CimInstance Win32_PhysicalMemory
    $ramGb    = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $ramSpeed = ($dimm | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
    $disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
        '{0} ({1} GB)' -f ($_.Model -replace '\s+', ' ').Trim(), [math]::Round($_.Size / 1GB)
    }
    $nic = Get-ActiveNic
    [pscustomobject]@{
        CPU   = $cpu.Name.Trim()
        Cores = '{0}C / {1}T' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
        GPU   = $gpu.Name
        RAM   = '{0} GB @ {1} MHz' -f $ramGb, $ramSpeed
        OS    = '{0} (build {1})' -f $os.Caption.Trim(), $os.BuildNumber
        Disks = $disks -join ' · '
        NIC   = if ($nic) { '{0} ({1})' -f $nic.InterfaceDescription, $nic.LinkSpeed } else { 'none up' }
    }
}

# ---------- installed software (registry Uninstall keys, not Win32_Product) ----------
function Get-PropOrNull {
    param($Obj, [string]$Name)
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Get-InstalledSoftware {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName     = Get-PropOrNull $_ 'DisplayName'
                DisplayVersion  = Get-PropOrNull $_ 'DisplayVersion'
                SystemComponent = Get-PropOrNull $_ 'SystemComponent'
            }
        } |
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } |
        Sort-Object DisplayName -Unique |
        ForEach-Object { [pscustomobject]@{ Name = $_.DisplayName; Version = [string]$_.DisplayVersion } }
}

# ---------- running processes ----------
function Get-RunningProcessSummary {
    Get-Process -ErrorAction SilentlyContinue |
        Select-Object -Property @{N='Name';E={$_.ProcessName}}, @{N='Pid';E={$_.Id}}
}

$specs = Get-ScanPCSpecs
$software = @(Get-InstalledSoftware)
$processes = @(Get-RunningProcessSummary)

$scan = [ordered]@{
    ScannedAt         = (Get-Date).ToString('o')
    Specs             = $specs
    InstalledSoftware = $software
    RunningProcesses  = $processes
}

$cacheDir = Join-Path $ScriptDir 'cache'
New-Item -ItemType Directory -Force -Path $cacheDir -ErrorAction SilentlyContinue | Out-Null
$scan | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $cacheDir 'SystemScan.json') -Encoding UTF8

$scan | ConvertTo-Json -Depth 6 -Compress
