# 1.14 — NIC power-saving property cluster off. Performance & Hardware sector.
# Energy-Efficient Ethernet / Green Ethernet / Power Saving Mode / Gigabit
# Lite / Wake-on-pattern cause micro-stutter and latency spikes. Only
# properties that exist on your adapter are touched. Applying resets the
# adapter ~2s — never runs mid-game.
param([switch]$Check, [switch]$Apply, [switch]$Undo, [string]$PreviousValueJson)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
. (Join-Path $ScriptDir '..\..\shared\PrimeChecks.ps1')
. (Join-Path $ScriptDir '..\..\shared\PrimeHeadless.ps1')

$PropNames = 'Energy-Efficient Ethernet', 'Energy Efficient Ethernet', 'EEE', 'Advanced EEE',
             'Green Ethernet', 'Power Saving Mode', 'Gigabit Lite', 'Wake on pattern match'

Invoke-PrimeChange -Id '1.14' -Check:$Check -Apply:$Apply -Undo:$Undo -PreviousValueJson $PreviousValueJson `
    -CheckBlock {
        $nic = Get-ActiveNic
        if (-not $nic) { return [pscustomobject]@{ Current = 'no active physical adapter'; Compliant = $null } }
        $props = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object { $PropNames -contains $_.DisplayName })
        if (-not $props.Count) { return [pscustomobject]@{ Current = "adapter '$($nic.Name)' exposes none of these properties"; Compliant = $true } }
        $bad = @($props | Where-Object { $_.DisplayValue -notin 'Disabled', 'Off' })
        $cur = ($props | ForEach-Object { "$($_.DisplayName)=$($_.DisplayValue)" }) -join '; '
        [pscustomobject]@{ Current = $cur; Compliant = ($bad.Count -eq 0) }
    } `
    -ApplyBlock {
        $nic = Get-ActiveNic
        if (-not $nic) { return New-TrackedResult -Success $false -Note 'no active physical adapter' }
        $props = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object { $PropNames -contains $_.DisplayName })
        if (-not $props.Count) { return New-TrackedResult -Success $true -Note 'adapter exposes none of these properties' }
        $prev = @{}
        foreach ($p in $props) {
            $prev[$p.DisplayName] = $p.DisplayValue
            Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $p.DisplayName -DisplayValue 'Disabled' -ErrorAction SilentlyContinue
        }
        New-TrackedResult -Success $true -PreviouslyExisted $true -PreviousValue (@{ NicName = $nic.Name; Props = $prev } | ConvertTo-Json -Compress)
    } `
    -UndoBlock {
        param($Prev)
        if (-not $Prev.PreviouslyExisted) { return New-TrackedResult -Success $true -Note 'nothing changed at apply time' }
        $inner = $Prev.PreviousValue | ConvertFrom-Json
        foreach ($name in $inner.Props.PSObject.Properties.Name) {
            Set-NetAdapterAdvancedProperty -Name $inner.NicName -DisplayName $name -DisplayValue $inner.Props.$name -ErrorAction SilentlyContinue
        }
        New-TrackedResult -Success $true -Note 'device reset (~2s) applies the change — never run mid-game'
    }
