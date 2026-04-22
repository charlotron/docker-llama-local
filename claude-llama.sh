#!/bin/bash

# Load variables from .env if it exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration for Claude Code
PORT=${LLAMA_PORT:-12345}
MODEL="claude_local"

export ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT"
export ANTHROPIC_API_KEY="sk-local"
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0

echo "🚀 Starting Claude Code"
echo "📡 Connecting to: $ANTHROPIC_BASE_URL"
echo "🤖 Model: $ANTHROPIC_MODEL"
echo "------------------------------------------------"

claude --model "$ANTHROPIC_MODEL" --dangerously-skip-permissions "$@"
