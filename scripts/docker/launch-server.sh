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

# --- Dependency checks ---
# Fail here, naming what is missing and how to get it, rather than letting the
# command fail later with "command not found" -- which says nothing about what
# the script actually needed.
require_cmd() {
    if ! command -v "$1" &> /dev/null; then
        printf "\n  %b! %s is not installed.%b %s\n\n" "${RED}" "$1" "${NC}" "$2" >&2
        exit 1
    fi
}

require_docker() {
    require_cmd docker "Install Docker Desktop: https://docs.docker.com/get-docker/"
    if ! docker info &> /dev/null; then
        printf "\n  %b! Docker is installed but not running.%b Start it and try again.\n\n" "${RED}" "${NC}" >&2
        exit 1
    fi
}

require_docker
require_cmd curl "Install it with your package manager."

# Resolve symlinks before working out where this script lives, so it behaves the
# same however it is reached: by relative path, by absolute path, or through a
# symlink from a directory on PATH. dirname of a symlink gives the directory of
# the link, not of the script, which would send every path below to the wrong
# place.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    LINK_DIR="$( cd -P "$( dirname "$SOURCE" )" &> /dev/null && pwd )"
    SOURCE="$( readlink "$SOURCE" )"
    [[ "$SOURCE" != /* ]] && SOURCE="$LINK_DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" &> /dev/null && pwd )"
INVOCATION_DIR="$PWD"
cd "$SCRIPT_DIR/../.." || exit 1

print_header "LOCAL INFRASTRUCTURE"

# Allow custom environment file as first argument, default to .env. A relative
# path is resolved against the directory the user ran the command from, not the
# project root we just moved to -- otherwise `launch-server.sh my.env` would
# quietly look for a different file than the one sitting next to the user.
ENV_FILE="${1:-.env}"
if [ -n "$1" ] && [[ "$ENV_FILE" != /* ]]; then
    ENV_FILE="$INVOCATION_DIR/$ENV_FILE"
fi

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

# Set defaults
HF_REPO=${HF_REPO:-"unsloth/Qwen3.6-35B-A3B-GGUF"}
HF_FILE=${HF_FILE:-"Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"}
LLAMA_PORT=${LLAMA_PORT:-12345}
LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
COMPOSE_FILE=${COMPOSE_FILE:-"docker/docker-compose-gpu-qwen-35b-a3b-mtp.yml"}

# Determine container name and default models folder based on compose file
if [[ "$COMPOSE_FILE" == *"cpu"* ]]; then
    CONTAINER_NAME="llama-cpp"
    MODEL_DIR="${MODELS_DIR:-./docker/data/models}"
else
    CONTAINER_NAME="llama-cpp-gpu"
    MODEL_DIR="${MODELS_DIR:-./docker/data/models}"
fi

FILE_NAME=$(basename "$HF_FILE")
MODEL_PATH="$MODEL_DIR/$FILE_NAME"

export TARGET_MODEL_FILE="$FILE_NAME"

print_header "MODEL CONFIGURATION"
print_info "Repository" "$HF_REPO"
print_info "Remote Path" "$HF_FILE"
print_info "Local File " "$MODEL_PATH"
print_info "Port      " "$LLAMA_PORT"

mkdir -p "$MODEL_DIR"

DOWNLOAD_URL="https://huggingface.co/$HF_REPO/resolve/main/$HF_FILE?download=true"

# --- 1. Get remote file size from Hugging Face ---
print_step "Consulting remote model size on Hugging Face"

# Try getting size
REMOTE_SIZE=$(curl -sIL --http1.1 "$DOWNLOAD_URL" | grep -i "^content-length:" | tail -n 1 | awk '{print $2}' | tr -d '\r')

if [ -z "$REMOTE_SIZE" ] || ! [[ "$REMOTE_SIZE" =~ ^[0-9]+$ ]]; then
    print_error "Could not retrieve remote file size. Check connection or URL."
    exit 1
fi

REMOTE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $REMOTE_SIZE/1073741824}")
print_info "Expected Remote Size" "${REMOTE_SIZE_GB} GB (${REMOTE_SIZE} bytes)"

# --- 2. Strict download and resume loop ---
MAX_ATTEMPTS=20
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    LOCAL_SIZE=0
    if [ -f "$MODEL_PATH" ]; then
        LOCAL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
    fi

    # Check if bytes match exactly
    if [ "$LOCAL_SIZE" -eq "$REMOTE_SIZE" ]; then
        # Verify GGUF header
        HEADER=$(head -c 4 "$MODEL_PATH" 2>/dev/null)
        if [ "$HEADER" = "GGUF" ]; then
            print_success "Local file is complete and verified (100% downloaded & GGUF OK)"
            break
        else
            print_error "Size matches but header is not GGUF. Removing..."
            rm -f "$MODEL_PATH"
        fi
    fi

    LOCAL_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $LOCAL_SIZE/1073741824}")
    print_header "DOWNLOAD IN PROGRESS (Attempt $ATTEMPT of $MAX_ATTEMPTS)"
    printf "  %bCurrent local progress: %s GB / %s GB%b\n" "${YELLOW}" "$LOCAL_SIZE_GB" "$REMOTE_SIZE_GB" "${NC}"
    printf "  %bResuming download with HTTP/1.1 and resume active...%b\n" "${CYAN}" "${NC}"

    # Use --http1.1 to prevent HTTP/2 stream failures during large downloads
    curl -L --http1.1 -C - \
        --retry 10 \
        --retry-delay 5 \
        --retry-connrefused \
        --connect-timeout 20 \
        --progress-bar \
        "$DOWNLOAD_URL" -o "$MODEL_PATH"

    CURL_EXIT=$?

    LOCAL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
    if [ "$LOCAL_SIZE" -eq "$REMOTE_SIZE" ]; then
        print_success "Download completed 100%"
        break
    else
        printf "\n%b! Download cut off before completing the %s GB. Retrying automatically in 5s...%b\n" "${RED}" "$REMOTE_SIZE_GB" "${NC}"
        sleep 5
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

FINAL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)
if [ "$FINAL_SIZE" -ne "$REMOTE_SIZE" ]; then
    print_error "Failed to complete download after $MAX_ATTEMPTS attempts."
    exit 1
fi

# --- 3. Docker Deployment ---
print_header "DOCKER DEPLOYMENT"
print_step "Restarting services"

# Stop active containers first to avoid conflicts
docker stop llama-cpp llama-cpp-gpu llama-cpp-gpu-qwen-27b > /dev/null 2>&1
docker compose --env-file "$ENV_FILE" -f "${COMPOSE_FILE}" down > /dev/null 2>&1
docker compose --env-file "$ENV_FILE" -f "${COMPOSE_FILE}" up -d

print_step "Starting server and checking startup logs"
printf "%b--------------------------------------------%b\n" "${CYAN}" "${NC}"

TIMEOUT=300
ELAPSED=0

READY_FILE="${TMPDIR:-/tmp}/llama_ready_flag"
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
        printf "\n%b! ERROR: Container stopped unexpectedly.%b\n" "${RED}" "${NC}"
        print_error "Check the error logs printed above."
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
    print_error "Timeout reached ($TIMEOUTs)."
    exit 1
fi

printf "%b--------------------------------------------%b\n" "${CYAN}" "${NC}"
print_success "Server active on http://$LLAMA_HOST:$LLAMA_PORT"
printf "%b--------------------------------------------%b\n\n" "${CYAN}" "${NC}"
