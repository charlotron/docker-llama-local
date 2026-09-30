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

# Which model and which compose file to run are never guessed: a baked-in
# default silently launches something other than the profile the env file
# describes, and it rots as soon as that model or compose file is removed.
for required in HF_REPO HF_FILE COMPOSE_FILE; do
    if [ -z "${!required}" ]; then
        print_error "$required is not set in $ENV_FILE"
        exit 1
    fi
done

# Set defaults
LLAMA_PORT=${LLAMA_PORT:-12345}
LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}

# Determine container name and default models folder based on compose file.
# The container name is read directly from the compose file's own
# `container_name:` line rather than guessed, since GPU profiles other than
# the 35B default use profile-specific names (e.g. llama-cpp-gpu-qwen3.8-27b-ud-q2-k-xl)
# -- a hardcoded guess here previously caused the script to attach to the
# wrong container name and falsely report "Container stopped unexpectedly"
# even when the real container was running and healthy.
MODEL_DIR="${MODELS_DIR:-./docker/data/models}"
mkdir -p "$MODEL_DIR"
# Resolve to an absolute path and export it as MODELS_DIR so the compose
# file's volume mount sees the same directory we just downloaded into.
# Compose resolves a relative ${MODELS_DIR} against the directory of the
# compose file itself (e.g. docker/), not the repo root this script cd'd
# into -- left relative, "./docker/data/models" doubles up into
# docker/docker/data/models and the container can't find the model.
MODEL_DIR="$(cd "$MODEL_DIR" && pwd)"
export MODELS_DIR="$MODEL_DIR"
if [ -f "$COMPOSE_FILE" ]; then
    CONTAINER_NAME=$(grep -m1 'container_name:' "$COMPOSE_FILE" | sed 's/.*container_name:[[:space:]]*//')
fi
if [ -z "$CONTAINER_NAME" ]; then
    if [[ "$COMPOSE_FILE" == *"cpu"* ]]; then
        CONTAINER_NAME="llama-cpp"
    else
        CONTAINER_NAME="llama-cpp-gpu"
    fi
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

# Downloads one file from a HF repo with strict resume/verify, retrying until
# the local file matches the remote byte count and has a valid GGUF header.
# Factored out so multimodal profiles can fetch a second file (the mmproj
# vision projector) with the same rigor as the main model, instead of
# duplicating this whole retry loop inline.
download_gguf() {
    local repo="$1" remote_file="$2" local_path="$3"
    local download_url="https://huggingface.co/$repo/resolve/main/$remote_file?download=true"

    print_step "Consulting remote file size on Hugging Face ($remote_file)"
    local remote_size
    remote_size=$(curl -sIL --http1.1 "$download_url" | grep -i "^content-length:" | tail -n 1 | awk '{print $2}' | tr -d '\r')

    if [ -z "$remote_size" ] || ! [[ "$remote_size" =~ ^[0-9]+$ ]]; then
        print_error "Could not retrieve remote file size for $remote_file. Check connection or URL."
        exit 1
    fi

    local remote_size_gb
    remote_size_gb=$(awk "BEGIN {printf \"%.2f\", $remote_size/1073741824}")
    print_info "Expected Remote Size" "${remote_size_gb} GB (${remote_size} bytes)"

    local max_attempts=20 attempt=1 local_size
    while [ $attempt -le $max_attempts ]; do
        local_size=0
        if [ -f "$local_path" ]; then
            local_size=$(stat -f%z "$local_path" 2>/dev/null || stat -c%s "$local_path" 2>/dev/null || echo 0)
        fi

        if [ "$local_size" -eq "$remote_size" ]; then
            local header
            header=$(head -c 4 "$local_path" 2>/dev/null)
            if [ "$header" = "GGUF" ]; then
                print_success "Local file is complete and verified (100% downloaded & GGUF OK)"
                return 0
            else
                print_error "Size matches but header is not GGUF. Removing..."
                rm -f "$local_path"
            fi
        fi

        local local_size_gb
        local_size_gb=$(awk "BEGIN {printf \"%.2f\", $local_size/1073741824}")
        print_header "DOWNLOAD IN PROGRESS (Attempt $attempt of $max_attempts) - $remote_file"
        printf "  %bCurrent local progress: %s GB / %s GB%b\n" "${YELLOW}" "$local_size_gb" "$remote_size_gb" "${NC}"
        printf "  %bResuming download with HTTP/1.1 and resume active...%b\n" "${CYAN}" "${NC}"

        curl -L --http1.1 -C - \
            --retry 10 \
            --retry-delay 5 \
            --retry-connrefused \
            --connect-timeout 20 \
            --progress-bar \
            "$download_url" -o "$local_path"

        local_size=$(stat -f%z "$local_path" 2>/dev/null || stat -c%s "$local_path" 2>/dev/null || echo 0)
        if [ "$local_size" -eq "$remote_size" ]; then
            print_success "Download completed 100%"
            return 0
        else
            printf "\n%b! Download cut off before completing the %s GB. Retrying automatically in 5s...%b\n" "${RED}" "$remote_size_gb" "${NC}"
            sleep 5
            attempt=$((attempt + 1))
        fi
    done

    local final_size
    final_size=$(stat -f%z "$local_path" 2>/dev/null || stat -c%s "$local_path" 2>/dev/null || echo 0)
    if [ "$final_size" -ne "$remote_size" ]; then
        print_error "Failed to complete download of $remote_file after $max_attempts attempts."
        exit 1
    fi
}

download_gguf "$HF_REPO" "$HF_FILE" "$MODEL_PATH"

# Optional second file: the mmproj (vision projector) needed by multimodal
# profiles (e.g. alternatives/.env.gpu.qwen2.5-vl-7b.sample). Only fetched if HF_MMPROJ_FILE
# is set -- text-only profiles leave it unset and this is skipped entirely.
if [ -n "$HF_MMPROJ_FILE" ]; then
    MMPROJ_FILE_NAME=$(basename "$HF_MMPROJ_FILE")
    MMPROJ_PATH="$MODEL_DIR/$MMPROJ_FILE_NAME"
    export TARGET_MMPROJ_FILE="$MMPROJ_FILE_NAME"
    print_info "MMProj Repo" "${HF_MMPROJ_REPO:-$HF_REPO}"
    print_info "MMProj Path" "$HF_MMPROJ_FILE"
    download_gguf "${HF_MMPROJ_REPO:-$HF_REPO}" "$HF_MMPROJ_FILE" "$MMPROJ_PATH"
fi

# --- 3. Docker Deployment ---
print_header "DOCKER DEPLOYMENT"
print_step "Restarting services"

# Stop every running llama.cpp container first, whatever its profile: they all
# bind the same port. Matching the "llama-cpp" name prefix instead of listing
# names keeps this correct when a profile's container_name changes.
RUNNING=$(docker ps -q --filter "name=^llama-cpp")
[ -n "$RUNNING" ] && docker stop $RUNNING > /dev/null 2>&1
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
