# PrimeHeadless.ps1 — mode-dispatch harness for every individual change
# script under changes\<Sector>\*.ps1. Dot-source AFTER shared\PrimeChecks.ps1.
#
# No WPF, no STA relaunch, no self-elevation prompt here on purpose — the
# Python host (or a human running a script directly) is already elevated,
# and child processes inherit that token (§3.5). A change script that needs
# nothing more than "run this check/apply/undo and print JSON" doesn't need
# any elevation ceremony of its own — that's app.py's job.
#
# Calling convention (every changes\<Sector>\*.ps1 file follows this shape):
#   param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
#   . (Join-Path $PSScriptRoot '..\..\shared\PrimeChecks.ps1')
#   . (Join-Path $PSScriptRoot '..\..\shared\PrimeHeadless.ps1')
#   Invoke-PrimeChange -Id '1.1' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
#       -CheckBlock { ... } -ApplyBlock { ... } -UndoBlock { param($Prev) ... }
#
# Exit-code contract (§5.5): 0 whenever a JSON payload was produced —
# including a Check result that itself reads ERROR-shaped for a check that
# threw inside its own try/catch. A non-zero exit here means the SCRIPT
# itself broke (unhandled exception outside any per-item try/catch), which
# ps_bridge.py treats as a hard, scoped-to-this-Id failure — never salvaged.

Set-StrictMode -Version 2

function Invoke-PrimeChange {
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Check,
        [switch]$Apply,
        [switch]$Undo,
        [string]$PreviousValueJson,
        [Parameter(Mandatory)][scriptblock]$CheckBlock,
        [scriptblock]$ApplyBlock,
        [scriptblock]$UndoBlock
    )

    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    $ErrorActionPreference = 'Stop'

    try {
        if ($Apply) {
            if (-not $ApplyBlock) { throw "Apply is not implemented for $Id" }
            $r = & $ApplyBlock
            $result = [ordered]@{
                Id = $Id; Mode = 'Apply'; Success = [bool]$r.Success
                PreviouslyExisted = $r.PreviouslyExisted; PreviousValue = $r.PreviousValue; Note = $r.Note
            }
        }
        elseif ($Undo) {
            if (-not $UndoBlock) { throw "Undo is not implemented for $Id" }
            if (-not $PreviousValueJson) { throw "Undo for $Id requires -PreviousValueJson" }
            $prev = $PreviousValueJson | ConvertFrom-Json
            $r = & $UndoBlock $prev
            $result = [ordered]@{ Id = $Id; Mode = 'Undo'; Success = [bool]$r.Success; Note = $r.Note }
        }
        else {
            # default mode is Check, whether -Check was passed explicitly or not
            $r = & $CheckBlock
            $status = switch ($r.Compliant) {
                $true   { 'APPLIED' }
                $false  { 'PENDING' }
                default { 'REVIEW' }
            }
            $result = [ordered]@{ Id = $Id; Mode = 'Check'; Status = $status; Current = $r.Current }
        }
        $result | ConvertTo-Json -Depth 6 -Compress
    }
    catch {
        [ordered]@{ Id = $Id; Error = $_.Exception.Message } | ConvertTo-Json -Compress
        exit 1
    }
}
