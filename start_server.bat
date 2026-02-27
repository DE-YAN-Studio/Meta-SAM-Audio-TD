@echo off
setlocal

:: Read install mode written by setup.bat
set USE_CONDA=1
if exist "%~dp0.env_mode" (
    for /f "tokens=2 delims==" %%v in (%~dp0.env_mode) do set USE_CONDA=%%v
)

if "%USE_CONDA%"=="1" goto :start_conda
goto :start_system


:start_conda
set CONDA_EXE=
if exist "C:\ProgramData\anaconda3\Scripts\conda.exe"       set CONDA_EXE=C:\ProgramData\anaconda3\Scripts\conda.exe
if exist "%USERPROFILE%\anaconda3\Scripts\conda.exe"        set CONDA_EXE=%USERPROFILE%\anaconda3\Scripts\conda.exe
if exist "%USERPROFILE%\Miniconda3\Scripts\conda.exe"       set CONDA_EXE=%USERPROFILE%\Miniconda3\Scripts\conda.exe
if exist "C:\ProgramData\miniconda3\Scripts\conda.exe"      set CONDA_EXE=C:\ProgramData\miniconda3\Scripts\conda.exe
if "%CONDA_EXE%"=="" ( where conda >nul 2>&1 && set CONDA_EXE=conda )

if "%CONDA_EXE%"=="" (
    echo ERROR: conda not found. Run setup.bat first.
    pause & exit /b 1
)

:: Derive path to activate.bat from conda.exe location
for %%i in ("%CONDA_EXE%") do set CONDA_SCRIPTS=%%~dpi
call "%CONDA_SCRIPTS%activate.bat" sam-audio

echo Starting SAM-Audio server (conda env: sam-audio) on http://127.0.0.1:8765
echo Press Ctrl+C to stop.
echo.
cd /d "%~dp0"
python server.py
pause & exit /b


:start_system
echo Starting SAM-Audio server (system Python) on http://127.0.0.1:8765
echo Press Ctrl+C to stop.
echo.
cd /d "%~dp0"
python server.py
pause
