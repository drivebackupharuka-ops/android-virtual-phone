param(
    [string]$AvdName,
    [switch]$ColdBoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$root = $PSScriptRoot
. (Join-Path $root 'device-catalog.ps1')

if ([string]::IsNullOrWhiteSpace($AvdName)) {
    & (Join-Path $root 'phone-menu.ps1') -ColdBoot:$ColdBoot
    return
}

$catalog = Get-AvpCatalog
$device = Get-AvpDevice -Catalog $catalog -AvdName $AvdName
if (-not $device) {
    [System.Windows.Forms.MessageBox]::Show("The device '$AvdName' is not in the phone list. Open Android Virtual Phone to refresh the list.", 'Android Virtual Phone') | Out-Null
    exit 1
}

$sdk = Join-Path $root '.local\android-sdk'
$java = Join-Path $root '.local\runtime\jdk'
$avdHome = $script:AvpAvdRegistryHome
$userHome = Join-Path $root '.local\android-user'
$port = 5566
$serial = "emulator-$port"
$adbEndpoint = "127.0.0.1:$($port + 1)"
$avdDir = [System.IO.Path]::GetFullPath([string]$device.avdPath)

if (-not (Test-Path (Join-Path $sdk 'emulator\emulator.exe'))) {
    [System.Windows.Forms.MessageBox]::Show('The Android emulator is not installed.', 'Android Virtual Phone') | Out-Null
    exit 1
}
if (-not (Test-Path -LiteralPath $avdDir)) {
    [System.Windows.Forms.MessageBox]::Show("The selected device profile is missing: $avdDir", 'Android Virtual Phone') | Out-Null
    exit 1
}

$phoneNumber = ([string]$device.phoneNumber).Trim()
if ($phoneNumber -notmatch '^1\d{10}$') {
    [System.Windows.Forms.MessageBox]::Show('The selected U.S. demo number is invalid.', 'Android Virtual Phone') | Out-Null
    exit 1
}

$env:JAVA_HOME = $java
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_AVD_HOME = $avdHome
$env:ANDROID_USER_HOME = $userHome
$env:Path = "$java\bin;$sdk\platform-tools;$sdk\emulator;$env:Path"

$emulatorPath = Join-Path $sdk 'emulator\emulator.exe'
$adbPath = Join-Path $sdk 'platform-tools\adb.exe'
$liveQemu = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "-port\s+$port(?:\s|$)" } |
    Select-Object -First 1

if ($liveQemu -and $liveQemu.CommandLine -notmatch ('-avd\s+(?:"' + [regex]::Escape($AvdName) + '"|' + [regex]::Escape($AvdName) + ')(?:\s|$)')) {
    & $adbPath connect $adbEndpoint 2>$null | Out-Null
    & $adbPath -s $serial emu kill 2>$null | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $liveQemu = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match "-port\s+$port(?:\s|$)" } |
            Select-Object -First 1
    } while ($liveQemu -and [DateTime]::UtcNow -lt $deadline)
    if ($liveQemu) {
        [System.Windows.Forms.MessageBox]::Show('The open Android device did not shut down cleanly. Close it and try switching devices again.', 'Android Virtual Phone') | Out-Null
        exit 1
    }
}

$emulatorProcess = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match ('-avd\s+(?:"' + [regex]::Escape($AvdName) + '"|' + [regex]::Escape($AvdName) + ')(?:\s|$)') -and $_.CommandLine -match "-port\s+$port(?:\s|$)" } |
    Select-Object -First 1
$emu = $null
if (-not $emulatorProcess) {
    $emulatorArguments = @(
        '-avd', $AvdName,
        '-port', "$port",
        '-timezone', [string]$device.timeZone,
        '-change-language', 'en',
        '-change-country', 'US',
        '-no-boot-anim',
        '-gpu', 'auto'
    )
    if ($ColdBoot) { $emulatorArguments += '-no-snapshot-load' }
    $emu = Start-Process -FilePath $emulatorPath -ArgumentList $emulatorArguments -PassThru -WorkingDirectory $root
}

for ($i = 0; $i -lt 900; $i++) {
    if ($emu) {
        $emu.Refresh()
        if ($emu.HasExited) { exit 1 }
    }
    & $adbPath connect $adbEndpoint 2>$null | Out-Null
    $boot = & $adbPath -s $serial shell getprop sys.boot_completed 2>$null
    if ($LASTEXITCODE -eq 0 -and "$boot".Trim() -eq '1') { break }
    Start-Sleep -Seconds 2
}

if ("$boot".Trim() -ne '1') {
    [System.Windows.Forms.MessageBox]::Show('Android did not finish starting within 30 minutes. Check the emulator window, then try again.', 'Android Virtual Phone') | Out-Null
    exit 1
}

& $adbPath -s $serial shell svc wifi enable | Out-Null
& $adbPath -s $serial emu phonenumber $phoneNumber | Out-Null
& $adbPath -s $serial emu gsm voice home | Out-Null
& $adbPath -s $serial emu gsm data home | Out-Null
& $adbPath -s $serial emu gsm signal-profile 4 | Out-Null
& $adbPath -s $serial emu geo fix -87.6298 41.8781 | Out-Null

$networkReady = $false
for ($i = 0; $i -lt 15; $i++) {
    $wifiStatus = & $adbPath -s $serial shell cmd wifi status 2>$null
    $dnsPing = & $adbPath -s $serial shell ping -c 1 -W 2 google.com 2>$null
    if ("$wifiStatus" -match 'Wifi is connected' -and $LASTEXITCODE -eq 0 -and "$dnsPing" -match '1 received|0% packet loss') {
        $networkReady = $true
        break
    }
    Start-Sleep -Seconds 2
}
$device.internetVerified = $networkReady

if (-not $device.smsVerified) {
    $marker = 'AVP-SMS-VERIFY-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
    $sent = & $adbPath -s $serial emu sms send 2025550138 $marker 2>&1
    $smsVerified = $false
    if ($LASTEXITCODE -eq 0) {
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            $inbox = & $adbPath -s $serial shell content query --uri content://sms/inbox --projection address:body 2>$null
            if ("$inbox" -match [regex]::Escape($marker) -and "$inbox" -match '2025550138|\+12025550138') {
                $smsVerified = $true
                break
            }
            Start-Sleep -Seconds 1
        }
    }
    $device.smsVerified = $smsVerified
}

if ($device.internetVerified -and $device.smsVerified) {
    $device.lastVerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$catalog.activeAvdName = $AvdName
Save-AvpCatalog -Catalog $catalog

if (-not $networkReady) {
    [System.Windows.Forms.MessageBox]::Show('The Android phone started, but Wi-Fi internet was not verified. Check the Windows internet connection and try again.', 'Android Virtual Phone') | Out-Null
} elseif (-not $device.smsVerified) {
    [System.Windows.Forms.MessageBox]::Show('The device started with internet, but the simulated SMS inbox test did not pass. Open Messages and try the test again.', 'Android Virtual Phone') | Out-Null
}
