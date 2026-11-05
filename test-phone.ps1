param(
    [switch]$SkipAppLaunches
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'device-catalog.ps1')
$catalog = Get-AvpCatalog
$device = Get-AvpDevice -Catalog $catalog -AvdName ([string]$catalog.activeAvdName)
if (-not $device) { throw 'No active Android device is selected.' }
$sdk = Join-Path $root '.local\android-sdk'
$adbPath = Join-Path $sdk 'platform-tools\adb.exe'
$env:ANDROID_AVD_HOME = $script:AvpAvdRegistryHome
$env:ANDROID_USER_HOME = Join-Path $root '.local\android-user'
$serial = 'emulator-5566'
$script:results = New-Object System.Collections.ArrayList

if (-not (Test-Path -LiteralPath $adbPath)) {
    Write-Error "Android SDK platform tools were not found at $adbPath"
    exit 1
}

function Invoke-Android {
    param([string[]]$Arguments)

    $output = & $script:adbPath -s $script:serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
    return (($output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

function Invoke-Check {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        $detail = (& $Action | Out-String).Trim()
        if (-not $detail) { $detail = 'OK' }
        [void]$script:results.Add([pscustomobject]@{ Name = $Name; Passed = $true; Detail = $detail })
        Write-Host "[PASS] $Name — $detail" -ForegroundColor Green
    } catch {
        $detail = $_.Exception.Message
        [void]$script:results.Add([pscustomobject]@{ Name = $Name; Passed = $false; Detail = $detail })
        Write-Host "[FAIL] $Name — $detail" -ForegroundColor Red
    }
}

$devices = & $adbPath devices 2>&1
$deviceEntry = $devices | Where-Object { $_ -match "^$serial\s+" } | Select-Object -First 1
if (-not $deviceEntry -or $deviceEntry -notmatch "^$serial\s+device(?:\s|$)") {
    Write-Host "[FAIL] ADB device — $serial is not online. Start Android Virtual Phone first." -ForegroundColor Red
    exit 1
}

Invoke-Check 'Android boot' {
    $value = Invoke-Android @('shell', 'getprop', 'sys.boot_completed')
    if ($value -ne '1') { throw "sys.boot_completed=$value" }
    'boot completed'
}

Invoke-Check 'U.S. locale and time zone' {
    $locale = Invoke-Android @('shell', 'getprop', 'ro.product.locale')
    $zone = Invoke-Android @('shell', 'getprop', 'persist.sys.timezone')
    if ($locale -ne 'en-US' -or $zone -ne 'America/Chicago') { throw "locale=$locale; time zone=$zone" }
    "$locale; $zone"
}

Invoke-Check 'Mock carrier and fictional U.S. number' {
    if ([string]$device.carrierName -ne $script:AvpCarrierName) {
        throw "carrier=$($device.carrierName)"
    }
    $phoneNumber = ([string]$device.phoneNumber).Trim()
    if ($phoneNumber -notmatch '^120255501\d{2}$' -or $phoneNumber -eq $script:AvpCarrierSmsSenderNumber) {
        throw "Invalid or reserved test sender number: $phoneNumber"
    }
    "$($device.carrierName); $(Format-AvpPhoneNumber -Number $phoneNumber) (fictional)"
}

Invoke-Check 'U.S. simulated mobile profile' {
    $country = Invoke-Android @('shell', 'getprop', 'gsm.sim.operator.iso-country')
    $mccMnc = Invoke-Android @('shell', 'getprop', 'gsm.sim.operator.numeric')
    if ($country -ne 'us' -or $mccMnc -notmatch '^310') { throw "country=$country; operator=$mccMnc" }
    "country=$country; operator=$mccMnc"
}

Invoke-Check 'Wi-Fi enabled' {
    $status = Invoke-Android @('shell', 'cmd', 'wifi', 'status')
    if ($status -notmatch 'Wifi is enabled' -or $status -notmatch 'Wifi is connected') { throw $status }
    'enabled and connected to AndroidWifi'
}

Invoke-Check 'Internet and DNS' {
    $output = ''
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try { $output = Invoke-Android @('shell', 'ping', '-c', '1', '-W', '5', 'google.com') }
        catch { $output = $_.Exception.Message }
        if ($output -match '1 received' -or $output -match '0% packet loss') {
            "google.com replied (attempt $attempt)"
            return
        }
        Start-Sleep -Seconds 2
    }
    throw $output
}

foreach ($app in @(
    @{ Name = 'Google Play Store'; Package = 'com.android.vending' },
    @{ Name = 'Gmail'; Package = 'com.google.android.gm' },
    @{ Name = 'Google Messages'; Package = 'com.google.android.apps.messaging' }
)) {
    Invoke-Check "$($app.Name) installed" {
        $path = Invoke-Android @('shell', 'pm', 'path', $app.Package)
        if ($path -notmatch '^package:') { throw "$($app.Package) is not installed" }
        "$($app.Name) installed"
    }
}

Invoke-Check 'Messages is default SMS app' {
    $roles = Invoke-Android @('shell', 'dumpsys', 'role')
    if ($roles -notmatch 'name=android\.app\.role\.SMS' -or $roles -notmatch 'holders=com\.google\.android\.apps\.messaging') {
        throw 'Google Messages does not hold the SMS role'
    }
    'Google Messages holds SMS role'
}

Invoke-Check 'Simulated SMS received' {
    $sender = $script:AvpCarrierSmsSenderNumber
    $body = 'AVP-SMOKE-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $phoneNumber = ([string]$script:device.phoneNumber).Trim()
    if ($phoneNumber -notmatch '^120255501\d{2}$') { throw 'Saved fictional U.S. number is invalid' }

    $sendResult = & $script:adbPath -s $script:serial emu sms send $sender $body 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($sendResult | ForEach-Object { $_.ToString() }) -join "`n") }

    $inbox = ''
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $inbox = Invoke-Android @('shell', 'content', 'query', '--uri', 'content://sms/inbox', '--projection', 'address:body')
        $inboxText = [string]::Join("`n", @($inbox | ForEach-Object { [string]$_ }))
        if ($inboxText -match [regex]::Escape($body)) { break }
        Start-Sleep -Seconds 1
    }
    if ($inboxText -notmatch [regex]::Escape($body) -or $inboxText -notmatch ('\+' + [regex]::Escape($sender))) {
        throw "Incoming message was not found in the SMS inbox: $inboxText"
    }
    "received local test SMS from $(Format-AvpPhoneNumber -Number $sender); fictional line $(Format-AvpPhoneNumber -Number $phoneNumber)"
}

