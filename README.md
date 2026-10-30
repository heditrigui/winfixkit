# WinFixKit

**Diagnose a broken Windows PC in one click, then run the right fix. Every fix has a dry run, gets logged, and asks before changing anything.**

[![CI](https://github.com/heditrigui/winfixkit/actions/workflows/ci.yml/badge.svg)](https://github.com/heditrigui/winfixkit/actions/workflows/ci.yml)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

![WinFixKit GUI after running Fix my PC: health checks, recommended-fix buttons and a dry run of the Windows Update repair](docs/screenshot.png)

WinFixKit is a small PowerShell module with a WPF front end. It packs the repairs IT support runs every day, from "the internet is broken" and "Windows Update is stuck" to "Teams won't sign in" and "my S: drive is gone". **Fix my PC** runs quick read-only checks and puts a button on screen for each fix it recommends. **Ticket bundle** zips up everything the helpdesk needs. Each fix is a small, documented function you can run from the GUI, a console, an RMM script or, with remote mode, on another PC.

## Install

```powershell
git clone https://github.com/heditrigui/winfixkit; .\winfixkit\WinFixKit.cmd
```

No git? Download the ZIP, extract it, run `Get-ChildItem -Recurse | Unblock-File` in the folder, then double-click **WinFixKit.cmd**.
Nothing else gets installed, and the toolkit never downloads anything at runtime.

## Features

### Diagnose and report

| Tool | Function | Needs admin | What it does |
|---|---|:-:|---|
| Fix my PC | `Get-FixKitDiagnosis` | - | Checks the network adapter, gateway, DNS, pending restart, Windows Update, print queue, disk space, system files, clock, audio and mapped drives, then recommends a fix for each problem (e.g. DNS failing → *Flush DNS cache*). In the GUI, each recommendation is a one-click button |
| Ticket bundle | `Export-FixKitTicketBundle` | - | One `.zip` with the snapshot (HTML + JSON), the diagnosis, the logs and every fix step's result, ready to attach to a ticket |
| System snapshot | `Export-SystemSnapshot` | - | OS, uptime, pending reboot, hardware, disks and disk health, network, recent errors, saved as an HTML/JSON/text report with flagged findings |
| Startup review | `Get-StartupItem` | - | Every Run key and Startup folder entry, with the Task Manager enabled/disabled state |

### Fixes

| Fix | Function | Needs admin | What it does |
|---|---|:-:|---|
| Flush DNS | `Reset-NetworkStack -DnsOnly` | - | Clears the DNS resolver cache |
| Network reset | `Reset-NetworkStack` | Yes | DNS flush, `netsh winsock reset` and `netsh int ip reset`, plus an optional DHCP release/renew |
| Windows Update repair | `Repair-WindowsUpdate` | Yes | Stops the update services, renames `SoftwareDistribution` and `catroot2` (rename, not delete), then restarts the services |
| System file repair | `Repair-SystemImage` | Yes | `DISM /RestoreHealth` then `sfc /scannow`. `-ScanOnly` only checks; `-Source` repairs offline from a WIM |
| Mapped drives | `Restore-MappedDrive` | - | Reconnects persistent network drives that show as disconnected, but only if the share is reachable. Unreachable mappings are left alone |
| Print spooler | `Reset-PrintSpooler` | Yes | Stops the spooler, clears stuck jobs, starts it again |
| No sound | `Restart-AudioService` | Yes | Restarts AudioEndpointBuilder and Audiosrv |
| Clock resync | `Sync-WindowsTime` | Yes | Starts Windows Time and forces `w32tm /resync`. Fixes sign-in and certificate errors caused by a wrong clock |
| Teams cache | `Reset-TeamsCache` | - | Closes Teams (new and classic) and renames its cache folder |
| Outlook cache | `Reset-OutlookCache` | - | Closes classic Outlook and renames `RoamCache`. `-IncludeOfflineData` also renames the `.ost` files so the mailbox downloads again |
| OneDrive sync | `Reset-OneDriveSync` | - | `OneDrive.exe /reset`, then starts OneDrive again. Your files stay put |
| Saved passwords | `Remove-SavedCredential` | - | Deletes Credential Manager entries for a target you choose (`Get-SavedCredentialTarget` lists them, without passwords). Refuses patterns that are too broad, such as `*` |
| Temp & disk cleanup | `Invoke-TempCleanup` | Only with `-IncludeSystem` | Deletes old temp files (skips recent and in-use ones). Optional Windows Temp and WinSxS component cleanup |
| Store apps | `Repair-StoreApp` | - | Re-registers Store apps from their local manifests |
| Debloat (optional) | `Invoke-Debloat` | Only with `-IncludeProvisioned` | Removes apps from a short, conservative list (News, Tips, Solitaire, Clipchamp and others). All of them can be reinstalled from the Store |

## Safety

- **Dry run first.** The GUI starts with *Dry run* switched on. Every fix supports `-WhatIf` and returns the exact steps it would take, without needing admin rights.
- **Asks before acting.** Destructive fixes use `ConfirmImpact = 'High'`, so PowerShell prompts before each step. The GUI shows its own confirmation dialog.
- **Admin only when needed.** The GUI runs as a standard user. A fix that needs elevation opens its own UAC prompt and runs in a separate administrator window. No other fix gets elevated.
- **Everything is logged.** Every step, dry run, skip and failure goes to `%LOCALAPPDATA%\WinFixKit\Logs\WinFixKit-yyyyMMdd.log`, and each step's result and output also go to `FixResults-yyyyMMdd.jsonl`. Set `WINFIXKIT_LOGDIR` to send the logs somewhere else.
- **Reversible where possible.** Windows Update, Teams and Outlook caches are renamed to `*.bak-<timestamp>`, not deleted. Debloat removes only apps you can get back from the Store, and never touches Photos, Calculator, Media Player, Terminal or the Store itself.
- **Offline.** Nothing is downloaded at runtime, and a Pester test enforces this. Some steps use the network the way Windows normally does: DISM `/RestoreHealth` may use Windows Update as its repair source (use `-Source` to stay fully offline), the clock resync contacts your time server, and the diagnosis pings your gateway and resolves one host name.

## Use from PowerShell

```powershell
Import-Module .\WinFixKit\WinFixKit.psd1

Reset-NetworkStack -WhatIf                # preview the steps
Repair-WindowsUpdate                      # prompts before each step (run elevated)
Invoke-TempCleanup -OlderThanDays 7 -Confirm:$false
Export-SystemSnapshot | Invoke-Item       # open the HTML report
Get-StartupItem | Where-Object Enabled
Get-FixKitCatalog                         # every fix, with admin/destructive flags

Get-FixKitDiagnosis | Format-Table Status, Check, Detail, FixTitle
Export-FixKitTicketBundle -Days 3         # zip for the ticket
Remove-SavedCredential -Target '*fileserver01*' -WhatIf
```

## Remote mode

Run any fix or check on other PCs over PowerShell remoting. Nothing needs to be installed there: WinFixKit sends its own code along with the command.

```powershell
Invoke-FixKitRemote -ComputerName PC042 -Fix diagnose
Invoke-FixKitRemote -ComputerName PC042, PC043 -Fix spooler -Credential (Get-Credential) -WhatIf
Invoke-FixKitRemote -ComputerName PC042 -Fix Remove-SavedCredential -Parameters @{ Target = '*fileserver*' }
```

`-Fix` takes a catalog id (`Get-FixKitCatalog`) or a command name. `-WhatIf` gives a dry run on the remote PC. Without it, you confirm once per computer here, and the fix then runs without prompting on the remote side. Results come back with `PSComputerName`, the remote PC logs to its own WinFixKit log, and this PC logs what was sent where. The targets need WinRM (`Enable-PSRemoting`) and usually admin rights.

Every fix returns `WinFixKit.StepResult` objects (`Step`, `Target`, `Status` = Done / DryRun / Skipped / Failed, `Message`, `Output`), so they are easy to use in scripts and RMM tools. Run `Get-Help <function> -Full` for the details.

## Project layout

```
WinFixKit/            the module (Public/ = exported fixes and checks, Private/ = logging, elevation, credential API, GUI)
Start-FixKit.ps1      launches the GUI
WinFixKit.cmd         double-click launcher
tests/                Pester 5 tests (read-only paths and dry runs only)
.github/workflows/    PSScriptAnalyzer + Pester on Windows PowerShell 5.1 and PowerShell 7
```

## Development

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests
```

The tests never change the machine. They run the read-only functions, `-WhatIf` dry runs, and real deletes inside Pester's `TestDrive` only. Problem cases in the diagnosis and the remote calls are tested with mocks. To add a fix, write a function in `WinFixKit/Public` that sends each step through `Invoke-FixStep`, then add it to `Get-FixKitCatalog`. The GUI picks it up automatically.

Want a single `.exe`? [ps2exe](https://github.com/MScholtes/PS2EXE) is the usual tool for that, but it isn't set up in this repo. `WinFixKit.cmd` already gives you a double-click launcher.

## License

[MIT](LICENSE)
