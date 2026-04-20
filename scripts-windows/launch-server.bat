@echo off
setlocal enabledelayedexpansion

:: Cargar variables del .env
if exist .env (
    for /f "usebackq tokens=1* delims==" %%a in (`findstr /v "^#" .env`) do (
        set %%a=%%b
    )
)

echo 🚀 Reiniciando infraestructura de IA Local (Ollama + LiteLLM)...
docker compose --env-file .env -f docker/docker-compose.yml down
docker compose --env-file .env -f docker/docker-compose.yml up -d --force-recreate

echo ------------------------------------------------
echo 📡 LiteLLM Proxy: http://localhost:%LITELLM_PORT%
echo 🦙 Ollama API: http://localhost:%OLLAMA_PORT%
echo ------------------------------------------------
echo ✅ Servidores relanzados en segundo plano.
echo 💡 Usa ollama-list-downloaded-models.bat para ver el progreso de carga.
endlocal
