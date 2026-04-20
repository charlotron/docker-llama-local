# Gemini CLI with Local LLM (Ollama + LiteLLM)

Este proyecto permite conectar la **Gemini CLI** de Google con un modelo local ejecutándose en **Ollama**, utilizando **LiteLLM Proxy** como traductor de protocolos.

Basado en el artículo: [Using Gemini CLI with a local LLM](https://dev.to/polar3130/using-gemini-cli-with-a-local-llm-5f5l)

## 🏗️ Arquitectura del Proyecto

- **`config/`**: Configuraciones de servicios (Persistidas en Git).
  - `litellm/config.yaml`: Mapeo de modelos Gemini -> Ollama.
- **`data/`**: Datos persistentes voluminosos o sensibles (Excluidos en Git).
  - `ollama/models/`: Modelos descargados (GBs).
  - `ollama/config/`: Claves SSH privadas generadas por Ollama.
  - `litellm/logs/`: Registros del proxy.
- **`.env`**: Variables de entorno para la infraestructura Docker.

## 🚀 Getting Started

### 1. Requisitos Previos
- Docker y Docker Compose instalados.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (Para soporte GPU).
- Gemini CLI instalada en el sistema host.

### 2. Configuración de Infraestructura
Crea tu archivo de configuración local:
```bash
cp .env.sample .env
```
*(Opcional: Edita el modelo en `OLLAMA_MODEL`. Por defecto usa `gemma2:9b`).*

### 3. Levantar Servicios
```bash
docker compose up -d
```
Ollama comenzará a descargar el modelo automáticamente. Puedes seguir el progreso con:
```bash
docker compose logs -f ollama
```

## 💻 Uso con Gemini CLI

Para que la CLI se comunique con tu infraestructura local en lugar de los servidores de Google, sigue estos pasos en tu terminal:

### 1. Configurar variables de entorno (Host)
```bash
# Redirigir a LiteLLM Proxy
export GOOGLE_GEMINI_BASE_URL="http://localhost:4000"

# API Key ficticia (requerida por el SDK)
export GEMINI_API_KEY="sk-dummy-key"
```

### 2. Ejecutar la CLI
Es obligatorio desactivar el sandbox para que la CLI pueda acceder a la red local y heredar las variables de entorno:
```bash
gemini --sandbox=false
```

## 🛠️ Mantenimiento

- **Cambiar de modelo:** Actualiza `OLLAMA_MODEL` en el `.env` y reinicia con `docker compose up -d`.
- **Estado del servicio:** Usa `./status.sh` para ver qué modelo está en memoria y `./list-models.sh` para ver todos los descargados.
- **Limpiar datos:** Borra la carpeta `./data` para resetear modelos y configuraciones locales.
- **Logs del Proxy:** `docker compose logs -f litellm` para depurar peticiones de la CLI.

Para más detalles sobre las convenciones del proyecto, consulta [GEMINI.md](./GEMINI.md).
