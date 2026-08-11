# StartupFolderShortcut.ps1 — PC Startup sector action script. Parameterized
# per discovered shortcut from Enumerate.ps1. Apply BACKS UP the file before
# deleting it — a shortcut's binary content can't be reconstructed from a
# JSON string the way a registry DWORD can (§8.5).
param(
    [Parameter(Mandatory)][string]$FilePath,
    [switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson
)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Id = "StartupFolderShortcut:$FilePath"
$BackupDir = Join-Path $ScriptDir '..\..\shared\cache\undo_backups'

Invoke-PrimeChange -Id $Id -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        if (Test-Path $FilePath) { [pscustomobject]@{ Current = 'still starts at logon'; Compliant = $false } }
        else { [pscustomobject]@{ Current = 'no longer in startup'; Compliant = $true } }
    } `
    -ApplyBlock {
        if (-not (Test-Path $FilePath)) { return New-TrackedResult -Success $true -Note 'not present — nothing to do' }
        New-Item -ItemType Directory -Force -Path $BackupDir -ErrorAction SilentlyContinue | Out-Null
        $backupName = "$([guid]::NewGuid().ToString('N'))_$(Split-Path $FilePath -Leaf)"
        $backupPath = Join-Path $BackupDir $backupName
        Copy-Item -Path $FilePath -Destination $backupPath -ErrorAction Stop
        Remove-Item -Path $FilePath -ErrorAction Stop
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $backupPath
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'was not present at apply time' }
        if (-not (Test-Path $Prev.PreviousValue)) { return New-TrackedResult -Success $false -Note 'backup file missing — cannot restore' }
        Copy-Item -Path $Prev.PreviousValue -Destination $FilePath -ErrorAction Stop
        New-TrackedResult -Success $true
    }
