@echo off
SETLOCAL EnableDelayedExpansion

:: Cargar variables de .env
if exist .env (
    for /f "tokens=*" %%a in ('type .env ^| findstr /v "^#"') do (
        set "%%a"
    )
)

echo 🚀 Reiniciando infraestructura de IA Local (llama.cpp)...
docker compose --env-file .env -f docker/docker-compose.yml down
docker compose --env-file .env -f docker/docker-compose.yml up -d --force-recreate

echo ------------------------------------------------
echo 🦙 llama-server: http://localhost:%LLAMA_CPP_PORT%
echo 📦 Modelo: %LLAMA_CPP_MODEL_HF%
echo ------------------------------------------------
echo ✅ Servidor relanzado en segundo plano.
echo 💡 El modelo se descargara automaticamente si no existe en %LLAMA_CPP_MODELS_PATH%.
echo 💡 Puedes ver los logs con: docker logs -f llama-cpp
pause
