#!/bin/bash

# Cargar variables del .env si existe
if [ -f .env ]; then
    echo "📄 Cargando configuración desde .env..."
    set -a
    source .env
    set +a
else
    echo "⚠️ Archivo .env no encontrado. Usando valores por defecto."
fi

# Valores por defecto si no están en .env
HF_REPO=${HF_REPO:-"jackrong/Qwopus3.5-9B-v3-GGUF"}
HF_FILE=${HF_FILE:-"Qwopus3.5-9B-v3.Q4_K_M.gguf"}
LLAMA_CPP_PORT=${LLAMA_CPP_PORT:-12345}

# Ruta de modelos dentro del proyecto
MODEL_DIR="./docker/data/models"
MODEL_PATH="$MODEL_DIR/$HF_FILE"

# Crear directorio de modelos si no existe
mkdir -p "$MODEL_DIR"

# Descarga automática si no existe el modelo
if [ ! -f "$MODEL_PATH" ]; then
    echo "📥 Modelo no encontrado en $MODEL_PATH. Descargando desde HuggingFace..."
    # Construir URL de descarga (HuggingFace)
    # Ejemplo: https://huggingface.co/jackrong/Qwopus3.5-9B-v3-GGUF/resolve/main/Qwopus3.5-9B-v3.Q4_K_M.gguf
    DOWNLOAD_URL="https://huggingface.co/$HF_REPO/resolve/main/$HF_FILE"

    
    curl -L "$DOWNLOAD_URL" -o "$MODEL_PATH"
    
    if [ $? -ne 0 ]; then
        echo "❌ Error al descargar el modelo. Revisa tu conexión o la URL: $DOWNLOAD_URL"
        exit 1
    fi
    echo "✅ Descarga completada."
fi

echo "🚀 Lanzando llama-server en puerto $LLAMA_CPP_PORT con soporte CUDA..."
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d

echo "⏳ Esperando a que el servidor esté listo..."
# Verificamos logs para saber cuando está listo
timeout 300s bash -c 'until docker logs llama-cpp 2>&1 | grep -q "HTTP server listening"; do sleep 2; done'

echo "✅ Servidor listo en puerto $LLAMA_CPP_PORT."
echo "------------------------------------------------"
echo "📡 Endpoint: http://127.0.0.1:$LLAMA_CPP_PORT/v1"
echo "------------------------------------------------"
