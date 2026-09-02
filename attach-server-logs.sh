#!/bin/bash

# --- Colors and Aesthetics ---
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "\n${CYAN}# --- LLAMA.CPP AUTO-ATTACH LOGS ---${NC}"
echo -e "Esperando contenedor activo... (Presiona Ctrl + C para salir)\n"

# Trampa para salir limpiamente con Ctrl + C
trap "echo -e '\n${RED}Desconectado de los logs.${NC}'; exit 0" SIGINT SIGTERM

while true; do
    # Búsqueda por expresión regular amplia usando awk
    ACTIVE_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "llama-cpp-gpu(-v2)?" | head -n 1)

    if [ -n "$ACTIVE_CONTAINER" ]; then
        echo -e "${GREEN}✓ Conectado a los logs en tiempo real de: ${ACTIVE_CONTAINER}${NC}\n"
        
        # Conecta a los logs de forma interactiva
        docker logs -f --tail 100 "$ACTIVE_CONTAINER"
        
        echo -e "\n${YELLOW}! Se ha perdido la conexión con ${ACTIVE_CONTAINER}. Reintentando...${NC}"
    else
        printf "\r${YELLOW}⌛ Buscando servidor llama.cpp activo...${NC}   "
    fi

    sleep 2
done
