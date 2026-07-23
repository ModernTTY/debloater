#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows tweaks script derived from WinUtil config.
    Run as Administrator in PowerShell.

    Self-resuming across reboots: run this script once with no arguments
    and it runs Stage 1, schedules Stage 2 to fire automatically at next
    logon (via Task Scheduler), reboots, Stage 2 runs, schedules Stage 3,
    reboots, Stage 3 runs and cleans everything up. No manual re-running.
#>

param(
    [ValidateSet(1, 2, 3)]
    [int]$Stage = 1
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# ─── SELF-RESUME PLUMBING ─────────────────────────────────────────────────────
# Persistent copy location so the scheduled task always has a stable file to
# invoke, regardless of where the script was originally launched from.
$Script:TaskName    = "DebloaterResume"
$Script:PersistDir  = Join-Path $Env:ProgramData "Debloater"
$Script:PersistPath = Join-Path $Script:PersistDir "debloater.ps1"

function Initialize-PersistentCopy {
    if (-not (Test-Path $Script:PersistDir)) {
        New-Item -Path $Script:PersistDir -ItemType Directory -Force | Out-Null
    }

    $currentPath = $PSCommandPath
    if (-not $currentPath) { $currentPath = $MyInvocation.PSCommandPath }

    if (-not $currentPath) {
        Write-Host "WARNING: Can't determine this script's own file path (likely running via 'irm | iex')." -ForegroundColor Yellow
        Write-Host "Auto-resume needs a real .ps1 file on disk. Save the script and run it with '.\debloater.ps1' instead." -ForegroundColor Yellow
        return
    }

    if ($currentPath -ne $Script:PersistPath) {
        Copy-Item -Path $currentPath -Destination $Script:PersistPath -Force
    }
}

function Register-ResumeTask {
    param([Parameter(Mandatory)][int]$NextStage)

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script:PersistPath`" -Stage $NextStage"

    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $Script:TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-Host "Scheduled task registered: Stage $NextStage will run automatically at next logon." -ForegroundColor DarkGray
}

function Remove-ResumeTask {
    Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Invoke-Reboot {
    param(
        [string]$Message,
        [int]$DelaySeconds = 15
    )

    Write-Host ""
    Write-Host "REBOOTING IN $DelaySeconds SECONDS" -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
    Write-Host "Run 'shutdown /a' in another window to cancel the reboot." -ForegroundColor DarkGray

    shutdown.exe /r /t $DelaySeconds /c "$Message"
    exit
}

function Write-Step {

    param([string]$Title)

    $line = "-------------------------------------------------------------"

    Write-Host ""

    Write-Host $line -ForegroundColor DarkGray

    Write-Host "  $Title" -ForegroundColor Cyan

    Write-Host $line -ForegroundColor DarkGray

    Write-Host ""

}
function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

Clear-Host

function Invoke-Stage1 {
    Write-Host "`n=== STAGE 1 ===" -ForegroundColor Cyan

    Remove-ResumeTask
    Initialize-PersistentCopy

    # UCPD disable stuff here
    Write-Step "UCPD DISBALE"
    Disable-ScheduledTask "UCPD velocity" "\Microsoft\Windows\AppxDeploymentClient\"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\UCPD" -Name "Start" -Value 4 -Type DWord -Force

    Register-ResumeTask -NextStage 2
    Invoke-Reboot "Debloater: Stage 1 done, rebooting into Stage 2 automatically..."
}

function Invoke-Stage2 {
    Write-Host "`n=== STAGE 2 ===" -ForegroundColor Cyan

    Remove-ResumeTask

    Write-Step "REGION CONFIGURATION"
    $Region = Read-Host "Enter 2-letter country code (BE, LV, US, GB, SK, EE, FI, etc.)"

    try {
        $geoId = ([System.Globalization.RegionInfo]::new($Region)).GeoId

        Set-WinHomeLocation -GeoId $geoId

        Set-ItemProperty `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion" `
            -Name "DeviceRegion" `
            -Value $geoId `
            -Type DWord `
            -Force

        Write-Host "Country/Region set to $Region"
        Write-Host "Device Setup Region will regenerate after reboot."
    }
    catch {
        Write-Host "Invalid country code."
    }

    Write-Step "SMARTSCREEN / SMART APP CONTROL DISBALE"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -Type DWord -Value 0
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null; Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Type DWord -Value 0

    Register-ResumeTask -NextStage 3
    Invoke-Reboot "Debloater: Stage 2 done, rebooting into Stage 3 automatically..."
}

function Invoke-Stage3 {

    Remove-ResumeTask

    # ─── ACTIVITY HISTORY ────────────────────────────────────────────────────────
    Write-Step "DISBALE ACTIVITY HISTORY"
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed"    0 DWord
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0 DWord
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities"  0 DWord

    # ─── TELEMETRY ────────────────────────────────────────────────────────────────
    Write-Step "DISBALE TELEMETRY"
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"                    "Enabled"                                   0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"                            "TailoredExperiencesWithDiagnosticDataEnabled" 0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"               "HasAccepted"                               0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Input\TIPC"                                                "Enabled"                                   0 DWord
    Set-Reg "HKCU:\Software\Microsoft\InputPersonalization"                                      "RestrictImplicitInkCollection"             1 DWord
    Set-Reg "HKCU:\Software\Microsoft\InputPersonalization"                                      "RestrictImplicitTextCollection"            1 DWord
    Set-Reg "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"                     "HarvestContacts"                           0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Personalization\Settings"                                  "AcceptedPrivacyPolicy"                     0 DWord
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"            "AllowTelemetry"                            0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"                  "Start_TrackProgs"                          0 DWord
    Set-Reg "HKCU:\Software\Microsoft\Siuf\Rules"                                                "NumberOfSIUFInPeriod"                      0 DWord

    Set-MpPreference -SubmitSamplesConsent 2
    Set-Service -Name diagtrack -StartupType Disabled
    Set-Service -Name wermgr    -StartupType Disabled
    [Environment]::SetEnvironmentVariable("POWERSHELL_TELEMETRY_OPTOUT", "1", "Machine")
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name PeriodInNanoSeconds -ErrorAction SilentlyContinue

    # ─── LOCATION TRACKING ────────────────────────────────────────────────────────
    Write-Step "DISABLE LOCATION TRACKING"
    Set-Service -Name lfsvc -StartupType Disabled -ErrorAction SilentlyContinue
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value"                 "Deny" String
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" "SensorPermissionState" 0 DWord
    Set-Reg "HKLM:\SYSTEM\Maps" "AutoUpdateEnabled" 0 DWord

    # ─── DELIVERY OPTIMIZATION ───────────────────────────────────────────────────
    Write-Step "DISABLE P2P UPDATES"
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0 DWord

    # ─── CONSUMER FEATURES ───────────────────────────────────────────────────────
    Write-Step "DISABLE AUTO-INSTALL MS-STORE APPS"
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1 DWord
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force | Out-Null; New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1 -PropertyType DWord -Force
    # ─── WPBT (vendor boot-time execution) ───────────────────────────────────────
    Write-Step "DISABLE WBPT"
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution" 1 DWord

    Write-Step "DISABLE BITLOCKER"
    if ((Get-BitLockerVolume -MountPoint $Env:SystemDrive -ErrorAction SilentlyContinue).ProtectionStatus -ne "Off") {
        Disable-BitLocker -MountPoint $Env:SystemDrive -ErrorAction SilentlyContinue
    }

    # ─── SERVICES → MANUAL / DISABLED ────────────────────────────────────────────
    Write-Step "DISBALE SERVICE AUTO-STARTUP"
    $services = @(
        @{ Name = "CscService";    Type = "Disabled" },   # Offline Files
        @{ Name = "DiagTrack";     Type = "Disabled" },   # Connected User Experiences & Telemetry
        @{ Name = "MapsBroker";    Type = "Manual"   },   # Downloaded Maps Manager
        @{ Name = "StorSvc";       Type = "Manual"   },   # Storage Service
        @{ Name = "SharedAccess";  Type = "Disabled" }    # ICS
    )
    foreach ($svc in $services) {
        Set-Service -Name $svc.Name -StartupType $svc.Type -ErrorAction SilentlyContinue
    }

    Write-Step "OPTIMIZE SVCHOST AMOUNT"
    $ramKB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name SvcHostSplitThresholdInKB -Value $ramKB

    # ─── TASKBAR: END TASK ON RIGHT-CLICK ────────────────────────────────────────
    Write-Step "ENABLE END-TASK ON TASKBAR"
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1 DWord

    # ─── FILE EXPLORER PREFERENCES ───────────────────────────────────────────────
    Write-Step "CONFIGURE FILE EXPLORER"
    # Show file extensions
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0 DWord
    # Show hidden files
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1 DWord
    # Show protected OS files (system-hidden)
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSuperHidden" 1 DWord
    # Default to This PC (not Home)
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1 DWord
    # Remove Home/Gallery from nav pane
    Set-Reg "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" "System.IsPinnedToNameSpaceTree" 0 DWord

    # ─── TASKBAR CLUTTER ─────────────────────────────────────────────────────────
    Write-Step "CLEANING UP TASKBAR"
    # Hide Search box
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0 DWord
    # Disable Bing in Start search
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 DWord
    # Hide Task View button
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0 DWord
    # Hide Start Menu recommendations
    Set-Reg "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"     "HideRecommendedSection" 1 DWord
    Set-Reg "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education" "IsEducationEnvironment" 1 DWord
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"               "HideRecommendedSection" 1 DWord
    # Disable Microsoft Store search recommendations
    icacls "$Env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db" /deny Everyone:F 2>$null

    # ─── LONG PATH SUPPORT ────────────────────────────────────────────────────────
    Write-Step "ENABLE LONG-PATH SUPPORT"
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1 DWord

    # ─── TEMP FILES ───────────────────────────────────────────────────────────────
    Write-Step "REMOVING TEMP-FILES"
    Remove-Item -Path "$Env:Temp\*"            -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    # ─── APPX BLOATWARE REMOVAL ──────────────────────────────────────────────────
    Write-Step "REMOVING PRE-INSTALLED BLOAT APPS"
    $bloat = @(
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.BingNews",
        "Microsoft.BingSearch",
        "Microsoft.BingWeather",
        "Clipchamp.Clipchamp",
        "Microsoft.Todos",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.Windows.DevHome",
        "Microsoft.Paint",
        "Microsoft.WindowsCamera",
        "Microsoft.OutlookForWindows",
        "Microsoft.WindowsAlarms",
        "Microsoft.StartExperiencesApp",
        "Microsoft.GetHelp",
        "Microsoft.ZuneMusic",
        "Microsoft.YourPhone",
        "MicrosoftCorporationII.QuickAssist",
        "MSTeams"
    )
    foreach ($pkg in $bloat) {
        Get-AppxPackage -AllUsers $pkg -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }

    # Teams classic leftovers
    $teamsPath = "$Env:LocalAppData\Microsoft\Teams\Update.exe"
    if (Test-Path $teamsPath) {
        Start-Process $teamsPath -ArgumentList "-uninstall" -Wait
        Remove-Item (Split-Path $teamsPath) -Recurse -Force -ErrorAction SilentlyContinue
    }

    Get-AppxPackage -AllUsers *crossdevice* | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*crossdevice*" | Remove-AppxProvisionedPackage -Online
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*yourphone*" | Remove-AppxProvisionedPackage -Online
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*windowscamera*" | Remove-AppxProvisionedPackage -Online
    Write-Step "REMOVE MICROSOFT STORE"
    do {
        $storeChoice = Read-Host "Do you wish to uninsatll the Microsoft Store`n  1) Yes`n  2) No`nChoice"
    } while ($storeChoice -notin "1","2")

    switch ($storeChoice) {
        "1" {
            Get-AppxPackage -AllUsers "Microsoft.WindowsStore" -ErrorAction SilentlyContinue |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

            Get-AppxPackage -AllUsers "Microsoft.StorePurchaseApp" -ErrorAction SilentlyContinue |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

            Get-AppxProvisionedPackage -Online |
                Where-Object DisplayName -like "*store*" |
                Remove-AppxProvisionedPackage -Online
        }

        "2" {
            Write-Host "OK MS Store will not be uninstalled"
        }

        default {
            Write-Host "Invalid"
        }
    }
        

    # ─── XBOX / GAME BAR ─────────────────────────────────────────────────────────
    Write-Step "REMOVE XBOX AND GAME BAR"
    Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 DWord
    $xboxPkgs = @(
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.GamingApp",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay"
    )
    foreach ($pkg in $xboxPkgs) {
        Get-AppxPackage -AllUsers $pkg -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }

    # ─── WINDOWS AI / COPILOT ────────────────────────────────────────────────────
    Write-Step "DISABLE WINDOWS AI / COPILOT"
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "hide:aicomponents" String
    Set-Reg "HKLM:\SOFTWARE\Policies\WindowsNotepad"                             "DisableAIFeatures"      1                  DWord

    $coreAI = (Get-AppxPackage MicrosoftWindows.Client.CoreAI -ErrorAction SilentlyContinue).PackageFullName
    if ($coreAI) {
        $sid = (Get-LocalUser $Env:UserName).Sid.Value
        New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$sid\$coreAI" -Force | Out-Null
        Remove-AppxPackage $coreAI -ErrorAction SilentlyContinue
    }
    Get-AppxPackage -AllUsers *Copilot*                    -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Set-Service -Name WSAIFabricSvc -StartupType Disabled -ErrorAction SilentlyContinue
    Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction SilentlyContinue

    # ─── WIDGETS ─────────────────────────────────────────────────────────────────
    Write-Step "REMOVING WIDGETS"
    Get-Process *Widget* -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-AppxPackage -AllUsers Microsoft.WidgetsPlatformRuntime    -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxPackage -AllUsers MicrosoftWindows.Client.WebExperience -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    # ─── MISC ────────────────────────────────────────────────────────────────────
    Write-Step "REMOVE ONEDRIVE"
    # Deny permission to remove OneDrive folder
    icacls $Env:OneDrive /deny "Administrators:(D,DC)" > $null 2>&1

    Write-Host "Uninstalling OneDrive..."
    Start-Process 'C:\Windows\System32\OneDriveSetup.exe' -ArgumentList '/uninstall' -Wait

    # Some of OneDrive files use explorer, and OneDrive uses FileCoAuth
    Write-Host "Removing leftover OneDrive Files..."

    Stop-Process -Name FileCoAuth,Explorer

    Remove-Item "$Env:LocalAppData\Microsoft\OneDrive" -Recurse -Force
    Remove-Item "C:\ProgramData\Microsoft OneDrive" -Recurse -Force

    # Grant back permission to access OneDrive folder
    icacls $Env:OneDrive /grant "Administrators:(D,DC)" > $null 2>&1

    if (-not (Get-ChildItem -Path $Env:OneDrive)) {
        Remove-Item -Path $Env:OneDrive -Recurse -Force
        [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')
    }

    # Disable OneSyncSvc
    Set-Service -Name OneSyncSvc -StartupType Disabled
    Write-Step "RUN O&O SHUTUP 10++"
    # O&O Shutup 10 ++

    try {
        $ProgressPreference = 'SilentlyContinue'

        Invoke-WebRequest -Uri https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe -OutFile "$Env:Temp\ooshutup10.exe"
        Start-Process -FilePath "$Env:Temp\ooshutup10.exe"

        $ProgressPreference = 'Continue'
    } catch {
        Write-Error "Couldn't download O&O ShutUp10. Please make sure you have an active internet connection."
    }

    Write-Step "ENABLE VERBOSE LOGON"

    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"                             "VerboseStatus"      1                  DWord
    Write-Step "DISABLE SETTINGS HOME PAGE"
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "hide:home" String
    Write-Step "ENABLE ULTIMATE PERFORMANCE PLAN"
    powercfg /setactive (powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value

    Write-Step "REMOVING MICROSOFT EDGE"
    

    $ErrorActionPreference = "Stop"
    $regView = [Microsoft.Win32.RegistryView]::Registry32
    $microsoft = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regView).
    OpenSubKey('SOFTWARE\Microsoft', $true)
    $edgeUWP = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
    $uninstallRegKey = $microsoft.OpenSubKey('Windows\CurrentVersion\Uninstall\Microsoft Edge')
    if ($null -eq $uninstallRegKey) {
        Write-Error "Edge is not installed!"
    }
    $uninstallString = $uninstallRegKey.GetValue('UninstallString') + ' --force-uninstall'
    $tempPath = "$env:SystemRoot\SystemTemp"
    if (-not (Test-Path -Path $tempPath) ) {
        $tempPath = New-Item "$env:SystemRoot\Temp\$([Guid]::NewGuid().Guid)" -ItemType Directory
    }
    $fakeDllhostPath = "$tempPath\dllhost.exe"
    $edgeClient = $microsoft.OpenSubKey('EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}', $true)
    if ($null -ne $edgeClient.GetValue('experiment_control_labels')) {
        $edgeClient.DeleteValue('experiment_control_labels')
    }
    $microsoft.CreateSubKey('EdgeUpdateDev').SetValue('AllowUninstall', '')
    Copy-Item "$env:SystemRoot\System32\cmd.exe" -Destination $fakeDllhostPath

    [void](New-Item $edgeUWP -ItemType Directory -ErrorVariable fail -ErrorAction SilentlyContinue)
    [void](New-Item "$edgeUWP\MicrosoftEdge.exe" -ErrorAction Continue)
    Start-Process $fakeDllhostPath "/c $uninstallString" -WindowStyle Hidden -Wait
    [void](Remove-Item "$edgeUWP\MicrosoftEdge.exe" -ErrorAction Continue)
    [void](Remove-Item $fakeDllhostPath -ErrorAction Continue)
    if (-not $fail) {
        [void](Remove-Item "$edgeUWP")
    }

    # ─── RESTART EXPLORER ────────────────────────────────────────────────────────
    Write-Step "RESTARTING EXPLORER"
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Start-Process explorer

    # ─── MAS ─────────────────────────────────────────────────────────────────────
    Write-Step "ACTIVATING WINDOWS"
    do {
        $choice = Read-Host "Do you wish to use MAS to activate Windows?`n  1) Yes`n  2) No`nChoice"
    } while ($choice -notin "1","2")

    switch ($choice) {
        "1" { irm https://get.activated.win | iex }
        "2" { Write-Host "OK MAS will not be run." }
        default { Write-Host "Invalid" }
    }

    # ─── THEME ─────────────────────────────────────────────────────────────────────
    Write-Step "SETTING THEME"
    do {
        $themeChoice = Read-Host "Choose theme:`n  1) Windows Light`n  2) Windows Dark`n  3) Leave current theme`nChoice"
    } while ($themeChoice -notin "1","2","3")

    switch ($themeChoice) {
        "1" {
            Start-Process "$env:windir\Resources\Themes\aero.theme"
        }

        "2" {
            Start-Process "$env:windir\Resources\Themes\dark.theme"
        }

        "3" {
            Write-Host "Theme unchanged."
        }
    }
    # ─── FIREFOX INSTALLER ───────────────────────────────────────────────────────
    Write-Step "INSTALL BROWSER"
    do {
        $browserChoice = Read-Host "Pick a browser:`n  1) Firefox Nightly`n  2) Firefox`n  3) No browser`nChoice"
    } while ($browserChoice -notin "1","2","3")

    if ($browserChoice -ne "3") {

        Write-Step "Preparing Firefox download"

        $isArm = (Get-CimInstance Win32_Processor).Architecture -eq 12

        switch ($browserChoice) {

            "1" {
                if ($isArm) {
                    $url = "https://download.mozilla.org/?product=firefox-nightly-latest-ssl&os=win64-aarch64&lang=en-US"
                }
                else {
                    $url = "https://download.mozilla.org/?product=firefox-nightly-latest-ssl&os=win64&lang=en-US"
                }

                $installerName = "FirefoxNightlySetup.exe"
            }

            "2" {
                if ($isArm) {
                    $url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64-aarch64&lang=en-US"
                }
                else {
                    $url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
                }

                $installerName = "FirefoxSetup.exe"
            }
        }

        $downloadPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads\$installerName"

        Write-Host "Downloading from $url"
        Invoke-WebRequest -Uri $url -OutFile $downloadPath

        if (Test-Path $downloadPath) {

            Write-Host "Running installer..."
            $proc = Start-Process -FilePath $downloadPath -PassThru

            try {
                $proc.WaitForExit()
            }
            catch {}

            Start-Sleep 3

            Write-Host "Removing installer..."
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue

            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }

    # ─── CLEANUP ─────────────────────────────────────────────────────────────────
    Remove-ResumeTask
    Remove-Item -Path $Script:PersistDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`nAll 3 stages complete. A reboot will now happen." -ForegroundColor Green
    Invoke-Reboot "Debloater: Stage 3 done, rebooting into your new debloated system automatically..."
}

Write-Host ""
Write-Host "Windows Debloat Script" -ForegroundColor Cyan
Write-Host "Stage $Stage of 3" -ForegroundColor DarkGray
Write-Host ""

switch ($Stage) {
    1 { Invoke-Stage1 }
    2 { Invoke-Stage2 }
    3 { Invoke-Stage3 }
}