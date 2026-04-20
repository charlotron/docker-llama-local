@echo off
setlocal enabledelayedexpansion

:: Cargar variables del .env
if exist .env (
    for /f "usebackq tokens=1* delims==" %%a in (`findstr /v "^#" .env`) do (
        set %%a=%%b
    )
)

:: Configurar variables para redirigir Claude Code a LiteLLM
if "%LITELLM_PORT%"=="" set LITELLM_PORT=4000
set ANTHROPIC_BASE_URL=http://localhost:%LITELLM_PORT%
set ANTHROPIC_API_KEY=sk-dummy-key

echo 🤖 Iniciando Claude Code apuntando a Ollama (%ANTHROPIC_BASE_URL%)...
echo ------------------------------------------------

:: Ejecutar claude con todos los argumentos pasados al script
claude %*
endlocal
