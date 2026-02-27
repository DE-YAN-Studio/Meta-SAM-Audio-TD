@echo off
setlocal enabledelayedexpansion

echo ========================================
echo  SAM-Audio Setup
echo ========================================
echo.
echo Choose install mode:
echo   [1] conda environment (recommended — isolated, easy to redo)
echo   [2] system Python
echo.
set /p MODE="Enter 1 or 2: "

if "%MODE%"=="1" goto :conda_setup
if "%MODE%"=="2" goto :system_setup
echo Invalid choice. Exiting.
pause & exit /b 1


:: ============================================================
:conda_setup
:: ============================================================
echo.
echo --- Conda environment setup ---

:: Find conda
set CONDA_EXE=
if exist "C:\ProgramData\anaconda3\Scripts\conda.exe"       set CONDA_EXE=C:\ProgramData\anaconda3\Scripts\conda.exe
if exist "%USERPROFILE%\anaconda3\Scripts\conda.exe"        set CONDA_EXE=%USERPROFILE%\anaconda3\Scripts\conda.exe
if exist "%USERPROFILE%\Miniconda3\Scripts\conda.exe"       set CONDA_EXE=%USERPROFILE%\Miniconda3\Scripts\conda.exe
if exist "C:\ProgramData\miniconda3\Scripts\conda.exe"      set CONDA_EXE=C:\ProgramData\miniconda3\Scripts\conda.exe
if "%CONDA_EXE%"=="" ( where conda >nul 2>&1 && set CONDA_EXE=conda )

if "%CONDA_EXE%"=="" (
    echo ERROR: conda not found. Install Anaconda or Miniconda from:
    echo   https://www.anaconda.com/download
    pause & exit /b 1
)
echo Found conda: %CONDA_EXE%

echo.
echo [1/7] Creating conda env "sam-audio" (Python 3.11)...
"%CONDA_EXE%" create -n sam-audio python=3.11 -y
if errorlevel 1 ( echo ERROR: env creation failed & pause & exit /b 1 )

echo.
echo [2/7] Installing CUDA 12.8 runtime into env...
"%CONDA_EXE%" install -n sam-audio cuda-runtime=12.8.1 -c nvidia -y
if errorlevel 1 ( echo ERROR: CUDA runtime install failed & pause & exit /b 1 )

echo.
echo [3/7] Installing FFmpeg (full-shared) via conda-forge...
"%CONDA_EXE%" install -n sam-audio ffmpeg -c conda-forge -y
if errorlevel 1 ( echo ERROR: FFmpeg install failed & pause & exit /b 1 )

echo.
echo [4/7] Installing PyTorch (cu128) via pip...
"%CONDA_EXE%" run -n sam-audio pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
if errorlevel 1 ( echo ERROR: PyTorch install failed & pause & exit /b 1 )

echo.
echo [5/7] Installing SAM-Audio from local repo...
cd /d "%~dp0sam-audio"
"%CONDA_EXE%" run -n sam-audio pip install .
if errorlevel 1 ( echo ERROR: sam-audio install failed & pause & exit /b 1 )
cd /d "%~dp0"

echo.
echo [6/7] Installing server dependencies...
"%CONDA_EXE%" run -n sam-audio pip install "fastapi>=0.115" "uvicorn[standard]>=0.30" "python-multipart>=0.0.9"
if errorlevel 1 ( echo ERROR: server deps install failed & pause & exit /b 1 )

echo.
echo [7/7] Verifying...
"%CONDA_EXE%" run -n sam-audio python -c "import torch; cuda=torch.cuda.is_available(); print('  torch:    ', torch.__version__); print('  CUDA:     ', cuda)"
"%CONDA_EXE%" run -n sam-audio python -c "import sam_audio; print('  sam_audio: OK')"
"%CONDA_EXE%" run -n sam-audio python -c "import fastapi;   print('  fastapi:   OK')"
"%CONDA_EXE%" run -n sam-audio python -c "import subprocess; r=subprocess.run(['ffmpeg','-version'],capture_output=True,text=True); print('  ffmpeg:   ', r.stdout.splitlines()[0] if r.returncode==0 else 'NOT FOUND')"

echo.
echo USE_CONDA=1> "%~dp0.env_mode"
goto :done


:: ============================================================
:system_setup
:: ============================================================
echo.
echo --- System Python setup ---

python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found. Install Python 3.11+ from https://python.org
    pause & exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo Found: %%v

