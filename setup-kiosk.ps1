# ============================================================================
# Logic Interactive - Kiosk/Installation PC Setup Script
# Run:  irm https://raw.githubusercontent.com/YOUR_REPO/main/setup-kiosk.ps1 | iex
# ============================================================================

# --- Self-elevate to admin if needed ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host "Requesting admin privileges..." -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/YOUR_REPO/main/setup-kiosk.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -c `"irm $scriptUrl | iex`""
    exit
}

$ErrorActionPreference = "SilentlyContinue"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   WARN: $msg" -ForegroundColor Yellow }

function Set-Reg($path, $name, $value, $type = "DWord")
{
    if (-not (Test-Path "Registry::$path"))
    {
        New-Item -Path "Registry::$path" -Force | Out-Null
    }
    Set-ItemProperty -Path "Registry::$path" -Name $name -Value $value -Type $type -Force
    Write-Ok "$path\$name = $value"
}

# ============================================================================
Write-Step "SMART APP CONTROL - Disable"
# ============================================================================
# State: 0=Off, 1=Evaluation, 2=On
Set-Reg "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState" 0

# ============================================================================
Write-Step "WINDOWS UPDATE - Disable auto-update and nag screens"
# ============================================================================
$wu = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$au = "$wu\AU"

# Disable auto-update entirely
Set-Reg $au "NoAutoUpdate" 1
# If updates are downloaded, never auto-restart
Set-Reg $au "NoAutoRebootWithLoggedOnUsers" 1
# Defer feature updates 365 days
Set-Reg $wu "DeferFeatureUpdates" 1
Set-Reg $wu "DeferFeatureUpdatesPeriodInDays" 365
# Defer quality updates 30 days
Set-Reg $wu "DeferQualityUpdates" 1
Set-Reg $wu "DeferQualityUpdatesPeriodInDays" 30
# Disable the full-screen "restart required" nag
Set-Reg $wu "SetAutoRestartNotificationDisable" 1
# Disable Windows Update active hours override
Set-Reg $au "AUOptions" 2  # Notify before download
# Disable delivery optimization (P2P update sharing)
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
# Disable update orchestrator scheduled tasks
$tasks = @(
    "\Microsoft\Windows\WindowsUpdate\Scheduled Start"
    "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"
    "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker"
    "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC"
    "\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery"
)
foreach ($t in $tasks)
{
    schtasks /Change /TN $t /Disable 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Disabled task: $t" }
}
# Stop and disable Windows Update service
Stop-Service -Name wuauserv -Force 2>$null
Set-Service -Name wuauserv -StartupType Disabled 2>$null
Write-Ok "Windows Update service disabled"

# ============================================================================
Write-Step "SETUP / FINISH NAG SCREENS - Disable"
# ============================================================================
$cdm = "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"

# "Let's finish setting up your device"
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
# "Welcome experience" after updates
Set-Reg $cdm "SubscribedContent-310091Enabled" 0
# OOBE nag on new user
Set-Reg "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" "DisablePrivacyExperience" 1
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" "DisablePrivacyExperience" 1

# ============================================================================
Write-Step "COPILOT / AI / RECALL - Disable"
# ============================================================================
Set-Reg "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
# Copilot button in taskbar
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0

# ============================================================================
Write-Step "WIDGETS - Disable"
# ============================================================================
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
# Kill widgets process
Stop-Process -Name "Widgets" -Force 2>$null

# ============================================================================
Write-Step "SEARCH / TASKBAR - Clean up"
# ============================================================================
# Disable web search in Start
Set-Reg "HKCU\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
# Hide search box on taskbar (0=hidden, 1=icon, 2=box)
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0
# Hide Task View button
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0
# Hide Chat/Teams icon
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" 0

# ============================================================================
Write-Step "START MENU ADS / SUGGESTIONS - Disable"
# ============================================================================
Set-Reg $cdm "SubscribedContent-338389Enabled" 0
Set-Reg $cdm "SubscribedContent-310093Enabled" 0
Set-Reg $cdm "SubscribedContent-338393Enabled" 0
Set-Reg $cdm "SilentInstalledAppsEnabled" 0
Set-Reg $cdm "SystemPaneSuggestionsEnabled" 0
Set-Reg $cdm "SoftLandingEnabled" 0
Set-Reg $cdm "RotatingLockScreenOverlayEnabled" 0
Set-Reg $cdm "ContentDeliveryAllowed" 0
Set-Reg $cdm "PreInstalledAppsEnabled" 0
Set-Reg $cdm "OemPreInstalledAppsEnabled" 0
Set-Reg $cdm "PreInstalledAppsEverEnabled" 0
Set-Reg $cdm "FeatureManagementEnabled" 0

