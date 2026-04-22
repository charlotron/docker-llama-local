#!/bin/bash

# Load variables from .env if it exists
if [ -f .env ]; then
    echo "📄 Loading configuration from .env..."
    set -a
    source .env
    set +a
else
    echo "⚠️ .env file not found. Using default values."
fi

# Default values if not in .env
HF_REPO=${HF_REPO:-"Qwen/Qwen2.5-Coder-14B-Instruct-GGUF"}
HF_FILE=${HF_FILE:-"qwen2.5-coder-14b-instruct-q4_k_m.gguf"}
LLAMA_PORT=${LLAMA_PORT:-12345}

# Model path inside the project
MODEL_DIR="./docker/data/models"
MODEL_PATH="$MODEL_DIR/$HF_FILE"

# Create model directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Automatic download if model doesn't exist
if [ ! -f "$MODEL_PATH" ]; then
    echo "📥 Model not found at $MODEL_PATH. Downloading from HuggingFace..."
    DOWNLOAD_URL="https://huggingface.co/$HF_REPO/resolve/main/$HF_FILE"
    
    curl -L "$DOWNLOAD_URL" -o "$MODEL_PATH"
    
    if [ $? -ne 0 ]; then
        echo "❌ Error downloading the model. Check your connection or the URL: $DOWNLOAD_URL"
        exit 1
    fi
    echo "✅ Download complete."
fi

echo "🚀 Launching llama-server on port $LLAMA_PORT..."
docker compose -f ${COMPOSE_FILE:-docker/docker-compose-gpu.yml} down
docker compose -f ${COMPOSE_FILE:-docker/docker-compose-gpu.yml} up -d

echo "⏳ Waiting for server to be ready..."
# Check logs to know when it's ready
timeout 300s bash -c 'until docker logs llama-cpp-gpu 2>&1 | grep -q "HTTP server listening" || docker logs llama-cpp 2>&1 | grep -q "HTTP server listening"; do sleep 2; done'

echo "✅ Server ready on port $LLAMA_PORT."
echo "------------------------------------------------"
echo "📡 Endpoint: http://127.0.0.1:$LLAMA_PORT/v1"
echo "------------------------------------------------"
