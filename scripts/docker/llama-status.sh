#!/bin/bash

# --- Colors and Aesthetics ---
BOLD='\033[1m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Configuration Loading ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR/../.." || exit 1

if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration
HOST=${LLAMA_HOST:-127.0.0.1}
PORT=${LLAMA_PORT:-12345}

# Helper function to query and format slots once
print_slots() {
    curl -s "http://$HOST:$PORT/slots" | jq -r '
      def format_tokens(val): 
        if val == null then "0"
        elif val >= 1048576 then ((val / 1048576 * 10 | round / 10 | tostring) + "M")
        elif val >= 1024 then ((val / 1024 * 10 | round / 10 | tostring) + "K")
        else (val | tostring) end;
      ["Slot ID", "Processing?", "Slot Context Size", "Tokens Decoded", "Tokens Remaining"],
      ["-------", "-----------", "-----------------", "--------------", "----------------"],
      (.[] | [.id, .is_processing, format_tokens(.n_ctx), format_tokens(.next_token[0].n_decoded), format_tokens(.next_token[0].n_remain)])
      | @tsv
    ' | column -t -s $'\t'
}

# Helper function to print system RAM and GPU VRAM info
print_system_metrics() {
    echo -e "${CYAN}${BOLD}--- SYSTEM MEMORY (WSL2 RAM) ---${NC}\033[K"
    if command -v free &> /dev/null; then
        free -h | awk '
          /total/ {print "        " $1 "       " $2 "       " $3 "       " $4 "    " $5 "   " $6}
          /Mem:/ {print "RAM:    " $2 "     " $3 "      " $4 "      " $5 "     " $6 "    " $7}
          /Swap:/ {print "Swap:   " $2 "     " $3 "      " $4}
        ' | sed 's/$/\o033[K/'
    else
        echo -e "RAM info unavailable\033[K"
    fi
    echo -e "\033[K"

    # Check if we are running in WSL2 and have access to powershell.exe to print Windows host RAM
    if [ -f "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        echo -e "${CYAN}${BOLD}--- WINDOWS HOST PHYSICAL RAM ---${NC}\033[K"
        "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory" 2>/dev/null | awk 'NF==2 && $1 ~ /^[0-9]+$/ {printf "Host RAM: %.1f GB Total | %.1f GB Free | %.1f GB Used\n", $1/1048576, $2/1048576, ($1-$2)/1048576}' | sed 's/$/\o033[K/'
        echo -e "\033[K"
    fi
    
    echo -e "${CYAN}${BOLD}--- GPU VRAM & UTILIZATION (RTX 4070 SUPER) ---${NC}\033[K"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader,nounits | awk -F', ' '
          {print "VRAM: " $2 " MiB / " $1 " MiB (Used / Total) | GPU Load: " $3 "% | Temp: " $4 "°C"}
        ' | sed 's/$/\o033[K/'
    else
        echo -e "NVIDIA GPU info unavailable (nvidia-smi not in PATH or no NVIDIA GPU)\033[K"
    fi
    echo -e "\033[K"
}

# Check for --once or -o flags to print once and exit immediately (useful for tests/agents)
if [ "$1" == "--once" ] || [ "$1" == "-o" ]; then
    print_system_metrics
    echo -e "${CYAN}${BOLD}--- LLAMA.CPP ACTIVE SLOTS ---${NC}"
    print_slots
    exit 0
fi

# Graceful exit on Ctrl+C for the loop
trap "printf '\033[J\nMonitor finalizado.\n'; exit 0" SIGINT SIGTERM

# Clear screen once on start
clear

while true; do
    # Reposition cursor to top-left (0,0) - completely prevents flickering!
    printf "\033[H"
    
    echo -e "${MAGENTA}${BOLD}===================================================================${NC}\033[K"
    echo -e "${MAGENTA}${BOLD}           LLAMA.CPP SYSTEM & SLOT MONITOR (http://$HOST:$PORT) ${NC}\033[K"
    echo -e "${MAGENTA}${BOLD}===================================================================${NC}\033[K"
    echo -e "${YELLOW}Refrescando cada 10s - Presiona Ctrl+C para salir${NC}\033[K\n"
    
    print_system_metrics
    
    echo -e "${CYAN}${BOLD}--- LLAMA.CPP ACTIVE SLOTS ---${NC}\033[K"
    print_slots | sed 's/$/\o033[K/'
    
    # Erase everything below this point in case terminal height changed
    printf "\033[J"
    
    sleep 10
done
