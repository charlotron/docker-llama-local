#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "🚀 Reiniciando infraestructura de IA Local (Ollama + LiteLLM)..."
docker compose --env-file .env -f docker/docker-compose.yml down
docker compose --env-file .env -f docker/docker-compose.yml up -d --force-recreate

echo "------------------------------------------------"
echo "📡 LiteLLM Proxy: http://localhost:${LITELLM_PORT:-4000}"
echo "🦙 Ollama API: http://localhost:${OLLAMA_PORT:-11434}"
echo "------------------------------------------------"
echo "✅ Servidores relanzados en segundo plano."
echo "💡 Usa ./ollama-list-downloaded-models.sh para ver el progreso de carga."
