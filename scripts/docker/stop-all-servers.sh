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
cd "$SCRIPT_DIR/../.." || exit 1

print_header "STOPPING ALL LLAMA.CPP SERVERS"

print_step "Stopping active Docker containers"

# Stop active containers if running
docker stop llama-cpp-gpu llama-cpp-gpu-qwen-27b llama-cpp-gpu-gpt-oss-20b llama-cpp > /dev/null 2>&1

# Shut down with docker compose using active configurations
if [ -f .env ] && [ -f docker/docker-compose-gpu-qwen-35b-a3b-mtp.yml ]; then
    docker compose --env-file .env -f docker/docker-compose-gpu-qwen-35b-a3b-mtp.yml down > /dev/null 2>&1
fi

if [ -f .env ] && [ -f docker/docker-compose-gpu-qwen-27b.yml ]; then
    docker compose --env-file .env -f docker/docker-compose-gpu-qwen-27b.yml down > /dev/null 2>&1
fi

if [ -f .env ] && [ -f docker/docker-compose-gpu-gpt-oss-20b.yml ]; then
    docker compose --env-file .env -f docker/docker-compose-gpu-gpt-oss-20b.yml down > /dev/null 2>&1
fi

if [ -f docker/docker-compose-cpu.yml ]; then
    docker compose -f docker/docker-compose-cpu.yml down > /dev/null 2>&1
fi

print_success "All server instances stopped"

# Resource status check
print_header "RESOURCING STATUS"

if command -v nvidia-smi &> /dev/null; then
    VRAM_USAGE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -n 1)
    print_info "VRAM currently used: ${VRAM_USAGE} MiB"
fi

if command -v free &> /dev/null; then
    RAM_FREE=$(free -h | awk '/^Mem:/ {print $4}')
    print_info "Free System RAM: ${RAM_FREE}"
fi

echo -e "\n${CYAN}--------------------------------------------${NC}\n"