# ============================================================================
Write-Step "TELEMETRY / FEEDBACK - Disable"
# ============================================================================
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
Set-Reg "HKCU\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
# Disable diagnostics services
foreach ($svc in @("DiagTrack", "dmwappushservice"))
{
    Stop-Service -Name $svc -Force 2>$null
    Set-Service -Name $svc -StartupType Disabled 2>$null
    Write-Ok "Disabled service: $svc"
}

# ============================================================================
Write-Step "NOTIFICATIONS - Minimize"
# ============================================================================
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" "ToastEnabled" 0
Set-Reg "HKCU\Software\Policies\Microsoft\Windows\Explorer" "DisableNotificationCenter" 1
# Disable tips/tricks notifications
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 0

# ============================================================================
Write-Step "POWER - Max performance, no sleep, no screen timeout"
# ============================================================================
# Activate high performance power plan
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
Write-Ok "Activated High Performance power plan"
# Create ultimate performance plan (available on desktop SKUs)
powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
if ($LASTEXITCODE -eq 0)
{
    Write-Ok "Created Ultimate Performance plan"
}
# Never sleep on AC
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
Write-Ok "Sleep timeout: never"
# Never hibernate
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /hibernate off
Write-Ok "Hibernate: off"
# Never turn off display
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
Write-Ok "Display timeout: never"
# Disable USB selective suspend
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setactive SCHEME_CURRENT
Write-Ok "USB selective suspend: disabled"

# ============================================================================
Write-Step "SCREENSAVER - Disable"
# ============================================================================
Set-Reg "HKCU\Control Panel\Desktop" "ScreenSaveActive" "0" "String"
Set-Reg "HKCU\Control Panel\Desktop" "ScreenSaverIsSecure" "0" "String"
Set-Reg "HKCU\Control Panel\Desktop" "ScreenSaveTimeOut" "0" "String"
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaveActive" "0" "String"

# ============================================================================
Write-Step "LOCK SCREEN - Disable (go straight to desktop)"
# ============================================================================
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" 1

# ============================================================================
Write-Step "VISUAL PERFORMANCE - Set to best performance"
# ============================================================================
# 0=Custom, 1=LetWindowsDecide, 2=BestPerformance, 3=BestAppearance
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
# Disable animations
Set-Reg "HKCU\Control Panel\Desktop" "UserPreferencesMask" ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) "Binary"
Set-Reg "HKCU\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
# Disable transparency
Set-Reg "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
# GPU scheduling (keep on for rendering perf)
Set-Reg "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2

# ============================================================================
Write-Step "AUTO-LOGON - Configure (optional, edit values below)"
# ============================================================================
$autoLogon = $false  # <-- Set to $true and fill in credentials
$autoUser  = "Kiosk"
$autoPwd   = ""
if ($autoLogon)
{
    $al = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-Reg $al "AutoAdminLogon" "1" "String"
    Set-Reg $al "DefaultUserName" $autoUser "String"
    Set-Reg $al "DefaultPassword" $autoPwd "String"
    Write-Ok "Auto-logon configured for: $autoUser"
}

# ============================================================================
Write-Step "MISC KIOSK TWEAKS"
# ============================================================================
# Disable Cortana
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
# Disable first logon animation
Set-Reg "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableFirstLogonAnimation" 0
# Disable action center
Set-Reg "HKCU\Software\Policies\Microsoft\Windows\Explorer" "DisableNotificationCenter" 1
# Disable Game Bar / Game DVR
Set-Reg "HKCU\Software\Microsoft\GameBar" "AllowAutoGameMode" 0
Set-Reg "HKCU\System\GameConfigStore" "GameDVR_Enabled" 0
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
# Disable sticky keys prompt
Set-Reg "HKCU\Control Panel\Accessibility\StickyKeys" "Flags" "506" "String"
# Disable filter keys prompt
Set-Reg "HKCU\Control Panel\Accessibility\Keyboard Response" "Flags" "122" "String"
# Disable toggle keys prompt
Set-Reg "HKCU\Control Panel\Accessibility\ToggleKeys" "Flags" "58" "String"
# Disable Windows Error Reporting
Set-Reg "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
# Set time zone (adjust as needed)
# tzutil /s "W. Europe Standard Time"
# Write-Ok "Timezone set to W. Europe Standard Time"

# ============================================================================
Write-Step "FIREWALL - Allow HashLink (optional)"
# ============================================================================
$hlPath = "C:\Program Files\HashLink\hl.exe"
if (Test-Path $hlPath)
{
    netsh advfirewall firewall add rule name="HashLink" dir=in action=allow program="$hlPath" enable=yes 2>$null
    Write-Ok "Firewall rule added for HashLink"
}

# ============================================================================
Write-Step "RESTART EXPLORER to apply taskbar changes"
# ============================================================================
Stop-Process -Name explorer -Force 2>$null
Start-Sleep -Seconds 2
Start-Process explorer
Write-Ok "Explorer restarted"

# ============================================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Setup complete! Reboot recommended." -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
