#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
exec "$SCRIPT_DIR/claude-llama.sh" --dangerously-skip-permissions "$@"
