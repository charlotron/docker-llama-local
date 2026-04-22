#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${CYAN}${BOLD}# --- $1 ---${NC}"
}

print_step() { echo -e "${BLUE}  → $1...${NC}"; }
print_success() { echo -e "${GREEN}  ✓ $1${NC}"; }
print_error() { echo -e "${RED}  ! ERROR: $1${NC}"; }
print_info() { echo -e "${YELLOW}  - $1: ${NC}$2"; }

# --- Configuration Loading ---
print_header "LOCAL INFRASTRUCTURE"

if [ -f .env ]; then
    print_step "Loading configuration (.env)"
    set -a
    source .env
    set +a
    print_success "Configuration loaded"
else
    print_error ".env not found"
fi

# Default values
HF_REPO=${HF_REPO:-"Qwen/Qwen2.5-Coder-14B-Instruct-GGUF"}
HF_FILE=${HF_FILE:-"qwen2.5-coder-14b-instruct-q4_k_m.gguf"}
LLAMA_PORT=${LLAMA_PORT:-12345}
COMPOSE_FILE=${COMPOSE_FILE:-"docker/docker-compose-gpu.yml"}

# --- Model Information ---
print_header "MODEL CONFIGURATION"
print_info "Repository" "$HF_REPO"
print_info "File      " "$HF_FILE"
print_info "Port      " "$LLAMA_PORT"

MODEL_DIR="./docker/data/models"
MODEL_PATH="$MODEL_DIR/$HF_FILE"

mkdir -p "$MODEL_DIR"

if [ ! -f "$MODEL_PATH" ]; then
    print_header "DOWNLOAD REQUIRED"
    echo -e "${YELLOW}  The model does not exist locally. Starting download...${NC}"
    DOWNLOAD_URL="https://huggingface.co/$HF_REPO/resolve/main/$HF_FILE"
    
    curl -L "$DOWNLOAD_URL" -o "$MODEL_PATH"
    
    if [ $? -ne 0 ]; then
        print_error "Download failed"
        exit 1
    fi
    print_success "Download complete"
fi

# --- Deployment with Docker ---
print_header "DOCKER DEPLOYMENT"
print_step "Restarting services"

docker compose -f "${COMPOSE_FILE}" down > /dev/null 2>&1
docker compose -f "${COMPOSE_FILE}" up -d

print_step "Waiting for server"

# Simple animated timeout
timeout 300s bash -c 'until docker logs llama-cpp-gpu 2>&1 | grep -q "server is listening on" || docker logs llama-cpp 2>&1 | grep -q "server is listening on"; do echo -n "."; sleep 2; done'
echo ""

print_success "Server active on port $LLAMA_PORT"
echo -e "${CYAN}--------------------------------------------${NC}\n"
