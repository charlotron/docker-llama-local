#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${MAGENTA}${BOLD}# $1${NC}"
    echo -e "${MAGENTA}--------------------------------------------${NC}"
}

print_info() { echo -e "  ${CYAN}- $1:${NC} $2"; }

# Ask the running server which model it is actually serving. The GGUF name on
# disk is authoritative only there -- env vars describe intent, not reality.
resolve_model_name() {
    local props
    props=$(curl -s -m 5 "http://$1:$2/props" 2>/dev/null) || true
    local path
    path=$(printf '%s' "$props" | sed -n 's/.*"model_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -n "$path" ]]; then
        basename "$path" .gguf
    else
        echo "unknown (server unreachable)"
    fi
}

# --- Configuration Loading ---
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

require_cmd opencode "Install it with: brew install opencode  (or: npm install -g opencode-ai)"

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

if [ -f "$SCRIPT_DIR/../../.env" ]; then
    set -a
    source "$SCRIPT_DIR/../../.env"
    set +a
fi

# Configuration
export LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
export LLAMA_PORT=${LLAMA_PORT:-12345}
export MODEL="llama-local/llama-local"

# Define the maximum tokens to generate per single response (output limit)
export LLAMA_OUTPUT_LIMIT=32768

# Dynamically calculate the compaction buffer (output limit + 1000 tokens)
export LLAMA_COMPACT_BUFFER=$((LLAMA_OUTPUT_LIMIT + 1000))

# Dynamically calculate the keep tokens window size (double the output limit)
export LLAMA_COMPACT_KEEP=$((LLAMA_OUTPUT_LIMIT * 2))

print_header "RESOLVING LLAMA.CPP CONFIGURATION"
printf "  ${CYAN}- Querying Llama.cpp slots API on http://$LLAMA_HOST:$LLAMA_PORT...${NC}\r"

# Query the active context size dynamically from the llama-server slots endpoint with 3s timeout
DETECTED_CTX=$(curl -s --max-time 3 "http://$LLAMA_HOST:$LLAMA_PORT/slots" | jq '.[0].n_ctx' 2>/dev/null || echo "null")

if [[ "$DETECTED_CTX" =~ ^[0-9]+$ ]]; then
    export LLAMA_CONTEXT_SIZE=$DETECTED_CTX
    printf "  ${GREEN}✓ Successfully autodetected context window size: ${BOLD}${LLAMA_CONTEXT_SIZE} tokens${NC}\n"
else
    export LLAMA_CONTEXT_SIZE=${LLAMA_CONTEXT_SIZE:-131072}
    printf "  ${YELLOW}! Server slots API unreachable. Falling back to configured context size: ${BOLD}${LLAMA_CONTEXT_SIZE} tokens${NC}\n"
fi

# Define the temporary path for opencode.json dynamically using system temporary path
export OPENCODE_CONFIG="${TMPDIR:-/tmp}/opencode.json"

# Merge the global opencode.json with dynamic settings to avoid losing MCPs and plugins
printf "  ${CYAN}- Merging system opencode.json with local server configuration...${NC}\n"
node -e "
const fs = require('fs');
const path = require('path');

const globalConfigPath = path.join(process.env.HOME, '.config', 'opencode', 'opencode.json');
let baseConfig = {};

if (fs.existsSync(globalConfigPath)) {
  try {
    const raw = fs.readFileSync(globalConfigPath, 'utf8').trim();
    if (raw) {
      baseConfig = JSON.parse(raw);
    }
  } catch (e) {
    console.error('Warning: Failed to parse global opencode.json:', e.message);
  }
}

// Resolve the live model name from the server, falling back to the generic
// alias only if the server cannot be reached.
const MODEL_NAME = (() => {
  try {
    // No template literals here: this whole block lives inside a
    // double-quoted 'node -e' string, so bash would expand them itself.
    const r = require('child_process')
      .execSync('curl -s -m 5 http://' + process.env.LLAMA_HOST +
                ':' + process.env.LLAMA_PORT + '/props', { encoding: 'utf8' });
    const p = JSON.parse(r).model_path;
    if (p) return p.split('/').pop().replace(/\.gguf$/, '');
  } catch (e) { /* server unreachable: fall through */ }
  return 'llama-local';
})();

const dynamicConfig = {
  'model': 'llama-local/llama-local',
  'autoCompact': true,
  'compaction': {
    'auto': true,
    'keep': { 'tokens': Number(process.env.LLAMA_COMPACT_KEEP) },
    'buffer': Number(process.env.LLAMA_COMPACT_BUFFER)
  },
  'performance': { 'maxConcurrentAgents': 1 },
  'agents': { 'maxConcurrent': 1 },
  'provider': {
    'llama-local': {
      'npm': '@ai-sdk/anthropic',
      'name': 'Llama.cpp Local Server',
      'options': {
        'baseURL': 'http://' + process.env.LLAMA_HOST + ':' + process.env.LLAMA_PORT + '/v1',
        'apiKey': 'sk-local'
      },
      'models': {
        'llama-local': {
          // Ask the server what it is actually serving. Never derive this
          // from HF_FILE: that is only the download target and goes stale the
          // moment a different profile is launched.
          'name': MODEL_NAME,
          'limit': {
            'context': Number(process.env.LLAMA_CONTEXT_SIZE),
            'output': Number(process.env.LLAMA_OUTPUT_LIMIT)
          }
        }
      }
    }
  }
};

function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (source[key] instanceof Object && target[key] instanceof Object) {
      if (Array.isArray(source[key]) && Array.isArray(target[key])) {
        target[key] = Array.from(new Set([...target[key], ...source[key]]));
      } else if (!Array.isArray(source[key]) && !Array.isArray(target[key])) {
        deepMerge(target[key], source[key]);
      } else {
        target[key] = source[key];
      }
    } else {
      target[key] = source[key];
    }
  }
  return target;
}

const mergedConfig = deepMerge(baseConfig, dynamicConfig);

if (!mergedConfig['\$schema']) {
  mergedConfig['\$schema'] = 'https://opencode.ai/config.json';
}

fs.writeFileSync(process.env.OPENCODE_CONFIG, JSON.stringify(mergedConfig, null, 2), 'utf8');
"

# Ensure the temporary opencode.json is cleaned up automatically on exit from the temporary directory
trap 'rm -f "$OPENCODE_CONFIG"' EXIT SIGINT SIGTERM

print_header "OPENCODE LOCAL CLIENT"
print_info "Host " "http://$LLAMA_HOST:$LLAMA_PORT"
print_info "Model" "$(resolve_model_name "$LLAMA_HOST" "$LLAMA_PORT")"
echo -e "\n  ${YELLOW}! Press Ctrl+C to exit${NC}"
echo -e "${MAGENTA}--------------------------------------------${NC}\n"

# Execution
SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == *"yolo"* ]]; then
    opencode "$@" --model "$MODEL" --auto
else
    opencode "$@" --model "$MODEL"
fi
