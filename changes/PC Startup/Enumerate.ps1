# Enumerate.ps1 — discovery step for the PC Startup sector (§3). PC-specific,
# not a static catalog like the other sectors — lists every Run-key entry,
# startup-folder shortcut, and logon/boot scheduled task actually present on
# THIS PC, with enough identifying detail (registry path+name, file path,
# task path+name) for Python to invoke the right action script
# (RunKeyEntry.ps1 / StartupFolderShortcut.ps1 / ScheduledTask.ps1) against
# each discovered instance. One subprocess call — fast, side-effect-free.
#
# Usage: .\Enumerate.ps1 -Json

param([switch]$Json)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# IDs must be derived from an entry's own identity (location + name), never
# from enumeration position — Python's undo/re-scan flow re-runs this script
# and matches results back up by Id. A positional "R.$n" scheme means
# removing entry #1 silently renumbers every entry after it, so a later
# Undo (or even an immediate re-scan of the same `checked` set) resolves the
# wrong Id to a real registry value/task/file that was never touched. A
# short hash of the entry's own (Tag, Name) pair stays stable regardless of
# what else was added or removed around it, and simply stops appearing at
# all once the entry itself is gone — which is the correct behavior.
function New-ContentId {
    param([string]$Prefix, [string]$Identity)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Identity)
    $hash = [System.Security.Cryptography.SHA1]::Create().ComputeHash($bytes)
    $hex = -join ($hash[0..2] | ForEach-Object { $_.ToString('x2') })
    return "$Prefix.$hex"
}

# ---------- annotations for well-known startup entries ----------
# Keep = recommended keep (item starts UNCHECKED so a general client doesn't
# remove it by accident).
function Get-StartupAnnotation {
    param($Name)
    switch -Regex ($Name) {
        '^SecurityHealth$'        { return @{ Keep = $true;  Note = 'Windows Security tray icon — recommended KEEP.' } }
        'OneDrive'                { return @{ Keep = $false; Note = 'Cloud file sync. UNCHECK if you rely on OneDrive syncing from the moment you log in.' } }
        'Discord'                 { return @{ Keep = $false; Note = 'Chat app — opens fine on demand, not needed at boot.' } }
        'Steam|EpicGames|GOG'     { return @{ Keep = $false; Note = 'Game launcher — start it when you actually game.' } }
        'Spotify'                 { return @{ Keep = $false; Note = 'Music app — not needed at boot.' } }
        'Teams'                   { return @{ Keep = $false; Note = 'Meetings app — starts fast on demand.' } }
        'vgtray|Vanguard|Riot'    { return @{ Keep = $false; Note = 'Game anticheat/launcher tray. Removing from startup may require re-enabling before that game runs.' } }
        'Rtk|Realtek'             { return @{ Keep = $false; Note = 'Audio vendor tray — audio keeps working without it.' } }
        'iTunesHelper|CCleaner|Update' { return @{ Keep = $false; Note = 'Helper/updater — the app updates itself when opened.' } }
        default                   { return @{ Keep = $false; Note = 'Starts at every logon. Removing it speeds up boot; you can still open the app manually.' } }
    }
}

$items = [System.Collections.Generic.List[object]]::new()

