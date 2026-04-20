#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "📊 Estado de los modelos en Ollama:"
echo "------------------------------------------------"

RESPONSE=$(curl -s http://localhost:11434/api/ps)

if echo "$RESPONSE" | grep -q "$OLLAMA_MODEL"; then
    echo "✅ Modelo $OLLAMA_MODEL está CARGADO en memoria."
    echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    if m['name'].startswith('$OLLAMA_MODEL'):
        size = m['size'] / (1024**3)
        vram = m.get('size_vram', 0) / (1024**3)
        print(f'   - Tamaño total: {size:.2f} GB')
        print(f'   - En VRAM: {vram:.2f} GB')
        print(f'   - Expiración: {m.get(\"expires_at\", \"N/A\")}')
"
else
    echo "⏳ Modelo $OLLAMA_MODEL NO está cargado (o está cargando...)"
fi
echo "------------------------------------------------"
