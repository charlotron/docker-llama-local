#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "🚀 Iniciando infraestructura de IA Local (Ollama + LiteLLM)..."
docker compose -f docker/docker-compose.yml up -d

echo "------------------------------------------------"
echo "📡 LiteLLM Proxy: http://localhost:${LITELLM_PORT:-4000}"
echo "🦙 Ollama API: http://localhost:${OLLAMA_PORT:-11434}"
echo "------------------------------------------------"
echo "✅ Servidores levantados en segundo plano."
echo "💡 Usa ./ollama-list-downloaded-models.sh para ver el progreso de carga."
