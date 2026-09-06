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
cd "$SCRIPT_DIR/../.." || exit 1

if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration
export LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
export LLAMA_PORT=${LLAMA_PORT:-12345}
export MODEL="llama-local/llama-local"

# Define the temporary path for opencode.json dynamically using system temporary path
export OPENCODE_CONFIG="${TMPDIR:-/tmp}/opencode.json"

# Generate the opencode.json dynamically inside the system temporary folder to keep the workspace spotless
cat <<EOF > "$OPENCODE_CONFIG"
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "llama-local/llama-local",
  "provider": {
    "llama-local": {
      "npm": "@ai-sdk/anthropic",
      "name": "Llama.cpp Local Server",
      "options": {
        "baseURL": "http://{env:LLAMA_HOST}:{env:LLAMA_PORT}/v1",
        "apiKey": "sk-local"
      },
      "models": {
        "llama-local": {
          "name": "${HF_FILE:-llama-local}"
        }
      }
    }
  }
}
EOF

# Ensure the temporary opencode.json is cleaned up automatically on exit from the temporary directory
trap 'rm -f "$OPENCODE_CONFIG"' EXIT SIGINT SIGTERM

print_header "OPENCODE LOCAL CLIENT"
print_info "Host " "http://$LLAMA_HOST:$LLAMA_PORT"
print_info "Alias" "$MODEL"
print_info "File " "${HF_FILE:-Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
echo -e "\n  ${YELLOW}! Press Ctrl+C to exit${NC}"
echo -e "${MAGENTA}--------------------------------------------${NC}\n"

# Execution
SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == *"yolo"* ]]; then
    opencode "$@" --model "$MODEL" --auto
else
    opencode "$@" --model "$MODEL"
fi
