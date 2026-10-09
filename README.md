# Safe Gaming Optimizer

This toolkit records what is running, previews every requested action, optionally asks selected user applications to close normally, applies only temporary session tuning, and restores the original power plan after the game exits. It never selects processes by RAM usage, never force-kills them, never disables Defender or other security controls, never changes networking, and never uses High or RealTime process priority.

## First run

1. Extract or copy the whole `GamingOptimizer` folder to a normal local folder.
2. Double-click `Launch Gaming Optimizer.bat`.
3. Choose **Inspect** first. It creates a process CSV and system JSON under `data\snapshots`.
4. Choose **Preview**. This changes nothing.
5. Choose **Start a game session**, select the pictured game, then start it from its normal launcher within 120 seconds. You can instead run the PowerShell command below with the exact shortcut or executable path.

You do not need Administrator mode. Do not run it as Administrator unless troubleshooting a specific access error.

## PowerShell examples

Open PowerShell in the toolkit folder:

```powershell
# Read-only inventory
.\GamingOptimizer.ps1 -Action Inspect

# Preview a session and show the exact matching Spotify processes
.\GamingOptimizer.ps1 -Action Preview -Game GTA5 -CloseApps Spotify

# Start from a shortcut, gently request Spotify to close, and temporarily use AboveNormal priority
.\GamingOptimizer.ps1 -Action Start -Game GTA5 -GamePath 'C:\path\to\Grand Theft Auto V.lnk' -CloseApps Spotify -Priority AboveNormal

# Also try the installed High performance power plan, restoring the old plan afterward
.\GamingOptimizer.ps1 -Action Start -Game GTA5 -UseHighPerformance

# Roll back the latest saved session after an interruption or crash
.\GamingOptimizer.ps1 -Action Rollback

# Run non-mutating guardrail tests
.\GamingOptimizer.ps1 -Action SelfTest
```

Supported presets: `GTA5`, `ZeroHour`, `WatchDogs2`, `HollowKnight`, `Silksong`, `Cuphead`, and `Custom`. The pictured launchers are not treated as games. For another game, use `Custom` with the actual game `.exe` in `-GamePath`; process detection uses that executable filename. Store shortcuts are supported only with a named preset because a shortcut filename does not reliably identify its launched process.

Allowed `-CloseApps` values are `Spotify`, `BlueStacks`, `Chrome`, `Edge`, `Firefox`, `Discord`, and `Teams`. Pass more than one as a comma-separated PowerShell array, for example `-CloseApps Spotify,Chrome`. Each is handled through a normal window-close request. Services, tray-only helpers, Windows components, security software, launchers, and unrecognized names fail closed and are left running.

## What the session changes

- Optional power plan: switches to an already-installed plan named **High performance**, then restores the exact previous plan GUID.
- Optional game priority: `AboveNormal` only, applied after the game starts. Process priority ends with the process.
- Optional cleanup: only labels explicitly passed through `-CloseApps`, only if they map to the built-in allowlist, and only through a normal close request.
- Snapshots: process inventory before and after the session plus JSON session state and dated logs.

Game Mode, Game Bar, registry values, services, startup entries, page file, CPU affinity, GPU settings, timer resolution, memory standby lists, TCP settings, Defender, firewall, and Windows Update are not modified.

## Recovery and limitations

The session state is written before changes. If PowerShell, Windows, or the game crashes, rerun the launcher and choose **Roll back latest session**. Closed apps are not relaunched automatically because reconstructing their arguments, tabs, documents, and privileges is unreliable. Reopen them normally.

If the game process is not detected, the session times out after 120 seconds and restores the power plan. Use the correct preset or supply `-GamePath`. Some store launchers hand off through multiple processes, so start the game manually first when needed.

The Windows display name for the High performance plan may be localized. If it cannot be found, the toolkit logs a warning and keeps the current plan.

## Realistic FPS expectations

Closing a genuinely busy browser, emulator, recording app, or updater can improve frame-time consistency when CPU or RAM pressure is real. A power plan can help a laptop that was using a restrictive profile. On a healthy desktop that is already GPU-limited, expect little or no average-FPS increase. This toolkit cannot overcome a GPU limit, CPU bottleneck, thermal throttling, insufficient VRAM/RAM, slow storage streaming, shader compilation, or game-engine limits. Benchmark the same scene with the same settings and compare 1% lows, temperatures, utilization, and stutter, not just one FPS number.

## Information needed for useful tuning

Please provide:

- Windows 10 or 11, exact version/build (`winver`)
- CPU, GPU and VRAM, installed RAM, desktop/laptop model, and monitor resolution/refresh rate
- Whether each game is on SSD or HDD and approximate free space
- A Task Manager screenshot of **Processes**, sorted by CPU and then Memory, while idle and while the game is struggling
- Task Manager **Performance** screenshots for CPU, Memory, GPU, and Disk during the issue
- Game, launcher/store, graphics resolution/settings, current FPS range, target FPS, and whether the issue is low average FPS, stutter, input lag, or crashes
- Any overlays, recording/streaming tools, mods, antivirus other than Defender, RGB/control utilities, and laptop vendor performance software

Do not post usernames, license keys, account details, or unrelated window contents. A clean screenshot crop is enough.

## Dry-run validation checklist

1. Run `SelfTest`; it must pass.
2. Run `Inspect`; confirm CSV and JSON appear and no settings change.
3. Run `Preview` with no `-CloseApps`; confirm it says no applications will close.
4. Run `Preview -CloseApps Spotify`; confirm only current Spotify processes appear.
5. Try an unknown label; it must exit with an error and change nothing.
6. Start a session without High performance, exit the game, and confirm a session JSON says `Restored: true`.
7. If using High performance, record the active plan first with `powercfg /getactivescheme`; after game exit or Rollback it must match exactly.
8. Interrupt a session with Ctrl+C, run Rollback, and confirm the saved plan is restored.

