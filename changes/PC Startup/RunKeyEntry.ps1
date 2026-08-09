# RunKeyEntry.ps1 — PC Startup sector action script. Parameterized per
# discovered Run-key entry from Enumerate.ps1 — not a fixed catalog item.
param(
    [Parameter(Mandatory)][string]$RegPath,
    [Parameter(Mandatory)][string]$ValueName,
    [switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson
)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Id = "RunKeyEntry:$RegPath\$ValueName"

Invoke-PrimeChange -Id $Id -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $k = Get-Item -Path $RegPath -ErrorAction SilentlyContinue
        if ($k -and ($k.GetValueNames() -contains $ValueName)) { [pscustomobject]@{ Current = 'still starts at logon'; Compliant = $false } }
        else { [pscustomobject]@{ Current = 'no longer in startup'; Compliant = $true } }
    } `
    -ApplyBlock {
        $k = Get-Item -Path $RegPath -ErrorAction SilentlyContinue
        if (-not $k -or ($k.GetValueNames() -notcontains $ValueName)) { return New-TrackedResult -Success $true -Note 'not present — nothing to do' }
        $val = $k.GetValue($ValueName)
        Remove-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction Stop
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue $val
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'was not present at apply time' }
        Set-ItemProperty -Path $RegPath -Name $ValueName -Value $Prev.PreviousValue -Type String -ErrorAction Stop
        New-TrackedResult -Success $true
    }
