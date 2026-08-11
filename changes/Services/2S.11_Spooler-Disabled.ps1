# 2S.11 — Spooler -> Disabled (printer-guarded). Services sector.
# Print spooler. Auto-guard: skipped entirely if a real printer is installed.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$Svc = 'Spooler'; $Expected = 'Disabled'

function Get-RealPrinters {
    @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax' })
}

Invoke-PrimeChange -Id '2S.11' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $printers = @(Get-RealPrinters)
        if ($printers.Count) { return [pscustomobject]@{ Current = "printer detected ($($printers[0].Name)) — guarded, would SKIP"; Compliant = $true } }
        Test-ServiceStartMode $Svc $Expected
    } `
    -ApplyBlock {
        if (@(Get-RealPrinters).Count) { return New-TrackedResult -Success $true -Note 'printer detected — guarded, skipped' }
        Set-ServiceStartModeTracked $Svc $Expected
    } `
    -UndoBlock  { param($Prev) Undo-ServiceStartModeTracked $Svc $Prev.PreviouslyExisted $Prev.PreviousValue }
