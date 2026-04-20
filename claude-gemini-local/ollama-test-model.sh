#!/bin/bash

# Cargar variables del .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

PROMPT=${1:-"Hola, dime qué modelo eres y qué tal programas."}
MODEL="qwen2.5-coder:14b"
URL="http://localhost:${LITELLM_PORT:-4000}/v1/messages"

echo "🔍 Probando modelo local: $MODEL"
echo "📡 Enviando petición a: $URL (vía LiteLLM/Anthropic)"
echo "------------------------------------------------"

curl -s -X POST "$URL" \
     -H "Content-Type: application/json" \
     -H "x-api-key: sk-dummy-key" \
     -H "anthropic-version: 2023-06-01" \
     -d "{
       \"model\": \"$MODEL\",
       \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
       \"max_tokens\": 300
     }" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    content = data.get('content', [{}])[0].get('text', 'Error en la respuesta')
    print(content)
except Exception as e:
    print(f'❌ Error al procesar respuesta: {e}')
"

echo -e "\n------------------------------------------------"
