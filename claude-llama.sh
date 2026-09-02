#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${MAGENTA}${BOLD}# $1${NC}"
    echo -e "${MAGENTA}--------------------------------------------${NC}"
}

print_info() { echo -e "  ${CYAN}- $1:${NC} $2"; }

# --- Configuration Loading ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
elif [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration
HOST=${LLAMA_HOST:-gpu-host}
PORT=${LLAMA_PORT:-12345}
MODEL="claude_local"

export ANTHROPIC_BASE_URL="http://$HOST:$PORT"
export ANTHROPIC_API_KEY="sk-local"
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0

print_header "CLAUDE CODE LOCAL"
print_info "Host " "$ANTHROPIC_BASE_URL"
print_info "Model" "$ANTHROPIC_MODEL"
echo -e "\n  ${YELLOW}! Press Ctrl+C to exit${NC}"
echo -e "${MAGENTA}--------------------------------------------${NC}\n"

# Execution
SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == *"yolo"* ]]; then
    claude --model "$ANTHROPIC_MODEL" --dangerously-skip-permissions "$@"
else
    claude --model "$ANTHROPIC_MODEL" "$@"
fi
