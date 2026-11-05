$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$wsh = New-Object -ComObject WScript.Shell
$icon = Join-Path $root '.local\android-sdk\emulator\emulator.exe'

$phone = $wsh.CreateShortcut((Join-Path $menu 'Android Virtual Phone.lnk'))
$phone.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$phone.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $root 'launch-phone.ps1')`""
$phone.WorkingDirectory = $root
$phone.IconLocation = "$icon,0"
$phone.Description = 'Choose and open a U.S. Android virtual phone'
$phone.Save()

$sms = $wsh.CreateShortcut((Join-Path $menu 'Send Test SMS to Android Virtual Phone.lnk'))
$sms.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$sms.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $root 'send-test-sms.ps1')`""
$sms.WorkingDirectory = $root
$sms.IconLocation = "$icon,0"
$sms.Description = 'Inject a simulated incoming SMS from AVP Test Mobile; it stays inside the emulator'
$sms.Save()

$desktopPath = [Environment]::GetFolderPath('Desktop')
$desktopPhone = $wsh.CreateShortcut((Join-Path $desktopPath 'Android Virtual Phone.lnk'))
$desktopPhone.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$desktopPhone.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $root 'launch-phone.ps1')`""
$desktopPhone.WorkingDirectory = $root
$desktopPhone.IconLocation = "$icon,0"
$desktopPhone.Description = 'Choose and open a U.S. Android virtual phone'
$desktopPhone.Save()
