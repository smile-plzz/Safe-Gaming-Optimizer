# Safe Gaming Optimizer

Safe Gaming Optimizer is a conservative Windows desktop app for preparing a PC for a gaming session and returning it to its previous state afterward.

## Download and use

1. Download `SafeGamingOptimizer.exe` from the latest GitHub release.
2. Open it and approve the Windows administrator prompt.
3. Review the running apps it finds. Green **Recommended** items are selected automatically. Yellow **Review** items require your choice because they may contain unsaved work or active downloads.
4. Click **Optimize for gaming**, then launch your game normally.
5. Minimize the optimizer. It stays available in the notification area.
6. When gaming is finished, click **Finish gaming & restore**. If you try to close it during a session, it asks whether you are done.

The app saves recovery state under `%LOCALAPPDATA%\SafeGamingOptimizer`. If Windows or the app closes unexpectedly, the next launch offers to restore the unfinished session.

## What it does

- Analyzes known optional desktop apps currently using memory and CPU time.
- Labels each result **Recommended**, **Review**, or **Protected**, with a plain-language reason.
- Gracefully closes selected apps first, then ends only the selected process if it does not respond.
- Temporarily switches to an already-installed Windows **High performance** power plan when available.
- Records every session change before applying it.
- Restores the exact previous power plan and reopens apps that have a safe executable path.
- Continues running in the notification area until the gaming session is finished.

## Safety boundaries

The one-click option is intentionally conservative. It does not choose unknown processes based only on RAM usage. High memory use does not make a process safe to kill.

The app never selects Windows core processes, Explorer, audio, sign-in, Defender, firewall, services, drivers, launchers, or unknown processes. It does not disable security, Windows Update, networking, page files, services, startup entries, or scheduled tasks. It does not clear the Windows standby cache because Windows uses that cache to make applications faster and releases it automatically when games need memory.

Closing an application cannot perfectly reconstruct every tab, command-line argument, document, call, or download. For that reason browsers, cloud-sync clients, emulators, and recording software are marked **Review** and are not included in the generalized safe option.

No optimizer can guarantee more FPS. This app is most useful when optional applications are consuming meaningful RAM or CPU in the background. It cannot fix GPU limits, thermal throttling, insufficient VRAM, game-engine stutter, slow storage, or demanding graphics settings.

## Build from source

Requirements: Windows 10/11 and the .NET 9 SDK.

```powershell
.\build-release.ps1
```

The self-contained Windows executable is written to `release\SafeGamingOptimizer.exe`. End users do not need to install .NET.

The original PowerShell prototypes remain in the repository for history and recovery reference. The supported product is the desktop app under `SafeGamingOptimizer\`.
