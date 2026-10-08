# Local LLM agent server (llama.cpp + Docker)

This project runs local models on **llama.cpp** inside Docker and connects an agentic CLI client (**OpenCode**) to them, with support for both **NVIDIA GPU** acceleration and **CPU-only** modes.

> Claude Code is not supported: it speaks the Anthropic Messages API, and llama.cpp's `/v1/messages` endpoint loses conversation history once tool results accumulate, which stalls agentic sessions mid-task. See `AGENTS.md`.

## 🏗️ Project Architecture

- **`llama-server`**: High-performance inference server. It natively supports Anthropic Messages and OpenAI Chat Completions APIs.
- **Docker + CUDA/CPU**: Isolated execution with support for GPU acceleration (NVIDIA) or standard CPU execution.
- **Hugging Face Hub**: Automatic download of optimized GGUF models.

## 🚀 Quick Start

### 1. Prerequisites
- **Docker with Docker Compose is required**: everything runs in containers.
  Docker Engine on Linux, or Docker Desktop (WSL2 backend on Windows); an
  equivalent runtime that supports `docker compose` and GPU passthrough also
  works.
- **An NVIDIA GPU with 12 GB of VRAM or more is strongly recommended.** Every
  profile except the CPU one is sized for a 12 GB card; the CPU profile runs a
  small 9B model and is much slower.
- **For GPU mode**: an NVIDIA driver plus the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  on Linux (Docker Desktop on WSL2 provides GPU access itself).
- OpenCode (`npm install -g opencode-ai`), plus `curl`, `jq` and `node` for
  the client script.

### 2. Configuration
Choose your mode and create your `.env` file:

Two recommended NVIDIA GPU profiles sit in the repo root; each sample's
header explains when to use it.

**Programming, long autonomous agent runs (most reliable):**
```bash
cp .env.gpu.qwen3.8-27b-fullgpu-best-coding.sample .env
```
Qwen3.8-27B dense, fully on a 12 GB GPU: ~40 tok/s, 96K context, no vision.

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
The script checks whether the model is already in `MODELS_DIR` (default
`docker/data/models/`) and downloads it from Hugging Face if not, before
starting the container.

### 4. Run OpenCode
```bash
./scripts/clients/opencode-llama.sh
```
Use `opencode-llama-yolo.sh` to skip permission prompts.

The script reads the context size from the server's `/slots` (falling back to
`LLAMA_CONTEXT_SIZE`) and derives OpenCode's limits from it:

| Setting | Rule | At 96K (98304) |
| --- | --- | ---: |
| Output limit per response | a third of the context, at most 32768 | 32768 |
| Compaction buffer | output limit + 1000 | 33768 (compacts at ~64.5K) |
| Kept verbatim after compaction | a fifth of the context | 19660 |

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

## 🔧 Troubleshooting & Maintenance

- **View real-time logs**: `./scripts/docker/attach-server-logs.sh` attaches
  to whichever profile is running, GPU or CPU (any `llama-cpp*` container), and
  reattaches after a restart. `docker logs -f <container_name>` also works; the
  name is in the profile's compose file.
- **Stop server**: `./scripts/docker/stop-all-servers.sh` stops every profile,
  GPU or CPU. `launch-server.sh` already does this before starting another one.
- **Live status** (GPU, RAM, container): `./scripts/docker/llama-status.sh`
- **Delete downloaded models**: `./scripts/docker/delete-models.sh` (uses
  `MODELS_DIR` from `.env`).
