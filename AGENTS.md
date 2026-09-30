# AGENTS.md

Operational notes for anyone (human or agent) launching profiles in this repo.
Read this before running `scripts/docker/launch-server.sh` against a real host.

## Profile files: what's tracked vs. what's real

The repo root holds only the two recommended profiles; everything else lives
in `alternatives/` (env samples) and `docker/alternatives/` (compose files):

- `.env.gpu.qwen3.8-27b-fullgpu-best-coding.sample` -- programming, long
  autonomous agent runs. Slower, no vision.
- `.env.gpu.qwen3.6-35b-a3b-apex-mini-best-assistant-with-vision.sample` --
  assistants, interactive agents, image/video analysis. Fastest.

Each sample's header says when to use it. Real files copied from any sample
go in the repo root, next to `.env`; `COMPOSE_FILE` paths are relative to it.

- **`.env.gpu.<profile>.sample`** (tracked in git): a template for one profile.
  Carries the model-specific settings (`COMPOSE_FILE`, `HF_REPO`, `HF_FILE`,
  `LLAMA_CONTEXT_SIZE`, ...) with `MODELS_DIR=""` left blank on purpose. **Never
  edit these** — they are the reference config for each profile and must stay
  generic/host-agnostic.
- **`.env` / `.env.gpu.<profile>`** (real files, gitignored, host-specific): what
  you actually launch with. Carries your machine's own settings —
  `MODELS_DIR`, `LLAMA_HOST`, `LLAMA_PORT`, `LLAMA_CPU_THREADS` — plus the
  model-specific block copied over from the `.sample` you want to run.

`launch-server.sh` defaults to `.env` when called with no argument, or loads
whatever file you pass as the first argument.

## Switching profiles — two supported patterns

**Pattern A — one `.env`, edited per switch.** Keep your machine's own
settings in `.env` (`MODELS_DIR`, host, port, threads) and, each time you
want a different model, copy the model-specific block from the target
`.sample` into `.env`, replacing the previous model's block. Launch with no
argument:
```
./scripts/docker/launch-server.sh
```

**Pattern B — one real `.env.gpu.<profile>` file per profile (recommended if
you switch often).** Create a real, non-`.sample` file for each profile you
use regularly, by copying the corresponding `.sample` and filling in your
machine's `MODELS_DIR`/host/port/threads once:
```
cp .env.gpu.qwen3.8-27b-fullgpu-best-coding.sample .env.gpu.qwen3.8-27b-fullgpu-best-coding
# edit .env.gpu.qwen3.8-27b-fullgpu-best-coding: set MODELS_DIR to your real model directory
cp alternatives/.env.gpu.gpt-oss-20b.sample .env.gpu.gpt-oss-20b
```
Then launch any profile directly, no editing required per switch:
```
./scripts/docker/launch-server.sh .env.gpu.qwen3.8-27b-fullgpu-best-coding
./scripts/docker/launch-server.sh .env.gpu.gpt-oss-20b
```
These per-profile real files are gitignored (`.env.*` except `*.sample` — see
`.gitignore`) — safe to keep host-specific paths in them, they will never be
committed.

**In both patterns, the `.sample` files themselves are never touched.** They
exist to be copied from, not launched directly or edited in place — launching
a `.sample` as-is runs with `MODELS_DIR=""`, which falls back to
`./docker/data/models` relative to the repo root and can silently resolve to
the wrong path depending on how Docker Compose resolves relative volume
paths (see Known gotchas below).

## Known gotchas

- **`MODELS_DIR=""` + Docker Compose relative-path resolution.** Compose
  resolves a relative `${MODELS_DIR}` volume path against the *compose
  file's own directory* (`docker/`), not the repo root `launch-server.sh` cds
  into. Left blank, `./docker/data/models` can double up into
  `docker/docker/data/models` and the container fails with "No such file or
  directory" even though the model downloaded successfully. `launch-server.sh`
  now exports `MODELS_DIR` as an absolute path internally to avoid this, but
  always set a real `MODELS_DIR` in your own `.env*` rather than relying on
  the blank default.
- **`--load-mode mlock` hangs indefinitely on a slow/virtualized filesystem.**
  All GPU compose files use `--load-mode mlock` so the whole model is pinned
  in RAM at load time (no lazy paging) — this requires `MODELS_DIR` to point
  at native, fast local disk (e.g. `/home/<user>/data/llama-models`). If it
  ever points at a WSL2 `/mnt/<drive>` 9p bind mount (or any slow
  network/virtualized storage) instead, `mlock` hangs in an uninterruptible
  disk wait with zero progress and no error — it looks like a crashed load,
  not a slow one. If you're stuck on slow storage, switch that profile's
  `--load-mode` to `none` instead of moving the model. See
  `docs/VISION_MODEL_EVAL.md` for the original diagnosis.
- **Port already in use / "not available" errors from Docker on Windows/WSL2
  hosts.** After a host sleep/resume, Windows can reserve the default port
  (12345) in its Hyper-V dynamic port exclusion range, which surfaces inside
  WSL2 as a permissions error on bind, not a normal "port in use" message.
  **`LLAMA_PORT` stays 12345 — never switch to a different port as a
  workaround, silently or otherwise.** OpenCode and other clients are
  configured against 12345; changing it breaks them until someone notices and
  reconfigures every client by hand. Fix the actual port instead: from an
  elevated Windows PowerShell, `net stop winnat && net start winnat`.
  **Caveat:** this can itself leave WSL2 without IPv4/IPv6 internet access
  for a bit (DNS resolves but every connection times out) — if that happens,
  run `wsl --shutdown` from PowerShell (not admin) and reopen your WSL
  terminal to fully reinitialize the virtual network adapter, then retry.
  If neither fixes it, stop and ask rather than picking another port.
