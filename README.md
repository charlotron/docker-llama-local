# Claude Code with Local LLM (llama.cpp + Docker + NVIDIA)

Este proyecto permite conectar **Claude Code** (la CLI de Anthropic) con modelos locales ejecutándose en **llama.cpp** dentro de Docker, aprovechando la aceleración de **GPU NVIDIA**.

Basado en la guía de configuración: [Running Claude Code with Local LLMs](https://github.com/pchalasani/claude-code-tools/blob/main/docs/local-llm-setup.md#running-claude-code-and-codex-with-local-llms)

## 🏗️ Arquitectura del Proyecto

- **`llama-server`**: Servidor de inferencia de alto rendimiento con soporte nativo para la Anthropic Messages API.
- **Docker + CUDA**: Ejecución aislada con acceso total a la GPU NVIDIA.
- **Hugging Face Hub**: Descarga automática de modelos GGUF optimizados.

## 🚀 Getting Started

### 1. Requisitos Previos
- Docker y Docker Compose instalados.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) configurado.
- Claude Code instalado (`npm install -g @anthropic-ai/claude-code`).

### 2. Configuración Inicial
Crea tu archivo `.env`:
```bash
cp .env.sample .env
```
Edita `LLAMA_CPP_MODEL_HF` para elegir el modelo. Por defecto está configurado **Qwen2.5-Coder-14B**, que ofrece un gran equilibrio entre velocidad y capacidad de razonamiento.

### 3. Lanzar Servidor
```bash
./launch-server.sh
```
El modelo se descargará automáticamente la primera vez. Puedes ver el progreso con:
```bash
docker logs -f llama-cpp
```

## 💻 Uso con Claude Code

Para usar Claude con tu modelo local:

```bash
./claude-llama.sh
```

Este script configura automáticamente:
- `ANTHROPIC_BASE_URL` apuntando a tu servidor local.
- `ANTHROPIC_API_KEY` con un valor ficticio.
- Desactiva el tráfico no esencial (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`).

## 🛠️ Herramientas y Tooling

El servidor está configurado con:
- `--jinja`: Usa el template oficial del modelo para un formateo preciso de herramientas.
- `--chat-template-kwargs '{"enable_thinking": false}'`: Optimiza el flujo para flujos de agentes.
- `-c 65536`: Ventana de contexto amplia requerida por Claude Code.

## 🔄 Mantenimiento

- **Ver logs**: `docker logs -f llama-cpp`
- **Limpiar todo**: `docker compose -f docker/docker-compose.yml down`