# ---------- Run keys ----------
$runLocations = @(
    @{ Tag = 'HKCU';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    @{ Tag = 'HKCU-RO'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' }
    @{ Tag = 'HKLM';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    @{ Tag = 'HKLM-RO'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    @{ Tag = 'HKLM32';  Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run' }
)
$rCount = 0
foreach ($loc in $runLocations) {
    $key = Get-Item -Path $loc.Path -ErrorAction SilentlyContinue
    if (-not $key) { continue }
    foreach ($valName in ($key.GetValueNames() | Where-Object { $_ })) {
        $rCount++
        $cmd = [string]$key.GetValue($valName)
        if ($cmd.Length -gt 110) { $cmd = $cmd.Substring(0, 107) + '…' }
        $ann = Get-StartupAnnotation $valName
        $items.Add([pscustomobject]@{
            Id = (New-ContentId 'R' "$($loc.Tag)|$valName"); Level = 1; Module = 'Registry Run Entries'
            Kind = 'RunKeyEntry'; Name = "$valName  [$($loc.Tag)]"
            Desc = "$($ann.Note)  Command: $cmd"; Target = 'entry removed from startup'
            DefaultChecked = (-not $ann.Keep)
            RegPath = $loc.Path; ValueName = $valName
        })
    }
}
if ($rCount -eq 0) {
    $items.Add([pscustomobject]@{
        Id = 'R.0'; Level = 1; Module = 'Registry Run Entries'
        Kind = $null; Name = 'No Run-key startup entries found'
        Desc = 'Your registry startup surface is already clean.'; Target = 'nothing to remove'
        DefaultChecked = $false
    })
}

# ---------- Startup folder shortcuts ----------
$folderLocations = @(
    @{ Tag = 'user';   Path = [Environment]::GetFolderPath('Startup') }
    @{ Tag = 'common'; Path = [Environment]::GetFolderPath('CommonStartup') }
)
$fCount = 0
foreach ($loc in $folderLocations) {
    if (-not $loc.Path -or -not (Test-Path $loc.Path)) { continue }
    foreach ($file in (Get-ChildItem -Path $loc.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $fCount++
        $ann = Get-StartupAnnotation $file.BaseName
        $items.Add([pscustomobject]@{
            Id = (New-ContentId 'F' "$($loc.Tag)|$($file.Name)"); Level = 1; Module = 'Startup Folder Shortcuts'
            Kind = 'StartupFolderShortcut'; Name = "$($file.Name)  [$($loc.Tag)]"
            Desc = "$($ann.Note)  Location: $($file.FullName)"; Target = 'shortcut removed from Startup folder'
            DefaultChecked = (-not $ann.Keep)
            FilePath = $file.FullName
        })
    }
}
if ($fCount -eq 0) {
    $items.Add([pscustomobject]@{
        Id = 'F.0'; Level = 1; Module = 'Startup Folder Shortcuts'
        Kind = $null; Name = 'Startup folders are empty'
        Desc = 'No shortcuts auto-launch from your Startup folders.'; Target = 'nothing to remove'
        DefaultChecked = $false
    })
}

# ---------- Logon/boot scheduled tasks ----------
# Scope: root-path third-party tasks, Office logon tasks, Edge/Google
# updater logon tasks. \Microsoft\Windows\* system tasks deliberately NOT
# touched (many are OS-critical).
$tCount = 0
$allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
foreach ($task in $allTasks) {
    $triggers = @($task.Triggers | Where-Object { $_ } | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger|BootTrigger' })
    if (-not $triggers.Count) { continue }
    $inScope = ($task.TaskPath -eq '\') -or
               ($task.TaskPath -like '\Microsoft\Office*') -or
               ($task.TaskName -like 'MicrosoftEdgeUpdate*') -or
               ($task.TaskName -like 'GoogleUpdater*')
    if (-not $inScope) { continue }

    $exe = ''
    $action = @($task.Actions | Select-Object -First 1)
    if ($action.Count -and $action[0].PSObject.Properties['Execute']) { $exe = [string]$action[0].Execute }
    if ($exe.Length -gt 80) { $exe = $exe.Substring(0, 77) + '…' }

    $keep = $task.TaskName -match 'FanControl|Afterburner|RTSS'
    $note = if ($keep) { 'Hardware control tool — KEEP if it manages your fans/overclock.' }
            elseif ($task.TaskName -like 'MicrosoftEdgeUpdate*') { 'Logon-triggered updater. Edge still updates via its periodic task.' }
            elseif ($task.TaskPath -like '\Microsoft\Office*') { 'Office logon task — Office re-enables these on updates; re-run this tool after Office updates.' }
            else { 'Runs at logon/boot. Disabling speeds up startup; the app itself is untouched.' }

    $tCount++
    $items.Add([pscustomobject]@{
        Id = (New-ContentId 'T' "$($task.TaskPath)|$($task.TaskName)"); Level = 2; Module = 'Logon Scheduled Tasks'
        Kind = 'ScheduledTask'; Name = $task.TaskName
        Desc = "$note  Path: $($task.TaskPath)  Runs: $exe"; Target = 'task Disabled'
        DefaultChecked = (-not $keep)
        TaskPath = $task.TaskPath; TaskName = $task.TaskName
    })
}
if ($tCount -eq 0) {
    $items.Add([pscustomobject]@{
        Id = 'T.0'; Level = 2; Module = 'Logon Scheduled Tasks'
        Kind = $null; Name = 'No third-party logon tasks found'
        Desc = 'No in-scope tasks trigger at logon/boot.'; Target = 'nothing to disable'
        DefaultChecked = $false
    })
}

$items | ConvertTo-Json -Depth 6 -Compress
