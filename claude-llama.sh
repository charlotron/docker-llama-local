#!/bin/bash

# Cargar variables del .env si existe
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuración para Claude Code con el alias específico
PORT=${LLAMA_CPP_PORT:-12345}
MODEL=${LLAMA_MODEL_ALIAS:-"claude_local"}

export ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT"
export ANTHROPIC_API_KEY="sk-local"
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0

echo "🚀 Iniciando Claude Code"
echo "📡 Conectando a: $ANTHROPIC_BASE_URL"
echo "🤖 Modelo: $ANTHROPIC_MODEL"
echo "------------------------------------------------"

claude --model "$ANTHROPIC_MODEL" --dangerously-skip-permissions "$@"