echo.
echo [1/5] Installing CUDA-enabled PyTorch (cu128)...
echo       Removing any existing CPU-only build first...
pip uninstall torch torchvision torchaudio -y >nul 2>&1
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
if errorlevel 1 ( echo ERROR: PyTorch install failed & pause & exit /b 1 )

echo.
echo [2/5] Installing SAM-Audio from local repo...
cd /d "%~dp0sam-audio"
pip install .
if errorlevel 1 ( echo ERROR: sam-audio install failed & pause & exit /b 1 )
cd /d "%~dp0"

echo.
echo [3/5] Installing server dependencies...
pip install "fastapi>=0.115" "uvicorn[standard]>=0.30" "python-multipart>=0.0.9"
if errorlevel 1 ( echo ERROR: server deps install failed & pause & exit /b 1 )

echo.
echo [4/5] Installing FFmpeg (full-shared)...
set FFMPEG_DIR=%~dp0ffmpeg

if exist "%FFMPEG_DIR%\bin\ffmpeg.exe" (
    echo   FFmpeg already installed at %FFMPEG_DIR%, skipping.
    goto :ffmpeg_path
)

:: Find or install 7-Zip
set SEVENZIP=
if exist "C:\Program Files\7-Zip\7z.exe"       set SEVENZIP=C:\Program Files\7-Zip\7z.exe
if exist "C:\Program Files (x86)\7-Zip\7z.exe" set SEVENZIP=C:\Program Files (x86)\7-Zip\7z.exe
where 7z >nul 2>&1 && set SEVENZIP=7z

if "%SEVENZIP%"=="" (
    echo   7-Zip not found — installing via winget...
    winget install 7zip.7zip -e --silent
    if errorlevel 1 ( echo ERROR: Could not install 7-Zip & pause & exit /b 1 )
    set SEVENZIP=C:\Program Files\7-Zip\7z.exe
)

:: Download
echo   Downloading FFmpeg full-shared build from gyan.dev...
powershell -Command "Invoke-WebRequest -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z' -OutFile '%TEMP%\ffmpeg-shared.7z' -UseBasicParsing"
if errorlevel 1 ( echo ERROR: Download failed & pause & exit /b 1 )

:: Extract to temp folder then move the inner build folder to FFMPEG_DIR
echo   Extracting...
"%SEVENZIP%" x "%TEMP%\ffmpeg-shared.7z" -o"%TEMP%\ffmpeg-extract" -y >nul
if errorlevel 1 ( echo ERROR: Extraction failed & pause & exit /b 1 )

:: The archive contains a single versioned folder e.g. ffmpeg-7.1-full_build-shared
for /d %%d in ("%TEMP%\ffmpeg-extract\*") do (
    if exist "%%d\bin\ffmpeg.exe" (
        move "%%d" "%FFMPEG_DIR%" >nul
    )
)
rd /s /q "%TEMP%\ffmpeg-extract" >nul 2>&1
del "%TEMP%\ffmpeg-shared.7z" >nul 2>&1

if not exist "%FFMPEG_DIR%\bin\ffmpeg.exe" (
    echo ERROR: FFmpeg extraction failed — bin\ffmpeg.exe not found.
    pause & exit /b 1
)
echo   Extracted to %FFMPEG_DIR%

:: Add bin to user PATH if not already present
:ffmpeg_path
powershell -Command "$bin='%FFMPEG_DIR%\bin'; $p=[Environment]::GetEnvironmentVariable('PATH','User'); if ($p -notlike \"*$bin*\") { [Environment]::SetEnvironmentVariable('PATH',\"$p;$bin\",'User'); Write-Host '  Added to user PATH — restart your terminal to take effect.' } else { Write-Host '  Already in user PATH.' }"

echo.
echo [5/5] Verifying...
python -c "import torch; cuda=torch.cuda.is_available(); print('  torch:    ', torch.__version__); print('  CUDA:     ', cuda)"
python -c "import sam_audio; print('  sam_audio: OK')"
python -c "import fastapi;   print('  fastapi:   OK')"
"%FFMPEG_DIR%\bin\ffmpeg.exe" -version 2>nul | findstr /i "ffmpeg version" && echo   ffmpeg:    OK

echo USE_CONDA=0> "%~dp0.env_mode"
goto :done


:: ============================================================
:done
:: ============================================================
echo.
echo Setup complete! Run start_server.bat to launch the server.
pause
