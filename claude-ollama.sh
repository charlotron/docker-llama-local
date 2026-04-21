#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Apuntar al Proxy de LiteLLM (Puerto 4000)
export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_API_KEY="sk-dummy-key"

echo "🤖 Iniciando Claude Code vía LiteLLM ($ANTHROPIC_BASE_URL)..."
echo "------------------------------------------------"

# Ejecutar claude de forma normal. 
# Dejamos que use su modelo por defecto (Sonnet) y LiteLLM lo mapeará.
exec claude "$@"
