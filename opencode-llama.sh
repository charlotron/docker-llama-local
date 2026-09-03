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
export LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
export LLAMA_PORT=${LLAMA_PORT:-12345}
export MODEL="claude_local/claude_local"

# Generate the opencode.json dynamically with resolved variables to avoid invalid URL errors
cat <<EOF > "$SCRIPT_DIR/opencode.json"
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "claude_local/claude_local",
  "provider": {
    "claude_local": {
      "npm": "@ai-sdk/anthropic",
      "name": "Llama.cpp Local Server",
      "options": {
        "baseURL": "http://{env:LLAMA_HOST}:{env:LLAMA_PORT}/v1",
        "apiKey": "sk-local"
      },
      "models": {
        "claude_local": {
          "name": "Qwen 3.6 35B"
        }
      }
    }
  }
}
EOF

print_header "OPENCODE LOCAL (QWEN 3.6)"
print_info "Host " "http://$LLAMA_HOST:$LLAMA_PORT"
print_info "Model" "$MODEL"
echo -e "\n  ${YELLOW}! Press Ctrl+C to exit${NC}"
echo -e "${MAGENTA}--------------------------------------------${NC}\n"

# Execution
SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == *"yolo"* ]]; then
    opencode "$@" --model "$MODEL" --auto
else
    opencode "$@" --model "$MODEL"
fi
