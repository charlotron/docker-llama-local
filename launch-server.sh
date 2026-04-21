#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

echo "🚀 Lanzando llama.cpp con configuración nativa..."
docker compose --env-file .env -f docker/docker-compose.yml down
docker compose --env-file .env -f docker/docker-compose.yml up -d --force-recreate

echo "------------------------------------------------"
echo "🦙 llama-server: http://localhost:${LLAMA_CPP_PORT:-8133}"
echo "📦 Modelo: ${LLAMA_CPP_HF_REPO}"
echo "📄 Archivo: ${LLAMA_CPP_HF_FILE}"
echo "------------------------------------------------"
echo "✅ Servidor relanzado."
echo "💡 Los modelos se guardan en docker/data/"
echo "💡 Sigue el progreso con: docker logs -f llama-cpp"
