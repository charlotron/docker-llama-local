# Claude Code with Local LLM (llama.cpp + Docker + NVIDIA)

Este proyecto permite conectar **Claude Code** (la CLI de Anthropic) con modelos locales ejecutándose en **llama.cpp** dentro de Docker, aprovechando la aceleración de **GPU NVIDIA**.

## 🏗️ Arquitectura del Proyecto

- **`llama-server`**: Servidor de inferencia de alto rendimiento. Soporta nativamente las APIs de Anthropic Messages y OpenAI Chat Completions.
- **Docker + CUDA**: Ejecución aislada con soporte para aceleración por GPU.
- **Hugging Face Hub**: Descarga automática de modelos GGUF optimizados.

## 🚀 Guía Rápida

### 1. Requisitos Previos
- Linux con Docker y Docker Compose.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) instalado y configurado.
- Claude Code instalado (`npm install -g @anthropic-ai/claude-code`).

### 2. Configuración
Crea tu archivo `.env` (ya preconfigurado para Qwopus3.5-9B y puerto 12345):
```bash
# Si no existe, puedes usar el script de lanzamiento que lo crea por ti o copiar el sample
cp .env.sample .env
```

### 3. Lanzar Servidor
```bash
./launch-server.sh
```
El script detectará si el modelo ya existe en `docker/data/models/`. Si no, lo descargará automáticamente antes de iniciar el contenedor.

### 4. Ejecutar Claude Code
```bash
./claude-llama.sh
```

---

## 🛠️ Especificaciones Técnicas (llama-server)

Basado en la [documentación oficial de llama-server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).

### Capacidades Principales
- **Compatibilidad**: Soporte nativo para OpenAI (Chat/Completions) y Anthropic (Messages API).
- **Rendimiento**: Continuous batching y decodificación paralela para múltiples usuarios.
- **Tool Use**: Soporte para function calling (herramientas) requerido por agentes como Claude Code.
- **Monitoreo**: Endpoint de métricas compatible con Prometheus.

### Endpoints Disponibles (Puerto 12345)
- `POST /v1/messages`: Endpoint compatible con Anthropic (usado por Claude Code).
- `POST /v1/chat/completions`: Endpoint compatible con OpenAI.
- `GET /health`: Estado del servidor y del modelo cargado.
- `GET /metrics`: Métricas de rendimiento (Prometheus).
- `POST /tokenize` / `/detokenize`: Gestión de tokens.

### Flags Clave en nuestra Configuración
- `--n-gpu-layers all`: Descarga todas las capas del modelo en la VRAM de la GPU.
- `--ctx-size 32768`: Ventana de contexto optimizada para 16GB de RAM.
- `--flash-attn on`: Aceleración de atención para mejor rendimiento y menor uso de memoria.
- `--jinja`: **Crítico**. Habilita el motor de plantillas para que el modelo gestione correctamente el "Tool Use" (uso de herramientas) de Claude Code.
- `--reasoning on`: Habilita capacidades de razonamiento mejoradas.

## 📺 Referencias y Créditos
Esta configuración está inspirada y optimizada siguiendo el tutorial de **Ing. Kevin David**: [Cómo configurar Claude Code con llama.cpp](https://www.youtube.com/watch?v=Ym967X2VCKY).

- **Ver logs en tiempo real**: `docker logs -f llama-cpp`
- **Detener servidor**: `docker compose -f docker/docker-compose.yml down`
- **Limpieza profunda (borrar modelos y resetear)**:
  ```bash
  docker compose -f docker/docker-compose.yml down
  rm -rf docker/data/models/*
  ./launch-server.sh
  ```
