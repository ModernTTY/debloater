# Windows Debloater

A Windows 10/11 PowerShell script that applies privacy, services, user-interface, and app-removal tweaks with minimal interaction. It must be run as Administrator and makes substantial system changes. Read the scope below before running it.

## What it changes

The script runs in three stages:

### Stage 1 — UCPD and reboot setup

- Disables the `UCPD velocity` scheduled task, when present.
- Sets the Windows `UCPD` service startup value to disabled.
- Saves a copy of the script in `%ProgramData%\Debloater`.
- Registers a temporary `DebloaterResume` scheduled task and reboots after 15 seconds.

### Stage 2 — region and SmartScreen settings

- Prompts for a two-letter country code and changes the Windows home/device region when the code is valid.
- Disables Smart App Control / SmartScreen policy values.
- Registers Stage 3 to run at the next logon and reboots after 15 seconds.

### Stage 3 — debloat and system tweaks

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

The script uses `SilentlyContinue` for many operations, so an unsupported package, service, registry path, or feature may simply be skipped without stopping the run. It is not a dry-run tool and does not create a general backup of registry settings, removed apps, or files.

## How to start

### Recommended: bootstrap loader

Open **Windows PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/ModernTTY/debloater/refs/heads/main/bootstrap.ps1 | iex
```

The bootstrap script downloads `debloater.ps1` to `%ProgramData%\Debloater` and starts Stage 1 from a real file. This is important because the automatic resume mechanism needs `$PSCommandPath`; running the main script directly through `irm | iex` cannot reliably provide it.

### Local copy

From an elevated PowerShell window in the repository directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\debloater.ps1
```

The local script can also be started explicitly with `.\debloater.ps1 -Stage 1`, but normally you should let the script advance through all three stages itself.

Requirements:

- Windows PowerShell with Administrator privileges.
- Internet access for the bootstrap download, O&O ShutUp10++, optional MAS, and optional Firefox installation.
- A user session that can log on again after each reboot.

## Prompts and choices

Only these actions require an interactive choice:

1. **Country/region** — Stage 2 asks for a two-letter country code such as `BE`, `LV`, `US`, or `GB`.
2. **Microsoft Store** — Stage 3 asks whether to uninstall it. Choosing `1` removes the Store and Store Purchase App for installed and provisioned users; choosing `2` keeps it.
3. **MAS activation** — Stage 3 asks whether to download and run MAS from `get.activated.win`. Choosing `1` runs it; choosing `2` skips it.
4. **Theme** — Choose Windows Light, Windows Dark, or leave the current theme unchanged.
5. **Browser** — Choose Firefox Nightly, Firefox, or no browser. The selected installer is downloaded to `Downloads`, run, and then removed.

O&O ShutUp10++ is launched automatically; it is not selected through a prompt. Review its settings yourself before applying anything in that application.

## Why it reboots during the script

The reboots are intentional. The script uses three stages because some service, policy, app-package, and device-region changes are applied more reliably after Windows restarts:

```text
Stage 1 → schedule Stage 2 → reboot → log on
Stage 2 → schedule Stage 3 → reboot → log on
Stage 3 → clean up → final reboot
```

The `DebloaterResume` scheduled task starts the next stage automatically at logon with highest privileges. The reboot is scheduled with a 15-second delay. To cancel a pending reboot, run this in another elevated window:

```powershell
shutdown /a
```

If automatic resume does not work, run the local persistent copy manually:

```powershell
& "$env:ProgramData\Debloater\debloater.ps1" -Stage 2
```

or `-Stage 3`, depending on the last completed stage. Do not run multiple stages at the same time.

## Important warnings

- Back up important files and create a restore point before running this script.
- It can disable privacy/security protections, disable services, remove Windows components, start decrypting the system drive by disabling BitLocker, remove Edge and OneDrive, and delete temporary files.
- Removing the Microsoft Store, Edge, OneDrive, Camera, Paint, Widgets, Xbox components, or other AppX packages may affect features or make later reinstallations difficult.
- The MAS option is an external activation tool and is entirely optional. Do not select it unless you understand and accept its licensing and security implications.
- The script downloads and executes software from external websites. Inspect the source and verify the URLs before use.
- There is no supported undo script. Restore from a backup or reinstall affected Windows components if you need to reverse changes.

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
