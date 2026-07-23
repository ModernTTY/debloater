# Windows Debloater

A Windows 10/11 PowerShell script that applies privacy, services, user-interface, and app-removal tweaks with minimal interaction. It must be run as Administrator.

## How to start

Open **Windows PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/ModernTTY/debloater/refs/heads/main/bootstrap.ps1 | iex
```

The bootstrap script downloads `debloater.ps1` to `%ProgramData%\Debloater` and starts Stage 1 from a real file. This allows the automatic resume mechanism to continue through the remaining stages after each reboot.

Requirements:

- Windows PowerShell with Administrator privileges.
- Internet access for the bootstrap download, O&O ShutUp10++, optional MAS, and optional Firefox installation.
- A user session that can log on again after each reboot.

The bootstrap command uses PowerShell's `irm` alias for `Invoke-RestMethod` and `iex` for `Invoke-Expression`. It downloads the loader from this repository, which then downloads the main script into `%ProgramData%\Debloater` before starting it.

## What it changes

The script runs in three stages:

<details>
<summary>Stage 1 — UCPD and reboot setup</summary>

- Disables the `UCPD velocity` scheduled task, when present.
- Sets the Windows `UCPD` service startup value to disabled.
- Saves a copy of the script in `%ProgramData%\Debloater`.
- Registers a temporary `DebloaterResume` scheduled task and reboots after 15 seconds.

</details>

<details>
<summary>Stage 2 — region and SmartScreen settings</summary>

- Prompts for a two-letter country code and changes the Windows home/device region when the code is valid.
- Disables Smart App Control / SmartScreen policy values.
- Registers Stage 3 to run at the next logon and reboots after 15 seconds.

</details>

<details>
<summary>Stage 3 — debloat and system tweaks</summary>

Stage 3 applies the main changes. Depending on the Windows edition and what is installed, some commands may have no effect.

- Disables Windows Activity History, advertising ID, tailored experiences, online speech/input personalization collection, telemetry settings, diagnostic tracking, Windows Error Reporting, location services, and map updates.
- Disables peer-to-peer Windows Update delivery optimization.
- Prevents automatic installation of some Microsoft consumer apps and device metadata.
- Disables WPBT vendor boot-time execution.
- If BitLocker protection is currently on, calls `Disable-BitLocker` on the system drive, which starts decrypting that drive.
- Changes several services to Manual or Disabled, including Offline Files, Maps Broker, Storage Service, Internet Connection Sharing, and OneSync.
- Adjusts the service-host split threshold based on installed RAM.
- Enables ending a task by right-clicking its taskbar button.
- Configures File Explorer to show file extensions, hidden files, and protected operating-system files; opens Explorer to This PC and hides Home/Gallery where supported.
- Hides taskbar Search and Task View, disables Bing search, and hides Start recommendations.
- Denies access to the Microsoft Store search database to suppress Store recommendations.
- Enables Windows long-path support and removes temporary files from the user and Windows temp folders.
- Removes a list of preinstalled AppX packages, including Feedback Hub, Bing apps, Clipchamp, To Do, Power Automate, Solitaire, Sound Recorder, Sticky Notes, Dev Home, Paint, Camera, Outlook for Windows, Alarms, Get Help, Groove Music, Phone Link, Quick Assist, and Teams where found.
- Removes additional cross-device, Phone Link, and Camera provisioned packages where found.
- Optionally removes the Microsoft Store and Store Purchase App.
- Removes Xbox/Gaming App components and disables Game DVR capture.
- Disables or removes Windows AI/Copilot components, Notepad AI features, Recall, and related services where available.
- Removes Widgets components and stops running Widget processes.
- Uninstalls OneDrive, removes leftover files, and disables OneSync.
- Downloads and launches O&O ShutUp10++.
- Enables verbose logon status messages and hides the Settings home page.
- Creates and activates the Ultimate Performance power plan.
- Attempts to force-uninstall Microsoft Edge.
- Restarts Windows Explorer after the UI changes.
- Optionally downloads and runs Microsoft Activation Scripts (MAS).
- Optionally changes the Windows theme.
- Optionally downloads and installs Firefox or Firefox Nightly.
- Deletes the temporary persistent copy and resume task when finished, then reboots once more.


</details>

## Execution flow

The normal run follows this sequence:

1. The loader checks for Administrator privileges and requests elevation through UAC when needed.
2. The loader creates `%ProgramData%\Debloater` and stores the main script there.
3. Stage 1 applies the UCPD changes and registers `DebloaterResume` for Stage 2.
4. Stage 2 collects the region code, applies region and SmartScreen-related settings, and registers Stage 3.
5. Stage 3 applies the remaining registry, service, AppX, Explorer, power, and application changes.
6. The script removes its scheduled task and temporary `%ProgramData%\Debloater` copy after Stage 3.

The stages are selected by the `-Stage` parameter. The valid values are `1`, `2`, and `3`; the default is `1`.

## Prompt reference

| Stage | Prompt | Choices | Result |
| --- | --- | --- | --- |
| 2 | Country/region | Two-letter code such as `BE`, `LV`, `US`, or `GB` | Sets the Windows home location and device region when the code is valid |
| 3 | Microsoft Store | `1` uninstall, `2` keep | Removes Store packages and provisioned Store packages when `1` is selected |
| 3 | MAS activation | `1` run, `2` skip | Downloads and runs the MAS command when `1` is selected |
| 3 | Theme | `1` Light, `2` Dark, `3` unchanged | Starts the selected built-in Windows theme |
| 3 | Browser | `1` Firefox Nightly, `2` Firefox, `3` none | Downloads and runs the selected Mozilla installer |

The region prompt accepts the country/region codes understood by `.NET`'s `RegionInfo` class. Invalid input is reported as an invalid country code and the script continues to the next setting.

## System areas affected

The script works across these Windows areas:

- **Registry:** `HKLM` policy and system settings plus `HKCU` user preferences.
- **Services:** startup types for telemetry, maps, storage, offline files, Internet Connection Sharing, OneSync, and related services.
- **Scheduled Tasks:** the UCPD task and the temporary `DebloaterResume` task.
- **AppX packages:** installed packages for all users and selected provisioned packages in the Windows image.
- **Windows features:** Recall and other optional components where the current Windows build exposes them.
- **File system:** user and system temporary folders, OneDrive folders, the Microsoft Store database permission, and the temporary persistent script directory.
- **Explorer and taskbar:** visibility, search, recommendations, file display, and task-ending behavior.
- **Power configuration:** creates and activates an Ultimate Performance power scheme.
- **Security and privacy configuration:** telemetry, location, SmartScreen-related policy values, Defender sample submission, WPBT, BitLocker, and Windows privacy policies.

## External downloads and installers

The script contacts these external locations during the normal or optional workflow:

| Purpose | Source |
| --- | --- |
| Bootstrap loader | `raw.githubusercontent.com/ModernTTY/debloater` |
| O&O ShutUp10++ | `dl5.oo-software.com` |
| Optional MAS activation | `get.activated.win` |
| Firefox installer | `download.mozilla.org` |

Firefox is downloaded to the current user's `Downloads` folder, launched, and removed after the installer exits. O&O ShutUp10++ is downloaded to the current user's temporary folder and launched from there.

## Files and temporary state

The repository contains:

- `bootstrap.ps1` — elevation-aware loader that downloads and starts the main script.
- `debloater.ps1` — the three-stage Windows customization script.
- `README.md` — usage and behavior documentation.
- `LICENSE` — this repository's Unlicense text.

During execution, the script creates:

- `%ProgramData%\Debloater\debloater.ps1` — stable copy used by Task Scheduler.
- A scheduled task named `DebloaterResume` — points to the next stage and runs at the current user's logon.
- A temporary Firefox installer in `Downloads` when a browser is selected.
- A temporary O&O ShutUp10++ executable in `%TEMP%`.

The persistent script copy and resume task are removed at the end of Stage 3.

## Compatibility and repeat runs

The script is designed for Windows 10/11 systems with the standard Windows PowerShell cmdlets for services, registry, AppX packages, scheduled tasks, BitLocker, and optional features. Results vary by Windows edition, build, installed packages, hardware architecture, and whether a component is already absent.

Many operations are conditional or use `-ErrorAction SilentlyContinue`. This means an unavailable service, package, registry key, or optional feature can be skipped while later sections continue. Running the script again applies the same selected settings where they are still available; removed packages and components are not recreated by the script.

The script detects ARM64 processors for the Firefox download and selects the matching Mozilla installer URL. Other system changes use Windows-native commands and registry paths rather than architecture-specific binaries.

## Troubleshooting

### The loader does not start

Run it from Windows PowerShell as Administrator and confirm that the computer can reach GitHub. The loader uses `ExecutionPolicy Bypass` for the process it starts and does not change the machine-wide execution policy.

### A prompt accepts no input

The Store, MAS, theme, and browser prompts only accept the numbered values shown on screen. The region prompt expects a two-letter country/region code.

### A package or service was not changed

This can happen when the component is not installed, is named differently on the current Windows build, is already removed, or is protected by the current edition. The script continues through many such cases without displaying a terminating error.

### A selected browser does not install

The installer is downloaded to `Downloads` and started as the current user. Check that the download completed and that the installer was allowed to finish before closing its window.

### The script stops after Explorer restarts

Explorer is intentionally stopped and started during Stage 3 so taskbar and Explorer settings can reload. Wait for the desktop shell to return before continuing with any other interaction.

## License and attribution

This repository is released under the Unlicense; see [LICENSE](LICENSE).

Some tweaks in this project are based on or adapted from **WinUtil** by Chris Titus Tech, which is available under the MIT License: <https://github.com/ChrisTitusTech/winutil>. The applicable upstream copyright and permission notice is preserved here for attribution:

> Copyright (c) Chris Titus Tech
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
