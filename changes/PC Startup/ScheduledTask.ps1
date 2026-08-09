# ScheduledTask.ps1 — PC Startup sector action script. Parameterized per
# discovered logon/boot task from Enumerate.ps1 — not a fixed catalog item.
param(
    [Parameter(Mandatory)][string]$TaskPath,
    [Parameter(Mandatory)][string]$TaskName,
    [switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson
)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Id = "ScheduledTask:$TaskPath$TaskName"

Invoke-PrimeChange -Id $Id -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $t) { return [pscustomobject]@{ Current = 'task no longer exists'; Compliant = $true } }
        if ($t.State -eq 'Disabled') { [pscustomobject]@{ Current = 'task disabled'; Compliant = $true } }
        else { [pscustomobject]@{ Current = "task $($t.State) — runs at logon/boot"; Compliant = $false } }
    } `
    -ApplyBlock { Disable-ScheduledTaskTracked $TaskPath $TaskName } `
    -UndoBlock  { param($Prev) Undo-ScheduledTaskTracked $TaskPath $TaskName $Prev.PreviouslyExisted $Prev.PreviousValue }
