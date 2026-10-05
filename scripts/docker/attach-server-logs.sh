#!/bin/bash

# --- Colors and Aesthetics ---
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

echo -e "\n${CYAN}# --- LLAMA.CPP AUTO-ATTACH LOGS ---${NC}"
echo -e "Waiting for a running container... (Ctrl + C to exit)\n"

# Exit cleanly on Ctrl + C
trap "echo -e '\n${RED}Detached from the logs.${NC}'; exit 0" SIGINT SIGTERM

while true; do
    # Any running llama.cpp container, whatever its profile name
    ACTIVE_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "^llama-cpp" | head -n 1)

    if [ -n "$ACTIVE_CONTAINER" ]; then
        echo -e "${GREEN}✓ Attached to the live logs of: ${ACTIVE_CONTAINER}${NC}\n"
        
        # Follow the logs
        docker logs -f --tail 100 "$ACTIVE_CONTAINER"
        
        echo -e "\n${YELLOW}! Lost the connection to ${ACTIVE_CONTAINER}. Retrying...${NC}"
    else
        printf "\r${YELLOW}⌛ Looking for a running llama.cpp server...${NC}   "
    fi

    sleep 2
done
