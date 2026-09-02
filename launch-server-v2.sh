#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() { printf "\n%b# --- %s ---%b\n" "${BOLD}${BLUE}" "$1" "${NC}"; }
print_step() { printf "  → %s...\n" "$1"; }
print_success() { printf "  %b✓%b %s\n" "${GREEN}" "${NC}" "$1"; }
print_error() { printf "  %b! ERROR:%b %s\n" "${RED}" "${NC}" "$1"; }
print_info() { printf "  - %s: %s\n" "$1" "$2"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR" || exit 1

print_header "LOCAL INFRASTRUCTURE (V2)"

ENV_FILE=".env.v2"

if [ -f "$ENV_FILE" ]; then
    print_step "Loading configuration ($ENV_FILE)"
    set -a
    source "$ENV_FILE"
    set +a
    print_success "Configuration loaded"
else
    print_error "$ENV_FILE not found"
    exit 1
fi

HF_REPO=${HF_REPO:-"unsloth/Qwen3.6-35B-A3B-GGUF"}
HF_FILE=${HF_FILE:-"Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"}
LLAMA_PORT=${LLAMA_PORT:-12345}
LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
COMPOSE_FILE=${COMPOSE_FILE:-"docker/docker-compose-gpu-v2.yml"}
MODEL_DIR="${MODELS_DIR:-/home/<user>/data/llama-models}"

FILE_NAME=$(basename "$HF_FILE")
MODEL_PATH="$MODEL_DIR/$FILE_NAME"

export TARGET_MODEL_FILE="$FILE_NAME"

print_header "MODEL CONFIGURATION (V2)"
print_info "Repository" "$HF_REPO"
print_info "Remote Path" "$HF_FILE"
print_info "Local File " "$MODEL_PATH"
print_info "Port      " "$LLAMA_PORT"

mkdir -p "$MODEL_DIR"

DOWNLOAD_URL="https://huggingface.co/$HF_REPO/resolve/main/$HF_FILE?download=true"

# --- 1. Obtener tamaño exacto del archivo remoto en Hugging Face ---
print_step "Consultando tamaño remoto del modelo en Hugging Face"

REMOTE_SIZE=$(curl -sIL --http1.1 "$DOWNLOAD_URL" | grep -i "^content-length:" | tail -n 1 | awk '{print $2}' | tr -d '\r')

if [ -z "$REMOTE_SIZE" ] || ! [[ "$REMOTE_SIZE" =~ ^[0-9]+$ ]]; then
    print_error "No se pudo obtener el tamaño del archivo remoto. Revisa la conexion o la URL."
    exit 1
fi

REMOTE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $REMOTE_SIZE/1073741824}")
print_info "Tamaño remoto esperado" "${REMOTE_SIZE_GB} GB (${REMOTE_SIZE} bytes)"

# --- 2. Bucle de descarga y reanudacion estricta ---
MAX_ATTEMPTS=20
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    LOCAL_SIZE=0
    if [ -f "$MODEL_PATH" ]; then
        LOCAL_SIZE=$(stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
    fi

    # Verificar si los bytes coinciden exactamente
    if [ "$LOCAL_SIZE" -eq "$REMOTE_SIZE" ]; then
        # Verificar header GGUF por seguridad adicional
        HEADER=$(head -c 4 "$MODEL_PATH" 2>/dev/null)
        if [ "$HEADER" = "GGUF" ]; then
            print_success "El archivo local esta completo y verificado (100% descargado y GGUF OK)"
            break
        else
            print_error "El tamaño coincide pero la cabecera no es GGUF. Eliminando..."
            rm -f "$MODEL_PATH"
        fi
    fi

    LOCAL_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $LOCAL_SIZE/1073741824}")
    print_header "DESCARGA EN PROGRESO (Intento $ATTEMPT de $MAX_ATTEMPTS)"
    printf "  %bProgreso local actual: %s GB / %s GB%b\n" "${YELLOW}" "$LOCAL_SIZE_GB" "$REMOTE_SIZE_GB" "${NC}"
    printf "  %bReanudando descarga con HTTP/1.1 y resume activo...%b\n" "${CYAN}" "${NC}"

    # Usar --http1.1 para evitar fallos de streams HTTP/2 en descargas largas
    curl -L --http1.1 -C - \
        --retry 10 \
        --retry-delay 5 \
        --retry-connrefused \
        --connect-timeout 20 \
        --progress-bar \
        "$DOWNLOAD_URL" -o "$MODEL_PATH"

    CURL_EXIT=$?

    LOCAL_SIZE=$(stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
    if [ "$LOCAL_SIZE" -eq "$REMOTE_SIZE" ]; then
        print_success "Descarga completada al 100%"
        break
    else
        printf "\n%b! La descarga se corto antes de completar los %s GB. Reintentando automáticamente en 5s...%b\n" "${RED}" "$REMOTE_SIZE_GB" "${NC}"
        sleep 5
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

if [ $(stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0) -ne "$REMOTE_SIZE" ]; then
    print_error "No se logro completar la descarga tras $MAX_ATTEMPTS intentos."
    exit 1
fi

# --- 3. Despliegue con Docker ---
print_header "DOCKER DEPLOYMENT (V2)"
print_step "Restarting services"

docker stop llama-cpp-gpu llama-cpp-gpu-v2 > /dev/null 2>&1
docker compose --env-file "$ENV_FILE" -f "${COMPOSE_FILE}" down > /dev/null 2>&1
docker compose --env-file "$ENV_FILE" -f "${COMPOSE_FILE}" up -d

print_step "Starting server and checking startup logs"
printf "%b--------------------------------------------%b\n" "${CYAN}" "${NC}"

CONTAINER_NAME="llama-cpp-gpu-v2"
TIMEOUT=300
ELAPSED=0

READY_FILE="/tmp/llama_v2_ready_flag"
rm -f "$READY_FILE"

docker logs -f "$CONTAINER_NAME" 2>&1 | while read -r line; do
    echo "$line"
    if echo "$line" | grep -q "server is listening on"; then
        touch "$READY_FILE"
        pkill -P $$ docker 2>/dev/null
        break
    fi
done &

LOG_PID=$!

while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f "$READY_FILE" ]; then
        rm -f "$READY_FILE"
        break
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        printf "\n%b! ERROR: El contenedor se ha detenido inesperadamente.%b\n" "${RED}" "${NC}"
        print_error "Revisa las ultimas lineas de error impresas arriba."
        kill $LOG_PID 2>/dev/null
        rm -f "$READY_FILE"
        exit 1
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    kill $LOG_PID 2>/dev/null
    rm -f "$READY_FILE"
    print_error "Tiempo de espera agotado ($TIMEOUTs)."
    exit 1
fi

printf "%b--------------------------------------------%b\n" "${CYAN}" "${NC}"
print_success "Server V2 active on http://$LLAMA_HOST:$LLAMA_PORT"
printf "%b--------------------------------------------%b\n\n" "${CYAN}" "${NC}"
