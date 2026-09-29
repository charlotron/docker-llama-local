# Local LLM agent server (llama.cpp + Docker)

This project runs local models on **llama.cpp** inside Docker and connects an agentic CLI client (**OpenCode**) to them, with support for both **NVIDIA GPU** acceleration and **CPU-only** modes.

> Claude Code is not supported: it speaks the Anthropic Messages API, and llama.cpp's `/v1/messages` endpoint loses conversation history once tool results accumulate, which stalls agentic sessions mid-task. See `AGENTS.md`.

## 🏗️ Project Architecture

- **`llama-server`**: High-performance inference server. It natively supports Anthropic Messages and OpenAI Chat Completions APIs.
- **Docker + CUDA/CPU**: Isolated execution with support for GPU acceleration (NVIDIA) or standard CPU execution.
- **Hugging Face Hub**: Automatic download of optimized GGUF models.

## 🚀 Quick Start

### 1. Prerequisites
- Linux with Docker and Docker Compose installed.
- **For GPU mode**: [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed and configured.
- OpenCode installed (`npm install -g opencode-ai`).

### 2. Configuration
Choose your mode and create your `.env` file:

**For NVIDIA GPU (Recommended):**
```bash
cp .env.gpu.qwen-35b-a3b-apex-mini.sample .env
```

**For NVIDIA GPU with image and video input:**
```bash
cp .env.gpu.qwen-35b-a3b-apex-mini-vision.sample .env
```
Same weights and same measured speed as the profile above, plus an 861 MB
`mmproj` file that enables vision. See `docs/BENCHMARKS.md` for the numbers.

**For CPU only:**
```bash
cp .env.cpu.sample .env
```

### 3. Launch Server
```bash
./scripts/docker/launch-server.sh
```
The script will detect if the model exists in `docker/data/models/`. If not, it will download it automatically before starting the container.

### 4. Run OpenCode
```bash
./scripts/clients/opencode-llama.sh
```
Use `opencode-llama-yolo.sh` to skip permission prompts.

---

## 🛠️ Technical Specifications (llama-server)

Based on the [official llama-server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).

### Main Capabilities
- **Compatibility**: Native support for Anthropic (Messages API) and OpenAI (Chat/Completions).
- **Performance**: Continuous batching and parallel decoding.
- **Tool Use**: Support for function calling required by agentic clients.

### Available Endpoints (Port 12345 by default)
- `POST /v1/chat/completions`: OpenAI-compatible endpoint. **This is the one to use.**
- `POST /v1/messages`: Anthropic-compatible endpoint. Unusable for agentic work:
  it loses conversation history once tool results accumulate (see AGENTS.md).
- `GET /health`: Server and model status.

### Key Configuration Flags
- `--n-gpu-layers`: Number of layers to offload to GPU (set to `all` or `999` for full GPU).
- `--ctx-size`: Context window size (measured in **tokens**).
- `--threads`: Number of CPU threads used for processing.
- `--jinja`: **Critical**. Enables the template engine for correct "Tool Use" handling.
- `--reasoning on`: Enables enhanced reasoning capabilities.

## 📺 Credits
This setup was originally inspired by the tutorial by **Ing. Kevin David**: [How to configure Claude Code with llama.cpp](https://www.youtube.com/watch?v=Ym967X2VCKY).

---

## 🔧 Troubleshooting & Maintenance

- **View real-time logs**:
  - GPU: `docker logs -f llama-cpp-gpu`
  - CPU: `docker logs -f llama-cpp`
- **Stop server**: 
  - The script `./scripts/docker/launch-server.sh` handles this automatically, but you can also use:
  - `docker compose -f docker/docker-compose-gpu-qwen-35b-a3b-apex-mini.yml down`
  - `docker compose -f docker/docker-compose-cpu.yml down`
- **Deep Clean (Delete models and reset)**:
  ```bash
  rm -rf docker/data/models/*
  ```