if (-not $SkipAppLaunches) {
    foreach ($app in @(
        @{ Name = 'Google Play Store'; Package = 'com.android.vending' },
        @{ Name = 'Gmail'; Package = 'com.google.android.gm' },
        @{ Name = 'Google Messages'; Package = 'com.google.android.apps.messaging' }
    )) {
        Invoke-Check "$($app.Name) opens" {
            $output = Invoke-Android @(
                'shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
                '-c', 'android.intent.category.LAUNCHER', '-p', $app.Package
            )
            if ($output -notmatch 'Status: ok') { throw $output }
            $time = [regex]::Match($output, 'TotalTime:\s*(\d+)')
            if ($time.Success) { "opened; Android launch time $($time.Groups[1].Value) ms" }
            else { 'opened' }
        }
        try { Invoke-Android @('shell', 'input', 'keyevent', '3') | Out-Null } catch { }
    }
}

try { Invoke-Android @('shell', 'input', 'keyevent', '3') | Out-Null } catch { }

$os = Get-CimInstance Win32_OperatingSystem
$freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$emuProcess = Get-Process -Name qemu-system-x86_64 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($emuProcess) {
    $emuMemoryGB = [math]::Round($emuProcess.WorkingSet64 / 1GB, 2)
    Write-Host "[INFO] Windows free RAM: $freeMemoryGB GB; emulator process working set: $emuMemoryGB GB"
} else {
    Write-Host "[INFO] Windows free RAM: $freeMemoryGB GB; emulator process was not found"
}

$passed = @($script:results | Where-Object { $_.Passed }).Count
$failed = @($script:results | Where-Object { -not $_.Passed }).Count
Write-Host "`n$passed passed; $failed failed."
if ($failed -gt 0) { exit 1 }
