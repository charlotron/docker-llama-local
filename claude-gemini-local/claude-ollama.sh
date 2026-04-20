#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configurar variables para redirigir Claude Code a LiteLLM
export ANTHROPIC_BASE_URL="http://localhost:${LITELLM_PORT:-4000}"
export ANTHROPIC_API_KEY="sk-dummy-key"

echo "🤖 Iniciando Claude Code apuntando a Ollama ($ANTHROPIC_BASE_URL)..."
echo "------------------------------------------------"

# Ejecutar claude con todos los argumentos pasados al script
exec claude "$@"
