@echo off
set LLAMA_PORT=12345
set LLAMA_MODEL_FILE=Qwopus3.5-9B-v3.Q4_K_M.gguf
set LLAMA_MODEL_ALIAS=Qwopus3.5-9B

set MODEL_DIR=docker\data\models
set MODEL_PATH=%MODEL_DIR%\%LLAMA_MODEL_FILE%

if not exist "%MODEL_DIR%" mkdir "%MODEL_DIR%"

if not exist "%MODEL_PATH%" (
    echo 📥 Descargando modelo...
    powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/jackrong/Qwopus3.5-9B-v3-GGUF/resolve/main/%LLAMA_MODEL_FILE%' -OutFile '%MODEL_PATH%'"
)

echo 🚀 Lanzando llama-server...
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d

echo ⏳ Esperando... verifica con: docker logs -f llama-cpp
pause