- **A real `.env`/`.env.<profile>` can outlive a compose-file rename.** When a
  compose file gets renamed in this repo (e.g. `docker-compose-gpu.yml` →
  `docker-compose-gpu-qwen-35b-a3b-mtp.yml`), git tracks the rename fine, but
  any host-specific real `.env*` file that hardcodes the old `COMPOSE_FILE=`
  path is gitignored and won't get updated by a `git pull` — it'll fail with
  "no such file or directory" the next time you launch. Check `COMPOSE_FILE`
  in your real env files after pulling changes that touch `docker/*.yml`.
- **`preserve_thinking: true` + a small client `max_tokens` returns EMPTY
  content, not an error.** Every GPU profile here enables thinking via
  `--chat-template-kwargs '{"preserve_thinking": true, ...}'`. The reasoning
  channel is billed against the same budget as the visible answer, and these
  models reason at length: measured 2227 reasoning tokens with **0 content
  tokens** on a request capped at 768. The response comes back HTTP 200 with
  `finish_reason: "length"` and `content: ""` — a silent, valid-looking empty
  answer that is easy to misdiagnose as a broken model or a bad prompt.
  This cost real measurements twice: HumanEval+ initially scored 5.5% purely
  because EvalPlus hardcodes `max_new_tokens: int = 768` (patch it in
  `evalplus/provider/base.py`), and the needle-in-a-haystack recall test
  scored 3/5 at `max_tokens: 400` while the correct answer was present in the
  reasoning trace in **19 of 19** cases — a formatting failure, not a recall
  failure. Budget is not free either: raising the cap from 4096 to 8192 moved
  APEX-I-Mini from 87.2/82.3 to 93.9/87.2 on HumanEval/HumanEval+.
  **Give any client at least 4096 `max_tokens`, and prefer 8192 for coding.**
  If a client cannot be configured that far, disable thinking for it rather
  than letting it receive empty strings.
- **`--reasoning-budget` must sit BELOW the client's `max_tokens`, or it does
  nothing.** The budget caps the thinking channel and injects a "wrap up now"
  nudge, but it can only fire if the request is still alive when the budget is
  reached. Set it above the client cap and the client truncates first, mid-
  thought, which is the empty-content failure the budget was meant to prevent.
  Measured: with `--reasoning-budget 16384` and a client cap of 8192, **38% of
  164 HumanEval problems returned empty solutions** -- the budget never fired
  once. The same budget looked like it worked when tested at `max_tokens
  81920`, which is why a generous test cap hides this bug. The rule is:

      client max_tokens  >  --reasoning-budget  +  room for the answer

  The shipped `apex-mini` profile uses 16384, so any client hitting it needs at
  least ~24576 to be safe (16384 reasoning + 8192 answer). If your clients
  cannot go that high, lower `--reasoning-budget` to match them instead --
  a budget larger than the smallest client cap protects nobody.

### The Anthropic `/v1/messages` endpoint loses conversation history

llama.cpp exposes an Anthropic-compatible `/v1/messages` alongside the
OpenAI-compatible `/v1/chat/completions`. The Anthropic one drops most of the
conversation once `tool_result` blocks accumulate. Measured with the same
history sent to both endpoints, growing one tool round at a time:

| tool rounds | `/v1/messages` prompt | `/v1/chat/completions` prompt |
|-------------|-----------------------|-------------------------------|
| 0           | 17                    | 272                           |
| 1           | 555                   | 823                           |
| 2           | 555                   | 1374                          |
| 4           | 1106                  | 2476                          |
| 6           | 1106                  | 3578                          |
| 8           | 1106                  | 4680                          |

`/v1/messages` flatlines; `/v1/chat/completions` grows linearly. Single-shot
requests look fine on both, so this only shows up in agentic sessions.

The failure does not look like an error. The model simply stops seeing what it
already did, so after a few tool rounds it ends the turn with a premature
summary and the task is never finished. Stray tool-call closing tags can leak
into the text as the parser desyncs.

Clients must therefore target `/v1/chat/completions`. `opencode-llama.sh` uses
the `@ai-sdk/openai-compatible` provider for this reason; do not switch it back
to `@ai-sdk/anthropic`.

Claude Code has no such option: it speaks the Anthropic API by design and is
therefore permanently exposed to this bug. Its launcher was removed from this
repo rather than left in place as a trap. Recover it with
`git show f224847:scripts/clients/claude-llama.sh` if llama.cpp ever fixes the
endpoint.

### Vision needs an `mmproj`, and the MTP repo does not ship one

`Qwen3.6-35B-A3B` is multimodal at the base, but the GGUF repo the default
profile pulls from (`mudler/Qwen3.6-35B-A3B-APEX-MTP-GGUF`) contains the weights
only. The vision tower is a separate `mmproj.gguf` that lives in the sibling
repo `mudler/Qwen3.6-35B-A3B-APEX-GGUF` (861 MB).

Without it the server starts happily and `/props` reports
`"modalities": {"vision": false}`; an image request then fails with
`500 image input is not supported - hint: ... you may need to provide the mmproj`.
Clients report this as "the model has no vision capability", which is true of the
files loaded but not of the model itself.

The `apex-mini-vision` profile is `apex-mini` plus `--mmproj`. Measured cost:
none (~95 tok/s and ~11.4 GB VRAM either way). `launch-server.sh` downloads the
file automatically when `HF_MMPROJ_REPO` and `HF_MMPROJ_FILE` are set, and
exports `TARGET_MMPROJ_FILE` for the compose file to pick up.
