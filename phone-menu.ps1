param([switch]$ColdBoot)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'device-catalog.ps1')

$root = $PSScriptRoot
$sdk = Join-Path $root '.local\android-sdk'
$java = Join-Path $root '.local\runtime\jdk'
$avdManager = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
$adbPath = Join-Path $sdk 'platform-tools\adb.exe'
$powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$systemImage = 'system-images;android-36;google_apis_playstore;x86_64'

$env:JAVA_HOME = $java
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_AVD_HOME = $script:AvpAvdRegistryHome
$env:ANDROID_USER_HOME = Join-Path $root '.local\android-user'
$env:Path = "$java\bin;$sdk\platform-tools;$sdk\emulator;$env:Path"

function Get-RunningPhoneAvd {
    $process = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '-port\s+5566(?:\s|$)' } |
        Select-Object -First 1
    if (-not $process) { return $null }
    $match = [regex]::Match($process.CommandLine, '-avd\s+(?:"([^"]+)"|(\S+))')
    if (-not $match.Success) { return $null }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}

function Start-SelectedPhone {
    param([Parameter(Mandatory)]$Device)

    $script:Catalog.activeAvdName = $Device.avdName
    Save-AvpCatalog -Catalog $script:Catalog
    $launcher = Join-Path $root 'launch-phone.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -AvdName $($Device.avdName)"
    if ($ColdBoot) { $arguments += ' -ColdBoot' }
    Start-Process -FilePath $powershellPath -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    $form.Close()
}

function Set-NewAvdDefaults {
    param([Parameter(Mandatory)][string]$AvdPath)

    $configPath = Join-Path $AvdPath 'config.ini'
    if (-not (Test-Path -LiteralPath $configPath)) { throw "Android did not create AVD config: $configPath" }

    $settings = [ordered]@{
        'PlayStore.enabled' = 'true'
        'disk.dataPartition.size' = '10G'
        'hw.cpu.ncore' = '4'
        'hw.device.manufacturer' = 'Google'
        'hw.device.name' = 'pixel_8'
        'hw.gpu.mode' = 'auto'
        'hw.lcd.density' = '420'
        'hw.lcd.height' = '2400'
        'hw.lcd.width' = '1080'
        'hw.ramSize' = '4096'
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $configPath) {
        foreach ($line in (Get-Content -LiteralPath $configPath)) { $lines.Add($line) }
    }
    foreach ($key in $settings.Keys) {
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($key) + '\s*=')) {
                $lines[$i] = "$key=$($settings[$key])"
                $found = $true
                break
            }
        }
        if (-not $found) { $lines.Add("$key=$($settings[$key])") }
    }
    Set-Content -LiteralPath $configPath -Value $lines -Encoding ascii
}

function Refresh-DeviceList {
    $script:Catalog = Get-AvpCatalog
    $runningAvd = Get-RunningPhoneAvd
    $deviceList.BeginUpdate()
    $deviceList.Items.Clear()
    foreach ($device in @($script:Catalog.devices)) {
        $status = if ($device.internetVerified -and $device.smsVerified) { 'Internet + SMS verified' } else { 'Verify on first launch' }
        if ($runningAvd -eq $device.avdName) { $status = "Running - $status" }
        $item = [System.Windows.Forms.ListViewItem]::new([string]$device.name)
        [void]$item.SubItems.Add((Format-AvpPhoneNumber -Number ([string]$device.phoneNumber)))
        [void]$item.SubItems.Add([string]$device.carrierName)
        [void]$item.SubItems.Add([string]$status)
        $item.Tag = [string]$device.avdName
        [void]$deviceList.Items.Add($item)
    }
    if ($deviceList.Items.Count -gt 0) {
        $selected = $deviceList.Items | Where-Object { $_.Tag -eq $script:Catalog.activeAvdName } | Select-Object -First 1
        if ($selected) { $selected.Selected = $true }
        elseif ($deviceList.Items.Count -gt 0) { $deviceList.Items[0].Selected = $true }
    }
    $deviceList.EndUpdate()
    $deleteButton.Enabled = ($script:Catalog.devices.Count -gt 1)
}

