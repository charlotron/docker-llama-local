@echo off
setlocal enabledelayedexpansion

echo.
echo # --- LOCAL INFRASTRUCTURE ---

:: --- Configuration Loading ---
if not exist .env echo   ! ERROR: .env not found
if exist .env echo   - Loading configuration (.env)...
if exist .env for /f "usebackq tokens=1* delims==" %%a in (`findstr /v /b "#" .env`) do set "%%a=%%b"
if exist .env echo   - Configuration loaded

:: Default values
if not defined HF_REPO set "HF_REPO=Qwen/Qwen2.5-Coder-14B-Instruct-GGUF"
if not defined HF_FILE set "HF_FILE=qwen2.5-coder-14b-instruct-q4_k_m.gguf"
if not defined LLAMA_PORT set "LLAMA_PORT=12345"
if not defined COMPOSE_FILE set "COMPOSE_FILE=docker/docker-compose-gpu.yml"

:: --- Model Information ---
echo.
echo # --- MODEL CONFIGURATION ---
echo   - Repository: %HF_REPO%
echo   - File:       %HF_FILE%
echo   - Port:       %LLAMA_PORT%

set "MODEL_DIR=docker\data\models"
set "MODEL_PATH=%MODEL_DIR%\%HF_FILE%"

if not exist "%MODEL_DIR%" mkdir "%MODEL_DIR%"

if not exist "%MODEL_PATH%" (
    echo.
    echo # --- DOWNLOAD REQUIRED ---
    echo   The model does not exist locally. Starting download...
    set "DOWNLOAD_URL=https://huggingface.co/%HF_REPO%/resolve/main/%HF_FILE%"
    powershell -Command "Invoke-WebRequest -Uri '!DOWNLOAD_URL!' -OutFile '!MODEL_PATH!'"
    if !errorlevel! neq 0 echo   ! ERROR: Download failed && exit /b 1
    echo   - Download complete
)

:: --- Deployment with Docker ---
echo.
echo # --- DOCKER DEPLOYMENT ---
echo   - Restarting services...

set "COMPOSE_FILE_WIN=%COMPOSE_FILE:/=\%"

docker compose -f "%COMPOSE_FILE_WIN%" down >nul 2>&1
docker compose -f "%COMPOSE_FILE_WIN%" up -d

if !errorlevel! neq 0 (
    echo   ! ERROR: Docker Compose failed
    exit /b 1
)

echo   - Waiting for server...
echo   (You can check logs with: docker logs -f llama-cpp-gpu)

echo.
echo   - Server active on port %LLAMA_PORT%
echo --------------------------------------------
echo.
