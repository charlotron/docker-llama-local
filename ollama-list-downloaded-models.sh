#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "📚 Modelos descargados en Ollama:"
echo "------------------------------------------------"

RESPONSE=$(curl -s http://localhost:11434/api/tags)

if [ -z "$RESPONSE" ]; then
    echo "❌ No se pudo conectar con Ollama."
    exit 1
fi

echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = data.get('models', [])
if not models:
    print('   (Ninguno)')
else:
    print(f'   {\"NOMBRE\":<30} {\"TAMAÑO\":<10} {\"ID\":<15}')
    for m in models:
        size = m['size'] / (1024**3)
        print(f'   {m[\"name\"]: <30} {size:>7.2f} GB   {m[\"digest\"][:12]}')
"
echo "------------------------------------------------"