function Get-SelectedDevice {
    if ($deviceList.SelectedItems.Count -eq 0) { return $null }
    return Get-AvpDevice -Catalog $script:Catalog -AvdName ([string]$deviceList.SelectedItems[0].Tag)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Android Virtual Phone - Choose a device'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(780, 470)
$form.MinimumSize = New-Object System.Drawing.Size(690, 420)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.TopMost = $true
$form.ShowInTaskbar = $true

$heading = New-Object System.Windows.Forms.Label
$heading.Text = 'Choose an Android phone'
$heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
$heading.AutoSize = $true
$heading.Location = New-Object System.Drawing.Point(22, 18)
$form.Controls.Add($heading)

$description = New-Object System.Windows.Forms.Label
$description.Text = 'AVP Test Mobile assigns fictional numbers and delivers test SMS locally. New devices keep separate apps and data.'
$description.AutoSize = $false
$description.Location = New-Object System.Drawing.Point(24, 57)
$description.Size = New-Object System.Drawing.Size(710, 40)
$form.Controls.Add($description)

$deviceList = New-Object System.Windows.Forms.ListView
$deviceList.View = [System.Windows.Forms.View]::Details
$deviceList.FullRowSelect = $true
$deviceList.HideSelection = $false
$deviceList.MultiSelect = $false
$deviceList.Location = New-Object System.Drawing.Point(24, 105)
$deviceList.Size = New-Object System.Drawing.Size(710, 235)
[void]$deviceList.Columns.Add('Device', 165)
[void]$deviceList.Columns.Add('U.S. demo number', 160)
[void]$deviceList.Columns.Add('Mock carrier', 150)
[void]$deviceList.Columns.Add('Status', 220)
$form.Controls.Add($deviceList)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = 'Launch'
$launchButton.Size = New-Object System.Drawing.Size(110, 38)
$launchButton.Location = New-Object System.Drawing.Point(24, 354)
$launchButton.DialogResult = [System.Windows.Forms.DialogResult]::None
$form.Controls.Add($launchButton)
$form.AcceptButton = $launchButton

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = 'Add device'
$addButton.Size = New-Object System.Drawing.Size(120, 38)
$addButton.Location = New-Object System.Drawing.Point(144, 354)
$form.Controls.Add($addButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = 'Delete device'
$deleteButton.Size = New-Object System.Drawing.Size(125, 38)
$deleteButton.Location = New-Object System.Drawing.Point(274, 354)
$form.Controls.Add($deleteButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh'
$refreshButton.Size = New-Object System.Drawing.Size(95, 38)
$refreshButton.Location = New-Object System.Drawing.Point(409, 354)
$form.Controls.Add($refreshButton)

$sendSmsButton = New-Object System.Windows.Forms.Button
$sendSmsButton.Text = 'Send test SMS'
$sendSmsButton.Size = New-Object System.Drawing.Size(120, 38)
$sendSmsButton.Location = New-Object System.Drawing.Point(514, 354)
$form.Controls.Add($sendSmsButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Size = New-Object System.Drawing.Size(95, 38)
$cancelButton.Location = New-Object System.Drawing.Point(639, 354)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

$note = New-Object System.Windows.Forms.Label
$note.Text = 'AVP Test Mobile uses fictional 202-555-01xx numbers. Test SMS is injected locally and never reaches carrier phones.'
$note.AutoSize = $false
$note.Location = New-Object System.Drawing.Point(24, 405)
$note.Size = New-Object System.Drawing.Size(710, 25)
$note.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($note)

$launchButton.Add_Click({
    try {
        $device = Get-SelectedDevice
        if (-not $device) { return }
        $runningAvd = Get-RunningPhoneAvd
        if ($runningAvd -and $runningAvd -ne $device.avdName) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                "Save and close '$runningAvd', then open '$($device.name)'?",
                'Switch Android device',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        Start-SelectedPhone -Device $device
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not launch phone', 'OK', 'Error') | Out-Null
    }
})

$deviceList.Add_DoubleClick({ $launchButton.PerformClick() })

$addButton.Add_Click({
    try {
        $displayName = [Microsoft.VisualBasic.Interaction]::InputBox(
            'Enter a name for this Android device:',
            'Add Android device',
            'My Android Phone'
        ).Trim()
        if (-not $displayName) { return }
        if ($displayName.Length -gt 40) { throw 'Device names must be 40 characters or fewer.' }

        $catalog = Get-AvpCatalog
        $slug = ($displayName -replace '[^A-Za-z0-9]+', '_').Trim('_')
        if (-not $slug) { $slug = 'Phone' }
        if ($slug.Length -gt 22) { $slug = $slug.Substring(0, 22) }
        $avdName = "Phone_$slug"
        while ((Get-AvpDevice -Catalog $catalog -AvdName $avdName) -or (Test-Path -LiteralPath (Join-Path $script:AvpAvdRegistryHome "$avdName.ini"))) {
            $avdName = "Phone_${slug}_$(Get-Random -Minimum 1000 -Maximum 9999)"
        }

        New-Item -ItemType Directory -Path $script:AvpManagedAvdRoot -Force | Out-Null
        $avdPath = Join-Path $script:AvpManagedAvdRoot "$avdName.avd"
        if (Test-Path -LiteralPath $avdPath) { throw "The device folder already exists: $avdPath" }

        $form.UseWaitCursor = $true
        $description.Text = "Creating '$displayName' from the Google Play Android image..."
        [System.Windows.Forms.Application]::DoEvents()
        $createOutput = & $avdManager -s create avd -n $avdName -k $systemImage -d pixel_8 -p $avdPath 2>&1
        if ($LASTEXITCODE -ne 0) { throw (($createOutput | ForEach-Object { $_.ToString() }) -join "`n") }
        Set-NewAvdDefaults -AvdPath $avdPath
        Set-AvpAvdIndexEntry -AvdName $avdName -AvdPath $avdPath

        $newDevice = [pscustomobject]@{
            name = $displayName
            avdName = $avdName
            avdPath = $avdPath
            phoneNumber = Get-AvpNewDemoNumber -Catalog $catalog
            carrierName = $script:AvpCarrierName
            region = 'US'
            locale = 'en-US'
            timeZone = 'America/Chicago'
            internetVerified = $false
            smsVerified = $false
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
            lastVerifiedAtUtc = $null
        }
        $catalog.devices = @($catalog.devices) + @($newDevice)
        Save-AvpCatalog -Catalog $catalog
        $script:Catalog = $catalog
        Refresh-DeviceList

        $choice = [System.Windows.Forms.MessageBox]::Show(
            "'$displayName' was added with $(Format-AvpPhoneNumber -Number $newDevice.phoneNumber). Launch it now to verify internet and simulated SMS? First startup can take several minutes on removable drives.",
            'Device added',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) { Start-SelectedPhone -Device $newDevice }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not add device', 'OK', 'Error') | Out-Null
    } finally {
        $form.UseWaitCursor = $false
        $description.Text = 'AVP Test Mobile assigns fictional numbers and delivers test SMS locally. New devices keep separate apps and data.'
    }
})

$sendSmsButton.Add_Click({
    try {
        $device = Get-SelectedDevice
        if (-not $device) { return }
        $runningAvd = Get-RunningPhoneAvd
        if ($runningAvd -ne $device.avdName) {
            [System.Windows.Forms.MessageBox]::Show(
                "Launch '$($device.name)' first, then choose Send test SMS again.",
                'AVP Test Mobile',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $message = [Microsoft.VisualBasic.Interaction]::InputBox(
            "AVP Test Mobile can inject a local-only SMS to $($device.name) ($(Format-AvpPhoneNumber -Number ([string]$device.phoneNumber))). This does not use a cellular network:",
            'AVP Test Mobile',
            'Test message from AVP Test Mobile'
        ).Trim()
        if (-not $message) { return }
        if ($message.Length -gt 160) { throw 'Test SMS messages must be 160 characters or fewer.' }

        $sendResult = & $adbPath -s 'emulator-5566' emu sms send $script:AvpCarrierSmsSenderNumber $message 2>&1
        if ($LASTEXITCODE -ne 0) { throw (($sendResult | ForEach-Object { $_.ToString() }) -join "`n") }
        [System.Windows.Forms.MessageBox]::Show(
            "AVP Test Mobile delivered a simulated SMS from $(Format-AvpPhoneNumber -Number $script:AvpCarrierSmsSenderNumber). It stayed inside the emulator.",
            'AVP Test Mobile',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AVP Test Mobile', 'OK', 'Error') | Out-Null
    }
})

$deleteButton.Add_Click({
    try {
        $device = Get-SelectedDevice
        if (-not $device) { return }
        $catalog = Get-AvpCatalog
        if ($catalog.devices.Count -le 1) {
            [System.Windows.Forms.MessageBox]::Show('Keep at least one Android device in the list.', 'Delete device', 'OK', 'Information') | Out-Null
            return
        }

        $choice = [System.Windows.Forms.MessageBox]::Show(
            "Delete '$($device.name)' ($(Format-AvpPhoneNumber -Number ([string]$device.phoneNumber))) and permanently remove its apps, accounts, and messages?",
            'Delete Android device',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $runningAvd = Get-RunningPhoneAvd
        if ($runningAvd -eq $device.avdName) {
            $adbEndpoint = '127.0.0.1:5567'
            & $adbPath connect $adbEndpoint 2>$null | Out-Null
            & $adbPath -s 'emulator-5566' emu kill 2>$null | Out-Null
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 500
                $stillRunning = Get-RunningPhoneAvd
            } while ($stillRunning -eq $device.avdName -and [DateTime]::UtcNow -lt $deadline)
            if ($stillRunning -eq $device.avdName) { throw 'The running phone did not shut down. Close it and try deleting again.' }
        }

        $avdPath = [System.IO.Path]::GetFullPath([string]$device.avdPath).TrimEnd('\')
        $allowedRoots = @(
            [System.IO.Path]::GetFullPath($script:AvpManagedAvdRoot).TrimEnd('\'),
            [System.IO.Path]::GetFullPath((Join-Path $script:AvpCatalogRoot 'avd')).TrimEnd('\')
        )
        $allowed = $false
        foreach ($allowedRoot in $allowedRoots) {
            if ($avdPath.StartsWith($allowedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $allowed = $true }
        }
        if (-not $allowed) { throw "Refusing to remove a device outside the Android Virtual Phone storage folders: $avdPath" }

        if (Test-Path -LiteralPath $avdPath) { Remove-Item -LiteralPath $avdPath -Recurse -Force }
        $iniPath = Join-Path $script:AvpAvdRegistryHome "$($device.avdName).ini"
        if (Test-Path -LiteralPath $iniPath) { Remove-Item -LiteralPath $iniPath -Force }
        $catalog.devices = @($catalog.devices | Where-Object { $_.avdName -ne $device.avdName })
        if ($catalog.activeAvdName -eq $device.avdName) { $catalog.activeAvdName = [string]$catalog.devices[0].avdName }
        Save-AvpCatalog -Catalog $catalog
        $script:Catalog = $catalog
        Refresh-DeviceList
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not delete device', 'OK', 'Error') | Out-Null
    }
})

$refreshButton.Add_Click({
    try { Refresh-DeviceList } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not refresh device list', 'OK', 'Error') | Out-Null }
})

try {
    $script:Catalog = Get-AvpCatalog
    Refresh-DeviceList
    [void]$form.ShowDialog()
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Android Virtual Phone', 'OK', 'Error') | Out-Null
}
