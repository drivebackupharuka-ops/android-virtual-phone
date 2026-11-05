$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

$root = $PSScriptRoot
. (Join-Path $root 'device-catalog.ps1')
$catalog = Get-AvpCatalog
$deviceInfo = Get-AvpDevice -Catalog $catalog -AvdName ([string]$catalog.activeAvdName)
if (-not $deviceInfo) { throw 'No active Android device is selected.' }
$sdk = Join-Path $root '.local\android-sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_AVD_HOME = $script:AvpAvdRegistryHome
$env:ANDROID_USER_HOME = Join-Path $root '.local\android-user'

$message = [Microsoft.VisualBasic.Interaction]::InputBox("AVP Test Mobile can inject a local-only SMS to $($deviceInfo.name) ($(Format-AvpPhoneNumber -Number ([string]$deviceInfo.phoneNumber))). This does not use a cellular network:", 'AVP Test Mobile')
if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }

$serial = 'emulator-5566'
$device = & $adb devices | Where-Object { $_ -match "^$serial\s+device(?:\s|$)" } | Select-Object -First 1
if (-not $device) {
    [System.Windows.Forms.MessageBox]::Show('Start Android Virtual Phone first, then send the test SMS again.', 'Android Virtual Phone') | Out-Null
    exit 1
}
$sender = $script:AvpCarrierSmsSenderNumber
& $adb -s $serial emu sms send $sender $message | Out-Null
if ($LASTEXITCODE -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("AVP Test Mobile delivered a simulated SMS from $(Format-AvpPhoneNumber -Number $sender). It stayed inside the emulator.", 'AVP Test Mobile') | Out-Null
} else {
    [System.Windows.Forms.MessageBox]::Show('The emulator did not accept the test SMS. Make sure Android Virtual Phone has finished starting.', 'AVP Test Mobile') | Out-Null
}
