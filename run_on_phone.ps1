# Run Chasham AI on your Android phone.
#
# BEFORE RUNNING:
# 1. Connect phone via USB.
# 2. On phone: Settings > Developer options > USB debugging ON.
# 3. When prompted on phone, tap "Allow" for USB debugging (remember this computer).
# 4. Unlock the phone. Pull down notification and set USB to "File transfer" or "MTP" (not "Charging only").
# 5. Run: .\run_on_phone.ps1
#
# If your phone still doesn't appear, try another USB cable/port or install USB drivers for your phone.

$env:Path = "D:\FYP\platform-tools;" + $env:Path
Set-Location $PSScriptRoot

Write-Host "Checking connected devices..." -ForegroundColor Cyan
flutter devices

$list = flutter devices 2>&1 | Out-String
if ($list -match "android") {
    Write-Host "`nRunning app on Android device..." -ForegroundColor Green
    flutter run -d android --device-timeout=60
} else {
    Write-Host "`nNo Android device found. Check USB cable, USB mode (File transfer), and Allow USB debugging on phone." -ForegroundColor Yellow
    Write-Host "Then run this script again." -ForegroundColor Yellow
}
