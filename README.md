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

Two recommended NVIDIA GPU profiles sit in the repo root; each sample's
header explains when to use it.

**Programming, long autonomous agent runs (most reliable):**
```bash
cp .env.gpu.qwen3.8-27b-fullgpu-best-coding.sample .env
```
Qwen3.8-27B dense, fully on a 12 GB GPU: ~40 tok/s, 100K context, no vision.

**Assistants, interactive agents, image and video analysis (fastest):**
```bash
cp .env.gpu.qwen3.6-35b-a3b-apex-mini-best-assistant-with-vision.sample .env
```
Qwen3.6-35B-A3B MoE: ~86-97 tok/s, 128K context, vision. Less reliable on
long unattended runs. See `docs/BENCHMARKS.md` for the numbers.

Each profile has its own Compose project, service and container name, all
derived from the model (the coding profile ends in `-code`, the vision one in
`-fast-vision`), so both recommended profiles can be created side by side.
Only one can run at a time on a 12 GB GPU: `launch-server.sh` stops every
`llama-cpp*` container before starting the chosen one.

Every other profile lives in `alternatives/` (compose files in
`docker/alternatives/`).

**For CPU only:**
```bash
cp alternatives/.env.cpu.qwopus3.5-9b.sample .env
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

The script reads the context size from the server's `/slots` (falling back to
`LLAMA_CONTEXT_SIZE`) and derives OpenCode's limits from it:

| Setting | Rule | At 100K (102400) |
| --- | --- | ---: |
| Output limit per response | a third of the context, at most 32768 | 32768 |
| Compaction buffer | output limit + 1000 | 33768 (compacts at ~68.6K) |
| Kept verbatim after compaction | a fifth of the context | 20480 |

The buffer must hold a whole response, or a request can go past the context
before OpenCode compacts. A larger "keep" leaves the session right under the
threshold after compacting, and subagents then compact again every couple of
tool calls.

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
  - GPU: `./scripts/docker/attach-server-logs.sh` (finds whichever profile
    is running), or `docker logs -f <container_name>` from the profile's
    compose file
  - CPU: `docker logs -f llama-cpp-qwopus3.5-9b-q4-k-m`
- **Stop server**: 
  - The script `./scripts/docker/launch-server.sh` handles this automatically, but you can also use:
  - `docker compose -f docker/alternatives/docker-compose-gpu-qwen-35b-a3b-apex-mini.yml down`
  - `docker compose -f docker/alternatives/docker-compose-cpu.yml down`
- **Deep Clean (Delete models and reset)**:
  ```bash
  rm -rf docker/data/models/*
  ```
