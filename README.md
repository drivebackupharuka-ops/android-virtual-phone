# Android Virtual Phone

Launch **Android Virtual Phone** from the Windows Start menu or desktop to open the device picker. Select a phone, add a separate Google Play device, or delete an old profile. Added phones get their own apps and data; their first launch checks internet and simulated SMS before the menu marks them verified. Press **Alt+Enter** in the emulator to toggle fullscreen.

Sign in to Google Play to download apps. Gmail is available for creating or signing into an email account. Android Wi-Fi is enabled; its internet connection is provided through Windows.

Run `powershell -ExecutionPolicy Bypass -File .\test-phone.ps1` from this folder to check boot, region, Wi-Fi and internet, installed apps, app launches, and simulated SMS delivery.

If Quick Boot opens to a black or crashed screen, close the emulator and run `powershell -ExecutionPolicy Bypass -File .\launch-phone.ps1 -ColdBoot` once. This bypasses the saved RAM snapshot while retaining the phone's apps and data.

## U.S. region and SMS

Each phone uses the U.S. English system image, Central time, and a Chicago GPS location. The mock carrier **AVP Test Mobile** assigns each device a unique fictional number from **+1 202-555-0100–0199** (the original phone is **+1 202-555-0147**). The menu displays the carrier name and number for each device. These are reserved fictional-use numbers, not active phone lines.

SMS works as an emulator simulation. AVP Test Mobile injects incoming test messages from **+1 202-555-0138** using Android Emulator's local SMS command. Use **Send test SMS** in the device picker or open **Send Test SMS to Android Virtual Phone** from Start. Messages sent to or from this emulator do not reach real mobile phones, receive carrier traffic, or verify external accounts. A real, reachable number requires activation with a carrier or virtual-number provider.

## Notes

- This is a real Android virtual device with Google Play, not a web mockup. A new device's first Android boot may take a few minutes.
- Some apps that require a physical device or carrier may decline to run in an emulator.
- The original device data is stored in `%LOCALAPPDATA%\AndroidVirtualPhone\avd`; additional profiles are stored under `.local\managed-devices`. The AVD list and per-device number/verification state are in `%LOCALAPPDATA%\AndroidVirtualPhone`.
- The Android SDK and support files remain under `.local` in this project.

## GitHub source snapshot

This repository contains the Windows launcher scripts, documentation, and the current phone screenshot. The local `.local` and `.setup` folders are intentionally excluded: they hold the Android SDK/JDK, emulator system images and device data, logs, and downloaded installer archives. Those are large and tied to this Windows installation. Cloning this repository alone will not recreate the existing emulator; a local Android SDK/JDK and AVD must be provisioned under `.local` before launch.
