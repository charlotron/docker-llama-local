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

# --- Models directory from .env, or the default ---
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

MODELS_DIR="./docker/data/models"

if [ -f .env ]; then
    source .env
fi

MODELS_DIR="${MODELS_DIR:-./docker/data/models}"

print_header "CLEANUP LOCAL MODELS"
echo -e "Directory: ${CYAN}${MODELS_DIR}${NC}\n"

if [ ! -d "$MODELS_DIR" ]; then
    echo -e "${RED}! Directory does not exist.${NC}"
    exit 1
fi

# --- Buscar archivos .gguf ---
mapfile -t FILES < <(find "$MODELS_DIR" -type f -name "*.gguf" -exec du -h {} +)

if [ ${#FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}No .gguf models found in this directory.${NC}\n"
    exit 0
fi

# --- Mostrar lista numerada de modelos ---
echo -e "${BOLD}Select a model to delete:${NC}\n"

i=1
declare -A FILE_PATHS
for line in "${FILES[@]}"; do
    SIZE=$(echo "$line" | awk '{print $1}')
    PATH_NAME=$(echo "$line" | cut -f2-)
    FILE_NAME=$(basename "$PATH_NAME")
    
    FILE_PATHS[$i]="$PATH_NAME"
    echo -e "  [${CYAN}$i${NC}] ${BOLD}$FILE_NAME${NC} (${YELLOW}$SIZE${NC})"
    ((i++))
done

echo -e "  [${RED}0${NC}] Exit (Cancel)"
echo ""

# --- Entrada de usuario ---
read -p "Enter option number: " CHOICE

if [[ "$CHOICE" == "0" ]] || [[ -z "$CHOICE" ]]; then
    echo -e "\n${YELLOW}Operation canceled.${NC}\n"
    exit 0
fi

SELECTED_FILE="${FILE_PATHS[$CHOICE]}"

if [ -n "$SELECTED_FILE" ] && [ -f "$SELECTED_FILE" ]; then
    FILE_NAME=$(basename "$SELECTED_FILE")
    SIZE=$(du -h "$SELECTED_FILE" | awk '{print $1}')
    
    echo ""
    read -p "Are you sure you want to delete '$FILE_NAME' ($SIZE)? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm -f "$SELECTED_FILE"
        echo -e "\n${GREEN}✓ File '$FILE_NAME' successfully deleted (${SIZE} freed).${NC}\n"
    else
        echo -e "\n${YELLOW}Deletion canceled.${NC}\n"
    fi
else
    echo -e "\n${RED}! Invalid option.${NC}\n"
fi
