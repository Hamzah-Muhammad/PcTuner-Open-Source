# 1.18 — Mouse acceleration off. Performance & Hardware sector.
# Raw 1:1 aim — Enhance Pointer Precision disabled.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$RegPath = 'HKCU:\Control Panel\Mouse'

Invoke-PrimeChange -Id '1.18' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $m = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
        $cur = "MouseSpeed=$($m.MouseSpeed) T1=$($m.MouseThreshold1) T2=$($m.MouseThreshold2)"
        [pscustomobject]@{ Current = $cur; Compliant = ($m.MouseSpeed -eq '0' -and $m.MouseThreshold1 -eq '0' -and $m.MouseThreshold2 -eq '0') }
    } `
    -ApplyBlock {
        $m = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
        $prev = @{ MouseSpeed = $m.MouseSpeed; MouseThreshold1 = $m.MouseThreshold1; MouseThreshold2 = $m.MouseThreshold2 }
        Set-ItemProperty -Path $RegPath -Name MouseSpeed -Value '0' -Type String
        Set-ItemProperty -Path $RegPath -Name MouseThreshold1 -Value '0' -Type String
        Set-ItemProperty -Path $RegPath -Name MouseThreshold2 -Value '0' -Type String
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue ($prev | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        Set-ItemProperty -Path $RegPath -Name MouseSpeed -Value $inner.MouseSpeed -Type String
        Set-ItemProperty -Path $RegPath -Name MouseThreshold1 -Value $inner.MouseThreshold1 -Type String
        Set-ItemProperty -Path $RegPath -Name MouseThreshold2 -Value $inner.MouseThreshold2 -Type String
        New-TrackedResult -Success $true
    }
