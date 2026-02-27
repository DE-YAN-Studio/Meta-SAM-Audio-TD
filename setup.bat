@echo off
setlocal

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
echo [1/6] Creating conda env "sam-audio" (Python 3.11)...
"%CONDA_EXE%" create -n sam-audio python=3.11 -y
if errorlevel 1 ( echo ERROR: env creation failed & pause & exit /b 1 )

echo.
echo [2/6] Installing CUDA 12.8 runtime into env...
"%CONDA_EXE%" install -n sam-audio cuda-runtime=12.8.1 -c nvidia -y
if errorlevel 1 ( echo ERROR: CUDA runtime install failed & pause & exit /b 1 )

echo.
echo [3/6] Installing PyTorch (cu128) via pip...
"%CONDA_EXE%" run -n sam-audio pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
if errorlevel 1 ( echo ERROR: PyTorch install failed & pause & exit /b 1 )

echo.
echo [4/6] Installing SAM-Audio from local repo...
cd /d "%~dp0sam-audio"
"%CONDA_EXE%" run -n sam-audio pip install .
if errorlevel 1 ( echo ERROR: sam-audio install failed & pause & exit /b 1 )
cd /d "%~dp0"

echo.
echo [5/6] Installing server dependencies...
"%CONDA_EXE%" run -n sam-audio pip install "fastapi>=0.115" "uvicorn[standard]>=0.30" "python-multipart>=0.0.9"
if errorlevel 1 ( echo ERROR: server deps install failed & pause & exit /b 1 )

echo.
echo [6/6] Verifying...
"%CONDA_EXE%" run -n sam-audio python -c "import torch; cuda=torch.cuda.is_available(); print('  torch:    ', torch.__version__); print('  CUDA:     ', cuda)"
"%CONDA_EXE%" run -n sam-audio python -c "import sam_audio; print('  sam_audio: OK')"
"%CONDA_EXE%" run -n sam-audio python -c "import fastapi;   print('  fastapi:   OK')"

echo.
echo Wrote: USE_CONDA=1 to .env_mode
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
echo [1/4] Installing CUDA-enabled PyTorch (cu128)...
echo       Removing any existing CPU-only build first...
pip uninstall torch torchvision torchaudio -y >nul 2>&1
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
if errorlevel 1 ( echo ERROR: PyTorch install failed & pause & exit /b 1 )

echo.
echo [2/4] Installing SAM-Audio from local repo...
cd /d "%~dp0sam-audio"
pip install .
if errorlevel 1 ( echo ERROR: sam-audio install failed & pause & exit /b 1 )
cd /d "%~dp0"

echo.
echo [3/4] Installing server dependencies...
pip install "fastapi>=0.115" "uvicorn[standard]>=0.30" "python-multipart>=0.0.9"
if errorlevel 1 ( echo ERROR: server deps install failed & pause & exit /b 1 )

echo.
echo [4/4] Verifying...
python -c "import torch; cuda=torch.cuda.is_available(); print('  torch:    ', torch.__version__); print('  CUDA:     ', cuda)"
python -c "import sam_audio; print('  sam_audio: OK')"
python -c "import fastapi;   print('  fastapi:   OK')"

echo USE_CONDA=0> "%~dp0.env_mode"
goto :done


:: ============================================================
:done
:: ============================================================
echo.
echo ========================================
echo  FFmpeg is required:
echo.
echo  winget/choco ffmpeg builds are STATIC and will NOT work.
echo  Install the full-shared build from gyan.dev and add its
echo  /bin folder to your system PATH:
echo    https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z
echo ========================================
echo.
echo Setup complete! Run start_server.bat to launch the server.
pause
