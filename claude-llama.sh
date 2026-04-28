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
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration
HOST=${LLAMA_HOST:-127.0.0.1}
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
claude --model "$ANTHROPIC_MODEL" --dangerously-skip-permissions "$@"
