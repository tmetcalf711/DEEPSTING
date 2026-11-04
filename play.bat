@echo off
rem ---------------------------------------------------------------------------
rem  DeepSting launcher (Windows)
rem  Double-click to update the game to the latest version and play it.
rem  - Put this file anywhere (e.g. your Desktop). The first run downloads the
rem    game into a "DeepSting" folder next to it; later runs just update it.
rem    (Run from inside the game folder itself, it updates that folder.)
rem  - Uses Git (recommended: it asks you to sign in to GitHub once, which a private
rem    repository needs); without Git it downloads the latest zip (public repos only).
rem  - Downloads Godot %GODOT_VERSION% once if it can't find it. To use your own
rem    copy, set the GODOT environment variable to the path of the Godot .exe.
rem  Your saves live in %%APPDATA%%\DeepSting and are
rem  never touched by updates.
rem ---------------------------------------------------------------------------
setlocal
title DeepSting
set "REPO=https://github.com/tmetcalf711/DEEPSTING"
rem Leave BRANCH empty to follow the repository's default branch, or name one (e.g. main).
set "BRANCH="
set "GODOT_VERSION=4.7.2"

set "HERE=%~dp0"
set "HERE=%HERE:~0,-1%"
if exist "%HERE%\project.godot" (
    set "GAME=%HERE%"
) else (
    set "GAME=%HERE%\DeepSting"
)
set "GODOT_DIR=%LOCALAPPDATA%\DeepSting\godot-%GODOT_VERSION%"
set "BRANCH_ARG="
set "REF=HEAD"
if defined BRANCH set "BRANCH_ARG=--branch %BRANCH%" & set "REF=%BRANCH%"
set "GODOT_NAME=Godot_v%GODOT_VERSION%-stable_win64"

echo.
echo   DeepSting - getting the latest version...
echo.

rem ---- 1. Update the game ----------------------------------------------------
call :find_git
if not defined GIT goto :zip_update
echo   Using Git: %GIT%
if exist "%GAME%\.git" goto :git_pull
if exist "%GAME%\project.godot" goto :git_adopt
"%GIT%" clone --depth 1 %BRANCH_ARG% %REPO%.git "%GAME%"
if errorlevel 1 goto :update_failed
goto :godot

:git_pull
"%GIT%" -C "%GAME%" pull --ff-only origin %REF%
if errorlevel 1 goto :update_failed
goto :godot

:git_adopt
rem A copy of the game that was downloaded as a zip: turn it into a Git copy so it can update
echo   Switching this folder over to Git updates (one time only)...
"%GIT%" -C "%GAME%" init -q
"%GIT%" -C "%GAME%" remote remove origin >nul 2>nul
"%GIT%" -C "%GAME%" remote add origin %REPO%.git
"%GIT%" -C "%GAME%" fetch --depth 1 origin %REF%
if errorlevel 1 goto :update_failed
"%GIT%" -C "%GAME%" reset -q --hard FETCH_HEAD
if errorlevel 1 goto :update_failed
if defined BRANCH "%GIT%" -C "%GAME%" branch -q -M %BRANCH%
goto :godot

:zip_update
echo   (Git not found - trying to download the latest zip instead)
set "TMPZIP=%TEMP%\deepsting-latest.zip"
set "TMPDIR=%TEMP%\deepsting-latest"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol='Tls12';" ^
  "Invoke-WebRequest -UseBasicParsing '%REPO%/archive/%REF%.zip' -OutFile '%TMPZIP%';" ^
  "if (Test-Path '%TMPDIR%') { Remove-Item -Recurse -Force '%TMPDIR%' };" ^
  "Expand-Archive -Force '%TMPZIP%' '%TMPDIR%'"
if errorlevel 1 (
    echo   The zip download needs the repository to be public. Install Git
    echo   from https://git-scm.com and sign in to GitHub when it asks, then run this again.
    goto :update_failed
)
for /d %%D in ("%TMPDIR%\*") do robocopy "%%D" "%GAME%" /E /NFL /NDL /NJH /NJS /NP >nul
del /q "%TMPZIP%" >nul 2>nul
rmdir /s /q "%TMPDIR%" >nul 2>nul
goto :godot

:update_failed
echo.
echo   Couldn't update the game (no internet, or local changes in the folder?).
if not exist "%GAME%\project.godot" (
    echo   There is no copy of the game yet, so there's nothing to play.
    pause
    exit /b 1
)
echo   Playing the version you already have.
echo.

rem ---- 2. Find (or fetch) Godot ---------------------------------------------
:godot
if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%" & goto :run
set "GODOT_EXE=%GODOT_DIR%\%GODOT_NAME%.exe"
if exist "%GODOT_EXE%" goto :run
echo   Downloading Godot %GODOT_VERSION% (one time only)...
if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol='Tls12';" ^
  "Invoke-WebRequest -UseBasicParsing 'https://github.com/godotengine/godot/releases/download/%GODOT_VERSION%-stable/%GODOT_NAME%.exe.zip' -OutFile '%GODOT_DIR%\godot.zip';" ^
  "Expand-Archive -Force '%GODOT_DIR%\godot.zip' '%GODOT_DIR%'; Remove-Item '%GODOT_DIR%\godot.zip'"
if not exist "%GODOT_EXE%" (
    echo.
    echo   Couldn't download Godot. Get Godot %GODOT_VERSION% from https://godotengine.org/download
    echo   and set the GODOT environment variable to the .exe path, then run this again.
    pause
    exit /b 1
)

rem ---- 3. Import new assets, then play ---------------------------------------
:run
echo   Preparing assets...
start "" /wait "%GODOT_EXE%" --headless --path "%GAME%" --import
echo   Starting DeepSting!
start "" "%GODOT_EXE%" --path "%GAME%"
endlocal
exit /b 0

rem ---- Find git.exe (PATH first, then the usual install folders) ------------
:find_git
set "GIT="
for /f "delims=" %%G in ('where git 2^>nul') do if not defined GIT set "GIT=%%G"
if defined GIT exit /b 0
for %%G in ("%ProgramFiles%\Git\cmd\git.exe" "%ProgramFiles(x86)%\Git\cmd\git.exe" "%LOCALAPPDATA%\Programs\Git\cmd\git.exe" "%ProgramW6432%\Git\cmd\git.exe") do if not defined GIT if exist "%%~G" set "GIT=%%~G"
if defined GIT exit /b 0
for /d %%D in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do if exist "%%D\resources\app\git\cmd\git.exe" set "GIT=%%D\resources\app\git\cmd\git.exe"
exit /b 0
