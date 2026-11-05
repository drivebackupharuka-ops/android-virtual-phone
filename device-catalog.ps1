$script:AvpCatalogRoot = Join-Path $env:LOCALAPPDATA 'AndroidVirtualPhone'
$script:AvpAvdRegistryHome = Join-Path $script:AvpCatalogRoot 'avd-index'
$script:AvpCatalogPath = Join-Path $script:AvpCatalogRoot 'devices.json'
$script:AvpManagedAvdRoot = Join-Path $PSScriptRoot '.local\managed-devices'
$script:AvpCarrierName = 'AVP Test Mobile'
$script:AvpCarrierSmsSenderNumber = '12025550138'

function Save-AvpCatalog {
    param([Parameter(Mandatory)]$Catalog)

    $json = ConvertTo-Json -InputObject $Catalog -Depth 6
    [System.IO.File]::WriteAllText($script:AvpCatalogPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Set-AvpAvdIndexEntry {
    param(
        [Parameter(Mandatory)][string]$AvdName,
        [Parameter(Mandatory)][string]$AvdPath
    )

    New-Item -ItemType Directory -Path $script:AvpAvdRegistryHome -Force | Out-Null
    $iniPath = Join-Path $script:AvpAvdRegistryHome "$AvdName.ini"
    $iniContent = "avd.ini.encoding=UTF-8`r`npath=$AvdPath`r`ntarget=android-36`r`n"
    Set-Content -LiteralPath $iniPath -Value $iniContent -Encoding ascii
}

function Get-AvpCatalog {
    New-Item -ItemType Directory -Path $script:AvpCatalogRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:AvpAvdRegistryHome -Force | Out-Null

    if (Test-Path -LiteralPath $script:AvpCatalogPath) {
        $catalog = Get-Content -LiteralPath $script:AvpCatalogPath -Raw | ConvertFrom-Json
        if ($null -eq $catalog.devices) { $catalog | Add-Member -NotePropertyName devices -NotePropertyValue @() -Force }
        $catalog.devices = @($catalog.devices)
    } else {
        $primaryAvdPath = Join-Path $script:AvpCatalogRoot 'avd\AndroidVirtualPhone.avd'
        if (-not (Test-Path -LiteralPath $primaryAvdPath)) {
            $primaryAvdPath = Join-Path $PSScriptRoot '.local\avd\AndroidVirtualPhone.avd'
        }
        if (-not (Test-Path -LiteralPath $primaryAvdPath)) {
            throw "The existing Android Virtual Phone profile was not found: $primaryAvdPath"
        }

        $numberPath = Join-Path $PSScriptRoot '.local\phone-number.txt'
        if (-not (Test-Path -LiteralPath $numberPath)) {
            throw "The existing U.S. demo number was not found: $numberPath"
        }
        $number = (Get-Content -LiteralPath $numberPath -Raw).Trim()
        if ($number -notmatch '^1\d{10}$') { throw 'The existing U.S. demo number is invalid.' }

        $device = [pscustomobject]@{
            name = 'Android Virtual Phone'
            avdName = 'AndroidVirtualPhone'
            avdPath = $primaryAvdPath
            phoneNumber = $number
            carrierName = $script:AvpCarrierName
            region = 'US'
            locale = 'en-US'
            timeZone = 'America/Chicago'
            internetVerified = $true
            smsVerified = $true
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
            lastVerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $catalog = [pscustomobject]@{
            version = 1
            activeAvdName = 'AndroidVirtualPhone'
            devices = @($device)
        }
        Save-AvpCatalog -Catalog $catalog
    }

    $catalogChanged = $false
    foreach ($device in @($catalog.devices)) {
        $carrierProperty = $device.PSObject.Properties['carrierName']
        if (-not $carrierProperty -or [string]::IsNullOrWhiteSpace([string]$device.carrierName)) {
            $device | Add-Member -NotePropertyName carrierName -NotePropertyValue $script:AvpCarrierName -Force
            $catalogChanged = $true
        }
    }
    if ($catalogChanged) { Save-AvpCatalog -Catalog $catalog }

    foreach ($device in @($catalog.devices)) {
        if ($device.avdName -and $device.avdPath -and (Test-Path -LiteralPath $device.avdPath)) {
            Set-AvpAvdIndexEntry -AvdName $device.avdName -AvdPath $device.avdPath
        }
    }
    return $catalog
}

function Get-AvpDevice {
    param(
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$AvdName
    )
    return @($Catalog.devices | Where-Object { $_.avdName -eq $AvdName } | Select-Object -First 1)[0]
}

function Get-AvpNewDemoNumber {
    param([Parameter(Mandatory)]$Catalog)

    $used = @($Catalog.devices | ForEach-Object { [string]$_.phoneNumber })
    $availableLines = @(100..199 | Where-Object {
        $candidate = '1202555{0:D4}' -f $_
        $candidate -notin $used -and $candidate -ne $script:AvpCarrierSmsSenderNumber
    })
    if ($availableLines.Count -eq 0) { throw 'No U.S. demo numbers remain in the reserved 202-555-01xx range.' }
    $line = Get-Random -InputObject $availableLines
    return '1202555{0:D4}' -f $line
}

function Format-AvpPhoneNumber {
    param([Parameter(Mandatory)][string]$Number)
    if ($Number -notmatch '^1\d{10}$') { return $Number }
    return '+1 202-555-' + $Number.Substring(7, 4)
}
