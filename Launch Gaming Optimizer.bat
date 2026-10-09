@echo off
setlocal
title Safe Gaming Optimizer
set "SCRIPT=%~dp0GamingOptimizer.ps1"

if not exist "%SCRIPT%" (
  echo ERROR: GamingOptimizer.ps1 was not found beside this launcher.
  pause
  exit /b 1
)

:MENU
cls
echo ==============================================
echo   Safe Gaming Optimizer
echo ==============================================
echo   1. Inspect this PC (read-only)
echo   2. Preview a game session (read-only)
echo   3. Start a game session (no apps closed)
echo   4. Start GTA V and gently close Spotify
echo   5. Roll back latest session
echo   6. Run self-tests
echo   7. Exit
echo.
set /p "CHOICE=Choose 1-7: "

if "%CHOICE%"=="1" goto INSPECT
if "%CHOICE%"=="2" goto PREVIEW
if "%CHOICE%"=="3" goto START
if "%CHOICE%"=="4" goto STARTSPOTIFY
if "%CHOICE%"=="5" goto ROLLBACK
if "%CHOICE%"=="6" goto TEST
if "%CHOICE%"=="7" exit /b 0
goto MENU

:INSPECT
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Inspect
goto DONE
:PREVIEW
set "MODE=Preview"
call :PICKGAME
if not defined GAME goto MENU
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Preview -Game %GAME%
goto DONE
:START
set "MODE=Start"
call :PICKGAME
if not defined GAME goto MENU
echo.
echo Start the game from its normal launcher now. This window will wait up to 120 seconds.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Start -Game %GAME%
goto DONE
:STARTSPOTIFY
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Start -Game GTA5 -CloseApps Spotify
goto DONE
:ROLLBACK
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action Rollback
goto DONE
:TEST
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action SelfTest
:DONE
echo.
pause
goto MENU

:PICKGAME
set "GAME="
cls
echo ==============================================
echo   Choose game for %MODE%
echo ==============================================
echo   1. Grand Theft Auto V
echo   2. Zero Hour
echo   3. Watch Dogs 2
echo   4. Hollow Knight
echo   5. Hollow Knight: Silksong
echo   6. Cuphead
echo   7. Cancel
echo.
set /p "GAMECHOICE=Choose 1-7: "
if "%GAMECHOICE%"=="1" set "GAME=GTA5"
if "%GAMECHOICE%"=="2" set "GAME=ZeroHour"
if "%GAMECHOICE%"=="3" set "GAME=WatchDogs2"
if "%GAMECHOICE%"=="4" set "GAME=HollowKnight"
if "%GAMECHOICE%"=="5" set "GAME=Silksong"
if "%GAMECHOICE%"=="6" set "GAME=Cuphead"
exit /b 0

