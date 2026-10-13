This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Safe Gaming Optimizer is a conservative Windows desktop utility that closes user-approved optional apps for a gaming session, stays in the notification area, and restores the prior power plan and restartable apps afterward.

## Commands

```powershell
dotnet build .\Safe-Gaming-Optimizer.sln -c Release
dotnet .\SafeGamingOptimizer\bin\Release\net9.0-windows\win-x64\SafeGamingOptimizer.dll --self-test
.\GamingOptimizer.ps1 -Action SelfTest
.\build-release.ps1
```

The release script creates a self-contained `win-x64` executable under `release\`. There are no external application dependencies, secrets, or configuration files. CI repeats the build, desktop guardrail test, and single-file publish.

## Architecture

- `SafeGamingOptimizer/Program.cs` is the WinForms entry point and exposes the non-mutating `--self-test` path.
- `SafeGamingOptimizer/MainForm.cs` owns the process table, safety presentation, one-click action, tray lifecycle, and finish-gaming confirmation.
- `SafeGamingOptimizer/OptimizerService.cs` owns process classification, protected-name exclusions, graceful-close/terminate behavior, power-plan capture/restoration, persistent recovery state, and system memory summary.
- `SafeGamingOptimizer/Models.cs` contains process candidates and the serialized session model.
- `SafeGamingOptimizer/app.manifest` requests administrator elevation at launch.
- `GamingOptimizer.ps1` and `Analyze Gaming.ps1` are the earlier PowerShell prototypes. They remain useful reference and recovery tools but are not the primary product UI.
- `.github/workflows/build.yml` produces the downloadable self-contained Windows artifact.

Session recovery state is written atomically to `%LOCALAPPDATA%\SafeGamingOptimizer\active-session.json` before mutations. Startup detects an unrestored record and offers recovery.

## Conventions to preserve when editing

- Unknown processes must fail closed. Never infer that a process is safe to terminate from RAM or CPU use alone.
- Windows, security, shell, audio, driver, service, launcher, and optimizer processes must remain outside the optional process rules.
- Browsers, sync clients, emulators, and recording tools require explicit review and must not become default-selected.
- Save recovery state before changing a power plan or terminating an app. Restore the exact captured power-plan GUID, not a guessed default.
- Do not claim that clearing standby memory or caches creates lasting free RAM. Windows manages reusable cache automatically.
- Do not add registry, service, security, update, networking, page-file, timer-resolution, or driver tweaks to the generalized action.
- Keep forced termination as a fallback after a normal close request, and only for a process the user selected from the explicit allowlist.
