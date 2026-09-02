#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n# --- $1 ---"
}

print_step() { echo -e "  → $1..."; }
print_success() { echo -e "  ✓ $1"; }
print_info() { echo -e "  - $1"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

print_header "STOPPING ALL LLAMA.CPP SERVERS"

print_step "Stopping active Docker containers"

# Detener los contenedores v1 y v2 si están en ejecución
docker stop llama-cpp-gpu llama-cpp-gpu-v2 > /dev/null 2>&1

# Apagar mediante docker compose usando ambos entornos si están disponibles
if [ -f .env ] && [ -f docker/docker-compose-gpu.yml ]; then
    docker compose --env-file .env -f docker/docker-compose-gpu.yml down > /dev/null 2>&1
fi

if [ -f .env.v2 ] && [ -f docker/docker-compose-gpu-v2.yml ]; then
    docker compose --env-file .env.v2 -f docker/docker-compose-gpu-v2.yml down > /dev/null 2>&1
fi

print_success "All server instances stopped"

# Verificación de recursos liberados
print_header "RESOURCING STATUS"

if command -v nvidia-smi &> /dev/null; then
    VRAM_USAGE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -n 1)
    print_info "VRAM currently used: ${VRAM_USAGE} MiB"
fi

RAM_FREE=$(free -h | awk '/^Mem:/ {print $4}')
print_info "Free System RAM: ${RAM_FREE}"

echo -e "\n${CYAN}--------------------------------------------${NC}\n"
