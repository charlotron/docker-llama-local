# MTP Benchmark Results — Qwen 35B A3B / 27B (gpu-host)

> **RAW DATA.** This is the full, unedited investigation log — every round, every test, every
> number, every methodology mistake found and corrected, in chronological order. It is not meant
> to be read start to finish. For the curated summary (final 4 profiles, chosen configs, what was
> rejected and why), see [`BENCHMARKS.md`](./BENCHMARKS.md) instead.

Date: 2026-09-15 (two rounds, same day)
Host: gpu-host (WSL2, RTX 4070 SUPER 12GB VRAM, 23GB WSL RAM ceiling — likely a WSL config
limit, not the physical host's actual RAM; see "WSL memory ceiling" section below)

## Executive summary

The original blocker was an **outdated Docker image** (llama.cpp build 8882). A plain
`docker pull` of the same tag brought it to build 10975, which properly supports MTP via
`--spec-type draft-mtp --spec-draft-n-max N`. On the previous build, `--draft-max` was
present in the compose file but inert (no real draft mechanism wired up).

With the new build, the **35B A3B model gives a real, repeatable +19% generation speedup**
with MTP on, at identical output quality. The 27B dense model showed a dramatic (and wrong)
+1390% figure in an earlier round — root-caused below to two methodology bugs — its real,
verified number is much more modest and comes with memory caveats on this 23GB-RAM host.

## Methodology errors found and corrected

1. **Mislabeled 27B run**: an intermediate round used `docker compose up -d` directly instead
   of `launch-server.sh` to toggle MTP on/off, and `TARGET_MODEL_FILE` wasn't exported in that
   SSH session — so the compose silently fell back to the default 35B model. The
   `--spec-draft-n-max` sweep (2/3/4) and the "27B" quality check from that round were actually
   the 35B A3B, relabeled correctly in the table below.
2. **Genuine 27B run hit RAM limits**: with MTP on and `--parallel 3` / ctx=393216, host RAM
   (23GB total) hit 94% and the system started swapping (3.1GB), producing 5.6 tok/s — worse
   than without MTP. Dropping to `--parallel 1` / ctx=131072 (still meets the 128K/slot floor)
   improved to 6.65 tok/s, but MTP-off at that same reduced config only measured 3.46 tok/s —
   far below the 30.2 tok/s seen at parallel=3. This drop when reducing context is
   counter-intuitive and was **not fully explained** (possibly interacts with `--fit-target`
   and GPU/CPU layer split); not chased further to avoid an open-ended session.

## Round 2 additions (2026-09-15, later same day)

- **IQ quants don't beat K-quants here.** 35B A3B IQ4_NL+MTP (row 10) is *slower* than
  Q4_K_XL+MTP despite being ~4GB smaller — 37.4 vs 42.0 tok/s. On this MoE model with heavy
  CPU-offloaded experts, IQ's per-weight dequant cost apparently outweighs its smaller
  footprint. Row 3 (Q4_K_XL+MTP) remains the pick.
- **Row 6 is now suspected mislabeled too.** A clean, container-verified run of 27B dense
  IQ4_XS (smaller than row 6's Q5_K_M) measured only **4.1-4.2 tok/s** (row 11) — 7x slower
  than row 6's reported 30.2 tok/s. A 27B *dense* model (all params active) with only
  `--fit-target 1536` MB on a 12GB GPU should be RAM/CPU-bound and slow; 30 tok/s for that
  shape is implausible and matches the same failure pattern already caught once before (env
  var not exported → silently benchmarked the fast 35B MoE instead). Row 6 was not
  re-verified this round (the file was already deleted) — treat it as unreliable, not
  as ground truth.
- **27B + MTP swap-free result obtained** (row 12): IQ4_XS + MTP at `--parallel 3` /
  full `--ctx-size 393216`, with `free -h` swap watched every 5s through the whole benchmark
  and confirmed flat (359-360MiB, no growth) — the smaller IQ4_XS quant (vs row 7-9's
  Q5_K_M) left enough RAM headroom to avoid the swapping seen before. Result: **5.4 tok/s
  vs 4.1 tok/s without MTP, a genuine +28% clean measurement** — modest compared to the 35B's
  +19%... [same ballpark], but far more trustworthy than the earlier swap-contaminated 5.6 or
  the suspect 30.2 baseline.
- **DeepSeek-Coder-V2-Lite-Instruct evaluated and ruled out** (row 13/14) — see dedicated
  section below.
- **WSL memory ceiling is artificial, not physical** — see dedicated section below.

## Round 3: broader tool-calling model search (GLM / Devstral / gpt-oss)

Round 2 only checked DeepSeek-Coder-V2-Lite and MiniMax-M2. This round widened the search,
with tool-calling verified via each model's `/props` chat_template (checked for `tool_call`
handling) **before** downloading/benchmarking, to avoid repeating the DeepSeek disk/time cost
on a model that turns out disqualified.

- **GLM-4.5-Air** (`unsloth/GLM-4.5-Air-GGUF`) — **ruled out without downloading**. 106B-total
  MoE; even the smallest practical quant (IQ4_XS) is split across two files, with the first
  part alone at 49.9GB (`content-length` checked via `curl -sIL`). Total well over 60GB — does
  not fit this host's budget by a wide margin regardless of active-param count.
- **Devstral-Small-2507** (`unsloth/Devstral-Small-2507-GGUF`, UD-Q4_K_XL, 24B dense, 14.55GB)
  — downloaded and benchmarked (row 15). Tool-call template confirmed (Mistral's agentic
  format, explicitly built for coding agents / OpenHands scaffold). Code quality: correct
  (standard DP palindrome solution). **Speed: 4.34 tok/s** — ~10x slower than Qwen 35B A3B+MTP.
  Being a **dense** 24B model (all params active every token, vs Qwen's 3B-active MoE), the
  full forward pass is far more expensive on this CPU/GPU-hybrid rig. Ruled out on speed alone.
- **gpt-oss-20b** (`unsloth/gpt-oss-20b-GGUF`, UD-Q4_K_XL, MoE ~3.6B active, 11.87GB) —
  downloaded and benchmarked (row 16). Tool-call template confirmed (OpenAI's harmony format,
  natively agentic — response includes a separate `reasoning_content` field alongside
  `content`). Code quality: correct, clean expand-around-center palindrome solution.
  **Speed: 42.37 ± 4.24 tok/s (n=3)** — matches Qwen 35B A3B+MTP's 42.0 tok/s, achieved with
  **no speculative decoding at all** (gpt-oss's architecture isn't MTP-capable in this
  llama.cpp build), at roughly **half the disk/RAM footprint** (11.87GB vs 22.85GB) and
  noticeably lower RAM pressure (6.4GB used vs 18.8GB for the Qwen 35B A3B+MTP run). This is
  the strongest alternative found so far — see "gpt-oss-20b: a real contender" below.

**Conclusion so far**: gpt-oss-20b earns a dedicated deeper look (more repeated runs, a full
essay-quality check, and confirming whether llama.cpp's classic `-md`/external-draft-model
speculative decoding could push it even faster) before it's adopted as a default — but on the
numbers gathered this round, it's competitive with the current champion at a much smaller
footprint, which is worth pursuing further. Devstral and GLM-4.5-Air are ruled out (speed and
size respectively, not tool-calling).

## Alternative model family research: DeepSeek / MiniMax

Checked whether a smaller DeepSeek or MiniMax coding model with tool-calling support could
run here (same agentic tool-use requirement as the Qwen models, which use `--jinja` chat
templates with tool-call support).

- **DeepSeek-Coder-V2-Lite-Instruct** (`bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF`,
  16B total / 2.4B active MoE, Q4_K_M quant, 9.65GB): downloaded and benchmarked.
  - At the standard `--parallel 3` / `--ctx-size 393216`, the container **OOM-crash-looped**
    (exit 137) — this model's KV-cache/context handling needs more memory per token than
    Qwen's at this context length.
  - At `--parallel 1` / `--ctx-size 131072` (the 128K/slot floor, no concurrency headroom)
    it loaded and ran cleanly: **23.8 ± 3.4 tok/s** (n=3), VRAM 10.1/12.28GB, RAM 11/23GB, no
    swap.
  - **Disqualified for the agentic use case anyway**: `curl .../props` shows its chat
    template has no `tool_call`/function-calling support — this is a pure code-completion
    model, not built for tool use. Ruled out regardless of speed.
- **MiniMax**: not benchmarked. A quick repo probe found `unsloth/MiniMax-M2-GGUF` exists,
  but MiniMax-M2 is a 230B-class MoE — no realistically small (<30GB) quant fits this
  12GB-VRAM/23GB-RAM host, and no smaller MiniMax coding-specific GGUF was found in the time
  available. Not chased further.
- **Conclusion**: no DeepSeek/MiniMax candidate beats or matches the Qwen models here for the
  agentic coding use case on this hardware. Sticking with Qwen 35B A3B is still the right call.

## WSL memory ceiling — likely fixable

gpu-host's `free -h` reports 23GB total RAM, but that's just the WSL2 VM's allocation, not the
physical host. `/mnt/c/Users/<user>/.wslconfig` (readable via the Windows drive mount) shows:

```ini
[wsl2]
networkingMode=mirrored
localhostForwarding=true
memory=24GB
```

If the physical host has more RAM than 24-28GB (unconfirmed this round — would need checking
from the Windows side, e.g. Task Manager or `systeminfo`), raising `memory=` here and running
`wsl --shutdown` from PowerShell (then relaunching) would give more headroom for the 27B+MTP
and DeepSeek-style configs that hit the RAM ceiling above. **Not applied this round** — doing
so would drop the active SSH session, so it needs to be done from the Windows side by Carlos,
not automated over SSH. This is a good candidate for the next round once bumped.

## Results table

**Base image for all "new build" rows:** `ghcr.io/ggml-org/llama.cpp:full-cuda`, pulled
2026-09-15, `version: 0.4.1-dev (build 10975, commit 4c9233c03)`.
**Common flags:** `--jinja --flash-attn on --context-shift --cache-type-k q4_0 --cache-type-v q4_0
--cache-ram 2048 --load-mode mlock --no-warmup --threads 14 --threads-batch 14 --temp 0.6
--top-p 0.95 --top-k 20 --min-p 0.05 --presence-penalty 0.2 --repeat-penalty 1.1`.
**Benchmark:** `POST /completion`, fixed prompt, `n_predict 100, ignore_eos true`, one
untimed warmup request before each measured run.

| # | Model / quant | HF repo | Build | spec-draft-n-max | parallel / ctx-per-slot | tok/s gen (mean ± range) | tok/s prompt | VRAM | Host RAM | Quality |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 35B A3B Q4_K_XL (original) | unsloth/Qwen3.6-35B-A3B-GGUF | 8882 | inert (`--draft-max`, no effect) | 3 / 131072 | 36.7 (1 sample) | 19.7 | — | — | — |
| 2 | 35B A3B Q4_K_XL | unsloth (same, no MTP) | 10975 | none | 3 / 131072 | 39.8–39.9 | 17.9–25.1 | — | — | reference |
| 3 | **35B A3B Q4_K_XL** | **unsloth/Qwen3.6-35B-A3B-MTP-GGUF** | 10975 | **2** | 3 / 131072 | **42.0 ± 3.6** (n=8) | 18.5 | 9.67/12.28GB | 18.8/23.5GB | code correct, essay 413 words, coherent |
| 4 | 35B A3B Q4_K_XL | unsloth MTP repo | 10975 | 3 | 3 / 131072 | 36.3 ± 10.2 (n=5) | — | — | — | not evaluated |
| 5 | 35B A3B Q4_K_XL | unsloth MTP repo | 10975 | 4 | 3 / 131072 | 40.6 ± 18.5 (n=5) | — | — | — | not evaluated |
| 6 | 27B dense Q5_K_M | unsloth/Qwen3.8-27B-GGUF | 10975 | none | 3 / 131072 | 30.2 ± 3.6 (n=3) | 9.4 (possible cold start) | — | 4.4GB free buff/cache | — |
| 7 | 27B dense Q5_K_M | unsloth/Qwen3.8-27B-GGUF | 10975 | 2 | 3 / 131072 | **5.6 ± 1.1** (n=5) — **swapping (3.1GB), RAM at 94%** | — | 8.79GB | 22/23GB (thrashing) | code correct, essay 413 words (quality OK despite slowness) |
| 8 | 27B dense Q5_K_M | unsloth/Qwen3.8-27B-GGUF | 10975 | 2 | **1 / 131072** | 6.65 ± 0.2 (n=5) | — | 9.69/12.28GB | 15/23GB (7.6GB free) | not evaluated |
| 9 | 27B dense Q5_K_M | unsloth/Qwen3.8-27B-GGUF | 10975 | none | **1 / 131072** | 3.46 ± 0.01 (n=5, very stable) | 8.6–11.9 | — | — | — |
| 10 | 35B A3B IQ4_NL | unsloth/Qwen3.6-35B-A3B-MTP-GGUF | 10975 | 2 | 3 / 131072 | 37.4 ± 6.0 (n=5) — slower than row 3 | 20.8-39.7 (noisy) | 9.67/12.28GB | 15/23GB | code correct (coherent reasoning, not re-scored) |
| 11 | 27B dense IQ4_XS | unsloth/Qwen3.8-27B-GGUF | 10975 | none | 3 / 131072 | **4.1-4.2** (4 samples, tight) | — | 9.74/12.28GB | 15/23GB, no swap | not evaluated |
| 12 | **27B dense IQ4_XS** | unsloth/Qwen3.8-27B-GGUF | 10975 | **2** | 3 / 131072 | **5.4 ± 0.5** (n=5) — **swap-free, verified via 5s-interval `free -h` polling through the run** | — | 8.65/12.28GB | 18/23GB, swap flat at 359-360MiB | code correct (coherent, not re-scored) |
| 13 | DeepSeek-Coder-V2-Lite-Instruct Q4_K_M | bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF | 10975 | n/a (no MTP variant found) | 3 / 131072 | **OOM crash-loop (exit 137)** | — | — | — | n/a |
| 14 | DeepSeek-Coder-V2-Lite-Instruct Q4_K_M | bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF | 10975 | n/a | **1 / 131072** | 23.8 ± 3.4 (n=3) | 24.7-39.5 | 10.1/12.28GB | 11/23GB, no swap | **disqualified: no tool-calling in chat template** |
| 15 | Devstral-Small-2507 UD-Q4_K_XL (24B dense) | unsloth/Devstral-Small-2507-GGUF | 10975 | n/a (no MTP for this arch) | 3 / 131072 | **4.34 ± 0.15** (n=3) | 2.7-8.9 (noisy) | 9.9/12.28GB | 22/23GB, no swap observed | tool-call template confirmed; code correct (standard DP palindrome solution) |
| 16 | gpt-oss-20b UD-Q4_K_XL (MoE, ~3.6B active) | unsloth/gpt-oss-20b-GGUF | 10975 | n/a (no MTP for this arch) | 3 / 131072 | **42.37 ± 4.24** (n=3: 44.17/43.02/39.93) | 27.0-71.5 (noisy) | 10.45/12.28GB | 6.4/23GB used, 15GB free/cache, swap 432MiB (pre-existing, not from this run) | tool-call (harmony format) confirmed; code correct, well-documented expand-around-center solution |
| 17 | gpt-oss-20b UD-Q4_K_XL (re-verify, n=5) | unsloth/gpt-oss-20b-GGUF | 10975 | n/a | 3 / 131072 | **42.19 ± 6.00** (n=5: 46.78/41.27/41.08/40.78/41.05) | 25.9-64.1 (noisy, cache-dependent) | 10.44/12.28GB (mid-generation) | 6.4/23GB used, no swap growth | code correct (needed `max_tokens 1500` — harmony reasoning channel burns tokens before the answer, 500 wasn't enough); essay ran 571 words vs the ~400 target (over by 43%, still coherent/structured) |
| 18 | 27B dense IQ4_XS + MTP, `spec-draft-n-max=4` | unsloth/Qwen3.8-27B-GGUF | 10975 | **4** | 3 / 131072 | **4.61 ± 0.45** (n=3: 4.66/4.36/4.81) — worse than row 12's n-max=2 | — | — | 20/23GB, swap 526MiB (up slightly from row 12's 438-360MiB baseline, still flat/no growth trend) | not evaluated (ruled out by speed alone) |
| 19 | 27B dense IQ2_S | unsloth/Qwen3.8-27B-GGUF | 10975 | n/a — **GGUF has no MTP/nextn tensors**, `--spec-type draft-mtp` fails cleanly (`context type MTP requested but model doesn't contain MTP layers`) | 3 / 131072 | **5.26 ± 0.45** (n=5: 5.32/5.57/5.19/5.12/5.12) | — | 9.33/12.28GB | swap-free (13MiB used, flat) | not evaluated |
| 20 | 27B dense Q3_K_XL | unsloth/Qwen3.8-27B-GGUF | 10975 | none | 3 / 131072 | **4.03 ± 0.13** (n=5: 3.98/4.05/4.09/4.05/3.96) | — | 9.75/12.28GB | swap-free (30MiB used, flat) | not evaluated |
| 21 | 27B dense Q3_K_XL + MTP | unsloth/Qwen3.8-27B-GGUF | 10975 | **2** | 3 / 131072 | **3.97 ± 0.14** (n=5: 4.03/3.81/4.09/3.85/4.09) — no gain over row 20, consistent with compute-bound finding | — | 8.65/12.28GB | 166MiB swap touched (minor, not the heavy contamination seen in row 7/pre-Round-6 Q4_K_XL run) | not evaluated |
| 22 | 27B dense HauhauCS-Aggressive Q2_K_P (**community fine-tune**, not unsloth/base line) | HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF | 10975 | none | 3 / 131072 | **4.17 ± 0.17** (n=5: 4.06/4.21/4.23/4.15/4.20) | — | 9.7/12.28GB | swap-free (104MiB used, flat) | coherent output on reverse-string sanity check, correct reasoning trace |
| 23 | 27B dense HauhauCS-Aggressive Q2_K_P + MTP (**community fine-tune**) | HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF | 10975 | **2** | 3 / 131072 | **3.31 ± 0.14** (n=5: 3.33/3.35/3.36/3.21/3.31) — *worse* than row 22, MTP tensors confirmed real (`creating MTP draft context`, clean init) | — | 8.9/12.28GB | 248MiB swap touched (minor) | not re-evaluated (already confirmed coherent at row 22) |
| 24 | 27B dense HauhauCS-Aggressive IQ2_M (**community fine-tune**) | HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF | 10975 | none | 3 / 131072 | **4.40 ± 0.02** (n=5: 4.38/4.40/4.41/4.40/4.42, tightest spread of any 27B run) | — | 9.72/12.28GB | swap-free (168MiB used, flat) | coherent output on reverse-string sanity check |
| 25 | 27B dense HauhauCS-Aggressive IQ2_M + MTP (**community fine-tune**) | HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF | 10975 | **2** | 3 / 131072 | **3.45 ± 0.20** (n=5: 3.31/3.71/3.31/3.37/3.56) — *worse* than row 24, MTP tensors confirmed real | — | 8.82/12.28GB | 270MiB swap touched (minor) | not re-evaluated (already confirmed coherent at row 24) |
| 26 | 27B EfficientThink Q2-LynnStyle + **DFlash2 draft** (`--model-draft` dflash2-Q8_0, **community fine-tune**) | nerkyor/Qwen3.8-27B-EfficientThink-...-DFlash2-GGUF | 10975 | `draft-dflash`, n_max=2 (real dflash tensors, `common_speculative_impl_draft_dflash` init clean, no missing-tensor warnings) | 3 / 131072 | **3.97 ± 0.82** (n=5: 3.02/3.80/4.39/4.64/4.00) | — | 11.52/12.28GB | 16-17/23GB, swap flat at 236MiB (pre-existing baseline, no growth) | coherent decorator-stacking code sample, on-topic |
| 27 | 27B EfficientThink Q2-LynnStyle, **no draft** (`--spec-type ngram-simple`, **community fine-tune**) | nerkyor/Qwen3.8-27B-EfficientThink-...-DFlash2-GGUF | 10975 | ngram-simple (no separate draft model needed) | 3 / 131072 | **3.81 ± 0.03** (n=5: 3.82/3.82/3.82/3.79/3.82, tightest spread on record) | — | 9.77/12.28GB | 14-15/23GB, swap flat at 233-240MiB | not re-evaluated (already confirmed coherent at row 26) |

**Model-card check:** unsloth's own guide (`unsloth/Qwen3.6-35B-A3B-MTP-GGUF/README.md`)
recommends exactly `--spec-draft-n-max 2` — matches our empirical optimum (row 3 vs 4/5).
**Important caveat from that same guide: `-np` (parallel) > 1 is not yet officially supported
with MTP** — our tests ran with `--parallel 3` and were stable/consistent, but this isn't
guaranteed upstream; if real concurrent-client instability shows up (multiple simultaneous
clients, not just sequential benchmarks), try `--parallel 1`.

## gpt-oss-20b: a real contender, not yet adopted

Row 16 is the first alternative model this session found that's actually competitive with the
Qwen 35B A3B+MTP champion: same throughput (~42 tok/s) with no speculative decoding, at half
the disk footprint and much lower RAM pressure. It is **not being adopted as the default yet**
because the round-3 evaluation was intentionally light (n=3 speed samples, one code-quality
check, no essay/constrained-writing check, no repeated-seed comparison) — the same bar every
other adopted config in this document had to clear (n=5-8 runs, both task types) hasn't been
applied here yet. Before switching the default:
- Run the full n≥5 speed benchmark and the essay-constraint quality check used everywhere else.
- Check whether external-draft-model speculative decoding (`-md`/`--model-draft`, pairing
  gpt-oss-20b with a small drafter) pushes it meaningfully past 42 tok/s — its architecture
  doesn't support model-native MTP, but classic speculative decoding is a separate mechanism
  and remains untried here.
- Confirm tool-calling actually round-trips correctly end-to-end (a real tool-call request/
  response cycle, not just template presence) since gpt-oss's harmony format is structurally
  different from Qwen's (separate `reasoning_content` channel).

If those hold up, gpt-oss-20b would be a strong case for a second officially-supported profile
(smaller footprint, comparable speed) alongside the 35B A3B — not necessarily a replacement,
since the two may have different quality profiles for complex agentic coding tasks that a
single code-completion + essay check can't fully capture.

## Round 4: gpt-oss-20b re-verified, 27B+MTP deep-dive (definitive)

**gpt-oss-20b holds up under full rigor** (row 17): n=5 speed run confirms ~42 tok/s (42.19 ±
6.00, in the same range as row 16's n=3 pass), VRAM/RAM checked under actual mid-generation
load (not just idle) and stayed light — 10.44/12.28GB VRAM, only 6.4GB host RAM, no swap. Two
real findings from the deeper pass:
- **Its harmony reasoning format burns output tokens before answering.** The first code-quality
  attempt with `max_tokens: 500` (same budget used elsewhere in this report) hit the limit
  entirely inside `reasoning_content` and never reached a visible answer — needed `max_tokens:
  1500` to get a complete, correct response. Anyone deploying this model needs a meaningfully
  larger `--predict`/`max_tokens` budget than Qwen needs for the same task.
- **Essay-length discipline is weaker**: asked for ~400 words, gpt-oss produced 571 (+43%),
  vs. Qwen's 413 (+3%) on the same prompt. Structure and coherence were still fine, just less
  tightly bounded to the word-count constraint.
- External-draft-model speculative decoding was *not* attempted (no small gpt-oss-family draft
  model exists publicly, and gpt-oss's tokenizer/architecture isn't a drop-in match for pairing
  with an unrelated small model) — noted as untried, not ruled out.
- Full end-to-end tool-call round-trip (actual function invocation, not just template presence)
  was still not exercised this round either — remains open before any adoption decision.

**gpt-oss-20b is confirmed as a genuinely strong, comparably-fast alternative to Qwen 35B
A3B+MTP with meaningfully lower resource usage** (about half the disk, a third of the host
RAM). It is **still not promoted to the default** pending the tool-call round-trip check and
an explicit decision from the user on whether they want a second profile or a replacement —
but the case for it is now on solid footing, not just a promising early read.

**27B+MTP deep-dive — conclusively ruled out on this hardware, and now well understood:**
- **The MTP head is real, not a degenerate fallback.** Server logs for the 27B+MTP container
  show `common_speculative_init_result: creating MTP draft context against the target model`
  with no missing-tensor errors — same clean initialization as the working 35B A3B case. The
  unsloth README for `Qwen3.8-27B-GGUF` confirms the base `Qwen/Qwen3.8-27B` model itself was
  "trained with multiple steps" of MTP, so (unlike the 35B A3B, which needed a dedicated
  `-MTP-GGUF` repo) the single standard 27B repo already carries working MTP tensors. No
  separate/better `-MTP-GGUF` sibling repo exists for the 27B from any reputable uploader
  (checked unsloth, bartowski) — the handful of repos with "MTP" in their name that do exist
  are unrelated community fine-tune/abliteration merges (DavidAU, HauhauCS, etc.), not vetted
  quantizer conversions, and were not tried.
- **The slowness is architectural, not a config or MTP-quality problem.** 27B dense activates
  all 27B parameters on every token; the 35B A3B MoE activates only ~3B. That's roughly a 9x
  compute gap per token, and it lines up almost exactly with what's measured: 35B A3B non-MTP
  ran at 39.8 tok/s (row 2) vs. 27B non-MTP IQ4_XS at 4.1 tok/s (row 11) — a 9.7x gap. MTP's
  speedup comes from amortizing the *verify* step over multiple drafted tokens, but the
  underlying forward pass a dense 27B model has to run every step is inherently ~9x more
  expensive than the MoE's, so there's a much smaller pool of "cheap" cycles for MTP to exploit
  here than on the 35B A3B.
- **`spec-draft-n-max` sweep confirms 2 is optimal for the 27B too** (row 18): n-max=4 measured
  4.61 ± 0.45 tok/s, worse than n-max=2's 5.4 ± 0.5 (row 12) — the same pattern seen on the 35B
  A3B (rows 3-5), where longer speculative drafts cost more than they save once the accept
  rate drops. Not swept further (6) given the clearly negative trend and RAM headroom getting
  tighter at higher n-max (available RAM dropped to 1.9GB during the n-max=4 run, vs. row 12's
  more comfortable margin at n-max=2).
- **Alternate-uploader quant search**: `bartowski/Qwen3.8-27B-GGUF` exists as a second
  legitimate source, but was not benchmarked this round (time budget) — worth a quick try if
  someone wants to squeeze marginal gains, but given the ~9x architectural gap above, no
  plausible quant swap closes that distance. Not expected to change the conclusion.
- **Conclusion: nothing gets 27B+MTP meaningfully above ~5-6 tok/s on this hardware.** This
  isn't a solvable config problem — it's the dense-model compute cost hitting the CPU/GPU-split
  hardware ceiling. Revisit only if (a) the WSL memory ceiling gets raised (§"WSL memory
  ceiling" above) and more of the model can live in VRAM instead of CPU RAM, which changes the
  cost structure enough to be worth re-measuring, or (b) external-draft speculative decoding
  (a small non-MTP Qwen model as `-md` drafter, paired with the 27B as the main model) is tried
  as a different mechanism — untested this round, flagged as the one unexplored lever left.

## Round 5: complex-task code quality (LRU cache with TTL + threading)

The "reverse a string" task used everywhere above is too trivial to differentiate models —
it doesn't exercise correctness edge cases, concurrency, or algorithmic complexity
requirements. This round replaced it with a genuinely hard, objectively verifiable prompt,
run at seed=42/temp=0.6/clean context against every candidate that was still viable, and
**each model's generated code was actually executed** (not just read) against its own
demo plus 10 independent edge-case tests (capacity=1, TTL=0, missing key, `__contains__`
not affecting recency, mixed get/put eviction order).

**Prompt** (verbatim, given to every model): implement a thread-safe LRU cache with
O(1) `get`/`put`, capacity-based eviction, optional per-key TTL using an *injectable clock*
(not `time.time()` internally), `__len__`, and a `__contains__`/`contains` that does not
count as a "use" for recency purposes — plus a demonstration/test in the same response.

| Model | Config | Result |
|---|---|---|
| **Qwen 35B A3B Q4_K_XL+MTP** (row 3 config) | `spec-draft-n-max 2`, same flags as row 3 | **Flawless.** Correct dict + doubly-linked-list O(1) design, single lock guarding every method consistently, clock injected and used consistently throughout. Its own demo AND all 10 independent edge-case tests passed with zero fixes needed. Needed a bigger token budget than the trivial task (14000, since its `preserve_thinking:false` system-prompt override apparently doesn't suppress reasoning on the `/v1/chat/completions` endpoint the way it does elsewhere — burned ~30k reasoning tokens before an 8k-token answer). |
| **Devstral-Small-2507** (row 15 config, non-MTP compose) | same as row 15 | **Broken.** Crashes immediately on its own basic test: forgot `import time` while defaulting `clock` to `time.time`. After patching that one line, it crashes again on the very first `get()` call with `TypeError: '<' not supported between instances of 'float' and 'NoneType'` — its `_get_ttl()` helper unconditionally `return None`, so TTL is entirely unimplemented despite being an explicit, detailed requirement in the prompt. A real functional regression, not a style nitpick. |
| **gpt-oss-20b** (row 16/17 config) | same as row 16/17, `max_tokens` bumped to 6000 | **Core logic correct, delivery rough.** Its own demo had a syntax error (mismatched brackets: `range(4))]`) that had to be hand-patched before it would even run. Once fixed, all 10 independent edge-case tests passed — the underlying cache logic (capacity, eviction, TTL with injected clock, `__contains__` not affecting recency) is genuinely correct. Its *own* concurrency smoke test then failed an assertion, but that's a flaw in the demo it wrote, not the cache: it ran 4 threads inserting 40 unique keys into a capacity-5 cache and asserted every thread could always read back its own just-written key, which is guaranteed to fail sometimes under correct LRU semantics (another thread's insert legitimately evicts it) — a test-design bug, not a thread-safety bug. |
| Qwen 27B dense IQ4_XS+MTP (row 12 config) | same as row 12 | **Not completed — abandoned for a strong practical reason.** Already disqualified on raw speed (~5.4 tok/s ceiling, §8), and this harder prompt confirmed why it's not viable even beyond that: two attempts (4000 and 8000-token budgets) both hit the limit entirely inside its reasoning channel before producing a single character of visible answer — at ~5 tok/s, getting a complete response would need a budget large enough to take 30+ minutes per attempt. Not worth the time for a model already ruled out. |

**Headline verdict**: on a task hard enough to actually separate them, **Qwen 35B A3B+MTP
is still the strongest of the group** — the only one that needed zero fixes and passed
every test on the first working attempt. gpt-oss-20b's *cache logic* is equally correct
once its trivial syntax bug is patched, so on pure algorithmic correctness it's a close
second — but Devstral's TTL implementation is genuinely broken (not a partial or edge-case
bug, the whole feature never worked), which is a meaningful mark against it as a coding
model regardless of its confirmed tool-calling support.

This reinforces, with harder evidence, the same shape of conclusion Round 4 reached on
speed grounds alone: Qwen 35B A3B+MTP remains the safest default; gpt-oss-20b remains a
credible second profile pending its still-open tool-call round-trip check; Devstral and
the 27B stay ruled out.

## Round 6: 9B dense sanity check, killing the memory-bandwidth hypothesis, and closing out Q4_K_XL/dflash/ngram

**9B dense model** (`Qwopus3.5-9B-v3.Q4_K_M.gguf`, pre-existing on disk, no MTP, `--parallel 3`
/ `--ctx-size 393216`, otherwise the same common flags): **44-48 tok/s (5 samples: 44.03, 43.71,
47.9, 48.22, 47.64)** — actually *faster* than the 42 tok/s champion, because at 5.63GB it fits
almost entirely in VRAM (10.96/12.28GB used) with no `--fit-target` cap forcing CPU offload.
This confirms the real driver of "dense = slow" on this host isn't dense-ness itself, it's
*how much of the model has to live in CPU RAM* — a dense model small enough to fit in VRAM is
fine. Quality could not be checked: like gpt-oss, it has a reasoning channel, but far more
aggressive — it burned the *entire* budget in `reasoning_content` with zero visible answer at
both 2000 and 6000 max_tokens on the LRU-cache task, never producing a response. Not worth
chasing further as a side data point; noted as a limitation, not benchmarked for quality.

**27B IQ3_S — kills the memory-bandwidth hypothesis.** The working theory going into this round
was that dense-model slowness on this host is dominated by memory-bandwidth (bytes of weight
read per token from CPU RAM), so a smaller quant should speed things up even with unchanged
FLOPs. Tested `unsloth/Qwen3.8-27B-GGUF:UD-IQ3_S` (11.21GB) without the `--fit-target 1536`
constraint used elsewhere, so most of it (10.18/12.28GB) actually landed in VRAM this time —
and it was still only **4.29 ± 0.32 tok/s without MTP (n=5: 4.44/4.28/4.26/4.28)**, and **3.97 ±
0.65 tok/s with MTP** (n=5: 4.08/4.06/3.82/4.08/3.79) — MTP made it *slightly worse*, and
neither beats the IQ4_XS numbers already on record (row 11/12: 4.1/5.4 tok/s). Even with the
weights mostly in VRAM, throughput barely moved. **Conclusion: the 27B's slowness is genuinely
compute-bound (FLOPs), not memory-bandwidth-bound** — smaller quants can't fix it because the
bottleneck isn't bytes read, it's the arithmetic itself, consistent with the ~9x active-param
gap already established in Round 4. This closes the "maybe a smaller quant helps" question with
a clean no, and refines the earlier hypothesis (§8) from "probably compute-bound" to
confirmed-by-experiment.

**"dflash 2" identified.** This build (10975) exposes `--spec-type` values including
`draft-dflash` (alongside `draft-mtp`, `draft-eagle3`, `draft-dspark`, and several `ngram-*`
variants) — this is very likely what "dflash 2" referred to. It's a distinct speculative-decoding
head architecture from MTP, and — like eagle3/dspark — requires the target GGUF to carry the
matching draft tensors; Qwen3.8-27B was not found to ship dflash tensors (only MTP, per Round 4),
so `--spec-type draft-dflash` was not expected to initialize cleanly against it and was not
pursued further within this round's time budget. Flagging this as **not conclusively tested** —
worth a quick empirical check (does the server refuse to start, or silently no-op?) in a future
round rather than assumed.

**Q4_K_XL/Q3_K_XL 27B and ngram-simple.** Downloads for both K-quants (16.35GB + 12.24GB) initially
died mid-transfer when the initiating SSH session closed (background `curl` jobs need `setsid`,
not just `&`, to survive that reliably — worth remembering for future rounds); once resumed
reliably, Q4_K_XL and ngram-simple were completed within this same round (see results directly
below). Q3_K_XL was deferred at the time (see Round 7 for its later completion).

Closing out the remaining queue items from this round: Q4_K_XL for 27B, ngram-simple, and the
draft-dflash tensor check. Base image/build/common flags unchanged from prior rounds; `--parallel 3`,
`--ctx-size 393216` (131072/slot) throughout.

- **27B dense Q4_K_XL** (`unsloth/Qwen3.8-27B-GGUF`, 17.5GB), no spec decoding: **3.59 ± 0.09 tok/s** (n=5: 3.64/3.58/3.57/3.58/3.55) — *worse* than IQ4_XS's 4.1, confirming (again) that a bigger K-quant doesn't help a compute-bound dense model; if anything it adds RAM pressure for no benefit.
- **27B dense Q4_K_XL + MTP** (`--spec-type draft-mtp --spec-draft-n-max 2`): MTP head initializes cleanly (`creating MTP draft context`, no missing tensors) but the run is **swap-contaminated** (1.1GB swap in use, RAM at 22/23GB) — **5.84 ± 0.6 tok/s** (n=5: 6.33/6.19/5.16/5.7/5.81) is not a clean number, consistent with but not better than the already-adopted IQ4_XS+MTP result (row 12, 5.4 tok/s, verified swap-free). A swap-free re-verification was not obtained this round; Q3_K_XL was deferred to Round 7 (rows 20-21), where it came back clean and swap-free at 4.03/3.97 tok/s — well below this contaminated 5.84 figure, so the swap contamination here is very likely inflating this number rather than reflecting real throughput. Treat row "27B dense Q4_K_XL + MTP" above as unverified, same caution as row 6/30.2.
- **`--spec-type draft-dflash` on the 27B**: loads without error, but logs show the model's `blk.64.nextn.*` tensors (the MTP/"nextn" head) being marked `unused ... ignoring` — dflash expects a different tensor structure than MTP's nextn layer, which this GGUF doesn't have. No draft-context init log line appears (unlike the clean `creating MTP draft context` seen with `draft-mtp`), and speed matches the no-spec baseline (3.15 tok/s, same ballpark as 3.59) — **conclusively a silent no-op on this model**, not a crash, not a working alternative. "Dflash 2" is very likely `--spec-type draft-dflash` (confirmed to exist in this build alongside `draft-eagle3`, `draft-dspark`, `ngram-simple`, `ngram-map`), but no publicly available 27B GGUF carries the tensors it needs.
- **`--spec-type ngram-simple` on the 27B Q4_K_XL**: loads cleanly, **3.6 ± 0.04 tok/s** (n=3: 3.6/3.6/3.68) — indistinguishable from the no-spec baseline. Ngram-based speculation relies on the prompt/response containing repeated token sequences to draft from; a from-scratch code-generation prompt doesn't offer much of that, so there's nothing for it to exploit here. Not tested on Devstral this round (time budget).
- **Conclusion**: none of these three items change the "27B: closed" verdict (§8) — if anything they reinforce it from new angles (bigger quant hurts, dflash tensors don't exist for this model, ngram speculation has nothing to draft from on fresh code-gen prompts). The one lever still genuinely untried is external draft-model speculative decoding (`-md` with a small separate Qwen model as drafter) and Devstral+ngram-simple.

## Round 7: remaining 27B quants (IQ2_S, Q3_K_XL) and a community fine-tune (HauhauCS)

Closes out the last open 27B quant questions from Round 6, plus an ad-hoc check of a
community-repackaged 27B fine-tune whose repo name happened to include "MTP". All MTP runs
this round use **`--spec-type draft-mtp --spec-draft-n-max 2`** specifically (the now-standing
canonical n-max value for every MTP measurement going forward — n=2 was already this session's
default per row 3/12, so no methodology change was needed, just confirmation). `--parallel 3` /
`--ctx-size 393216` (131072/slot) throughout, same common flags as every prior round.

- **IQ2_S** (row 19): **5.26 ± 0.45 tok/s**, no MTP variant possible — this specific unsloth
  GGUF simply doesn't carry MTP/nextn tensors (clean `context type MTP requested but model
  doesn't contain MTP layers` error, not a hang or crash). Interesting *because* it's the
  fastest 27B number on record without MTP, ahead of IQ4_XS (row 11, 4.1) and IQ3_S (row 18
  section, 4.29) — the very aggressive 2-bit quant appears to reduce compute enough to matter
  here, unlike the IQ3_S/IQ4_XS/Q3_K_XL/Q4_K_XL cluster that all landed in the same
  ~4 tok/s band regardless of size. Still far below the 35B A3B's 42 tok/s and not remotely
  competitive on quality grounds expected from 2-bit quantization (not evaluated for quality
  this round — ruled out on the "no MTP support" constraint alone, since MTP is a hard
  requirement for this profile).
- **Q3_K_XL** (rows 20-21): **4.03 ± 0.13 tok/s (MTP off) / 3.97 ± 0.14 tok/s (MTP on, n=2)** —
  both clean, swap-free measurements (VRAM 9.75GB/8.65GB, RAM swap flat or only minimally
  touched). MTP makes no measurable difference (within noise, actually very slightly worse),
  matching the compute-bound pattern established in Round 6 for IQ3_S. This is also the clean,
  swap-free number the Round 6 Q4_K_XL+MTP result (5.84 tok/s) should be compared against —
  since Q3_K_XL undercuts it by ~30%, the Q4_K_XL+MTP figure is very likely swap-inflated, not
  a genuine best-in-class 27B result.
- **HauhauCS-Aggressive** (rows 22-25): a community fine-tune/abliteration merge from
  `HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF`, flagged in earlier rounds as
  "found but not tried, not a vetted quantizer conversion." Tested here on explicit request.
  Unlike IQ2_S, **both quants of this repo genuinely carry MTP/nextn tensors** — clean
  `creating MTP draft context` init on both Q2_K_P and IQ2_M, no missing-tensor errors. Speed:
  Q2_K_P 4.17 (off) / 3.31 (on, n=2); IQ2_M 4.40 (off) / 3.45 (on, n=2) — MTP is *worse* than
  off on both, same compute-bound story as every other 27B quant tested. IQ2_M's no-MTP number
  (4.40 ± 0.02) is the tightest-spread 27B result on record, and both quants produced coherent,
  on-topic output on the reverse-string sanity check (not a full quality pass). **This is a
  fine-tune/abliteration of the base model, not an official unsloth quantization** — its speed
  profile matches the base model closely (as expected, quantization/fine-tuning doesn't change
  active-param count), so it doesn't change the "27B: closed" verdict, but it's now an actual
  data point instead of an unexplored repo name.
- **Conclusion**: no 27B config or quant found this round beats the already-adopted 35B A3B
  champion, and none changes the compute-bound diagnosis from Round 6. IQ2_S is the fastest
  27B-without-MTP number on record but can't run MTP at all with this file; Q3_K_XL confirms
  (again, cleanly) that MTP doesn't help this dense model; HauhauCS's community MTP tensors
  work exactly like the base model's — real, but not a game-changer. The "27B: closed"
  verdict stands.

## Round 8: real DFlash2 tensors (nerkyor 27B fine-tune) vs ngram-simple; Ornith-1.5-35B-A3B-DFlash2 ruled out (wrong format)

User-authorized final phase, testing two specific community repos linked directly in chat.

**`jzinno/Ornith-1.5-35B-A3B-DFlash2` — ruled out before download, incompatible format.**
Checked via the HF API (`GET /api/models/jzinno/Ornith-1.5-35B-A3B-DFlash2`) before spending any
bandwidth: `library_name: sglang`, `architectures: ["DFlash2DraftModel"]`, and the file list is
`model.safetensors` (BF16, ~526M params) + `config.json`/`manifest.json` — **no `.gguf` file
anywhere in the repo**. This is a draft model built for the **sglang** runtime, not llama.cpp.
The deployed image (`ghcr.io/ggml-org/llama.cpp:full-cuda`) only loads GGUF files, so this repo
cannot be benchmarked on this stack without an out-of-scope safetensors→GGUF conversion (which
would also need llama.cpp to support whatever custom `DFlash2DraftModel` architecture this is,
which it does not). No download, no benchmark — documented here as checked-and-incompatible,
not silently skipped.

**`nerkyor/Qwen3.8-27B-EfficientThink-...-DFlash2-GGUF` (Q2-LynnStyle tier) — real DFlash2
tensors, genuinely tested.** This is a community fine-tune/quant repo (base: the same
Qwen3.8-27B lineage as the other 27B rows in this doc; card branding includes "EfficientThink"
and "Uncensored", multi-source SFT/SimPO lineage per the repo name) that separately publishes
its own DFlash2 draft GGUF (`dflash2-qwen38-27b-Q8_0.gguf`, 2.06GB) alongside the ~13GB main
model, plus separate optional MTP draft files. The repo's own `manifest.json` states explicitly:
*"Choose either Q8_0 or Q4_K_M DFlash2 with llama.cpp `--model-draft` and `--spec-type
draft-dflash`; never pass both and never use `draft-mtp`."* — i.e. **dflash and MTP are
mutually exclusive by the file's own design**, and `--spec-type` on this llama.cpp build
(confirmed via `--help`) is a single-choice flag (`none,draft-simple,draft-eagle3,draft-mtp,
draft-dflash,draft-dspark,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache`) — **it
is structurally impossible to stack two `--spec-type` strategies simultaneously on this build**,
so the "combined" test the user asked to attempt if possible was not attemptable: not a build
limitation specific to this model, but a hard single-selector constraint in llama.cpp's CLI
itself. dflash-alone and ngram-alone were each tested in full instead.

- Both downloaded files verified byte-exact against the manifest's published SHA256 (main GGUF
  `8a84f7ef...d21922`, dflash2 Q8_0 draft `1086ea5d...1335a`) — genuine, unmodified download.
- **DFlash2** (`--model-draft dflash2-qwen38-27b-Q8_0.gguf --spec-type draft-dflash
  --spec-draft-n-max 2`, row 26): loads with a clean, real
  `common_speculative_impl_draft_dflash: adding speculative implementation 'draft-dflash'`
  init (`n_max=2, n_min=0, p_min=0.00, block_size=8, ...`) — this is a genuinely working
  dflash implementation, unlike Round 6's silent no-op on the unsloth base GGUF (which had no
  dflash tensors at all). **3.97 ± 0.82 tok/s** (n=5: 3.02/3.80/4.39/4.64/4.00 — noisier than
  most 27B rows, no obvious cause, possibly draft-acceptance-rate variance run to run). VRAM
  ran tight (11.52/12.28GB, both main + draft loaded) but stable; RAM swap flat at 236MiB
  throughout (pre-existing baseline level seen across every clean run this session, no growth
  — confirmed swap-free via 5s-interval `free -h` polling).
- **ngram-simple** (`--spec-type ngram-simple`, no separate draft model, row 27): loads clean,
  **3.81 ± 0.03 tok/s** (n=5: 3.82/3.82/3.82/3.79/3.82) — the tightest spread of any 27B run in
  this document, essentially indistinguishable from the dflash mean (3.97) and from the
  no-spec 27B baseline band (~3.6-4.4) established since Round 6. Swap flat at 233-240MiB, VRAM
  much lower than dflash (9.77GB, no second model loaded).
- **Quality sanity check**: a decorator-stacking prompt against the dflash config produced
  coherent, on-topic, syntactically correct Python (not a full capability eval, same bar as
  prior community-fine-tune rows).
- **Conclusion**: DFlash2 is real on this repo (confirmed via clean draft-context init logs,
  not a silent no-op like the base-model dflash test in Round 6) but delivers **no measurable
  speedup** over ngram-simple or the established no-spec 27B baseline — both land in the same
  ~3.8-4.0 tok/s compute-bound band as every other 27B config tested since Round 6, and dflash
  costs meaningfully more VRAM (11.52 vs 9.77GB) for the same throughput. This is the same
  compute-bound story repeated a fourth way: neither MTP (Rounds 6-7), nor ngram (Round 6-8),
  nor now a genuinely-working DFlash2 draft model change the fundamental 27B-dense-on-12GB
  bottleneck. The "27B: closed" verdict stands; DFlash2 does not reopen it. Ornith-1.5-35B is
  not a substitute data point for the 35B A3B+MTP champion — it was never benchmarked, ruled
  out purely on format incompatibility before any GPU time was spent on it.

## Round 9: 9B dense model — quality re-check with larger budget, provenance, spec-decoding — ruled out

Round 6 flagged the pre-existing `Qwopus3.5-9B-v3.Q4_K_M.gguf` as fast (44-48 tok/s) but
untested for quality: it burned its entire token budget inside `reasoning_content` at both
2000 and 6000 `max_tokens` on the LRU-cache-with-TTL task, never producing a visible answer.
This round retested it properly per explicit request, and rules it out with a real finding
(not just an unresolved budget question).

**Provenance resolved.** The file's origin was undocumented going into this round. Web search
identified the source repo: `Jackrong/Qwopus3.5-9B-v3-GGUF`, file
`Qwopus3.5-9B-v3.Q4_K_M.gguf` — base model `unsloth/Qwen3.5-9B` with LoRA adapters, a
reasoning-tuned fine-tune (`<think>` chat template) targeting competitive programming/math.
The local file on gpu-host was verified **byte-exact** against the HF-hosted copy (both
5,629,105,024 bytes via `curl -sIL` content-length). The repo also ships a `mmproj.gguf`
(vision projector) alongside the text GGUFs, but that file is not present locally — no vision
capability for this specific on-disk setup.

**Larger budget did produce a visible answer, but the code is genuinely broken.** Re-ran the
same LRU-cache-with-TTL prompt used in Round 5/6, `max_tokens: 16000` (vs. the earlier
2000/6000 that fully starved it). This time it completed: `finish_reason: stop`,
`completion_tokens: 14611` (52087 chars of `reasoning_content`, 8340 chars of visible
`content`) — so the fix for the previous round's finding is simply "give it enough budget";
`--chat-template-kwargs preserve_thinking:false` does not suppress the reasoning channel on
`/v1/chat/completions` for this model (same behavior already seen with the 35B A3B in Round 5).
However, the generated code itself does not run:
- The class is declared as `class LRUCacheWithTTL(threading.Lock):` — `threading.Lock` is a
  C-implemented type and cannot be subclassed (`TypeError: type '_thread.lock' is not an
  acceptable base type`). The model's own demo crashes immediately at class-definition time.
- After patching that line out (dropping the bogus inheritance, same "patch the trivial bug
  and test the real logic" methodology used for gpt-oss-20b/Devstral in Round 5), the cache
  still fails on its **first real `get()` call**: `AttributeError: 'LRUCacheWithTTL' object
  has no attribute '_move_to_end'` — `get()` calls a method that is never defined anywhere in
  the class. This is not a demo-script bug (like gpt-oss's bracket typo) or a missing-feature
  gap (like Devstral's TTL) — it's the core `get()` path being fundamentally broken, worse than
  either previously-rejected model. Not pursued further (no edge-case test suite run) since the
  primary method doesn't work at all.

**No speculative decoding available, confirmed via clean log message.** Tried
`--spec-type draft-mtp --spec-draft-n-max 2` against this exact GGUF: clean
`common_speculative_init_result: creating MTP draft context` init immediately followed by
`llama_init_from_model: context type MTP requested but model doesn't contain MTP layers` and
`failed to create MTP context` — the server refuses to start, a clean rejection (same failure
shape as row 19's IQ2_S 27B), not a hang or silent no-op. This confirms Round 6's "no MTP
tensors" note with an actual log capture. Note this is expected: `Jackrong/Qwopus3.5-9B-v3-GGUF`
is the plain reasoning-tuned repo; a separate sibling repo,
`Jackrong/Qwopus3.5-9B-Coder-MTP-GGUF`, does ship MTP tensors for a *different* (coder-focused)
9B variant — but that is not the file already on disk, and downloading/adopting a different,
never-benchmarked model was out of scope for this round (the task was to verify the
pre-existing file). `--spec-type draft-dflash` was not exhaustively tested (no companion draft
GGUF exists for this repo either), consistent with every other model in this document that
lacks dedicated draft tensors.

**Verdict: 9B model rejected, no profile created.** Two independent disqualifying findings:
(1) the reasoning channel needs a much larger budget than any other profile in this document
(16000 tokens for a trivial-by-comparison task, vs. the 35B's already-large 14000) to produce
anything at all, and (2) even with that budget, the generated code is broken at the most basic
level (`get()` cannot run) — worse than every previously-rejected candidate. Speed alone (44-48
tok/s) is not enough to justify a profile when the model cannot reliably produce working code.
`docker/docker-compose-gpu-qwen-9b.yml` was intentionally **not created**.

## Round 10: end-to-end re-verification of all shipped profiles on gpu-host

Re-tested every profile that ships in `docker/` today — not trusting old benchmark numbers,
actually booting each one fresh, checking `/health`, and sending one real completion request.
Config values below reflect the final sampling/context parameters in place at test time
(`--parallel 2`, Qwen profiles at `preserve_thinking:true` / temp 0.6 / top_p 0.95 / top_k 20 /
min_p 0 / presence_penalty 0 / repeat_penalty 1.0 / `--predict 81920` / 196608 ctx-per-slot;
gpt-oss-20b at temp 1.0 / top_p 1.0 / top_k 0 / `reasoning_effort: high` / 131072 ctx-per-slot
via `--ctx-size 262144`).

- **35B A3B + MTP (default)**: booted and served correctly. `/health` → `{"status":"ok"}`.
  Smoke-test completion ("Say OK and name the capital of France") returned
  `"OK, the capital of France is Paris."` at 42.7 tok/s generation, MTP draft acceptance
  125/148 — matches the documented champion numbers.
- **27B dense IQ4_XS + MTP**: booted and served correctly (healthy in ~27s — the small quant
  loads fast). Smoke test returned `"OK, Paris."` at ~5.0 tok/s, MTP draft acceptance 29/34 —
  matches the documented ~5.4 tok/s figure within run-to-run noise.
- **27B dense HauhauCS-Aggressive IQ2_M ("uncensored"), no MTP**: the model file
  (`Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-IQ2_M.gguf`, 9.61GB) had been deleted from
  gpu-host's disk per the disk-budget discipline noted at the end of this document — first boot
  attempt failed cleanly (`gguf_init_from_file: failed to open GGUF file ... No such file or
  directory`), not a config bug. Re-downloaded via `launch-server.sh` (which handles this
  automatically in normal use), then booted and served correctly: `/health` → `{"status":"ok"}`,
  smoke test returned `"OK. The capital of France is Paris."` at 4.40 tok/s — matches the
  documented figure exactly.
- **gpt-oss-20b**: model file (`gpt-oss-20b-UD-Q4_K_XL.gguf`) had also been deleted per the same
  disk discipline; re-downloaded (11.87GB) and re-tested. Booted and served correctly, smoke
  test returned `"OK, the capital of France is Paris."` at 51.2 tok/s (326 completion tokens,
  most spent in the harmony `reasoning_content` channel as expected with
  `reasoning_effort: high`).
- **`scripts/docker/launch-server.sh` container-name bug found and fixed**: the script used to
  hardcode `CONTAINER_NAME="llama-cpp-gpu"` for every non-CPU profile, but three of the four GPU
  compose files run under a different `container_name:` (`llama-cpp-gpu-qwen-27b-mtp`,
  `llama-cpp-gpu-qwen-27b-uncensored`, `llama-cpp-gpu-gpt-oss-20b`). The script's own
  readiness-wait (`docker logs -f "$CONTAINER_NAME"`) then failed to attach (`Error response
  from daemon: No such container: llama-cpp-gpu`) and reported `Container stopped unexpectedly`
  **even when the real container was running and healthy** — confirmed directly: `docker ps`
  showed `llama-cpp-gpu-qwen-27b-mtp` `Up` at the exact moment the script printed its false
  error. Found during this round's testing and fixed the same day: `CONTAINER_NAME` is now
  derived from each compose file's actual `container_name:` line via `grep`, with the old
  hardcoded name kept only as a fallback if that line is somehow missing.
- **A note on parallel launches**: `launch-server.sh` deliberately stops every known profile
  container at the start of each run (`docker stop llama-cpp llama-cpp-gpu ...` — the full
  current list) before starting its own, to avoid two models fighting over the single 12GB GPU.
  This round briefly launched two profiles' downloads concurrently to save wall-clock time; the
  second launch's own stop-everything step correctly tore down the first once its download
  finished, which is the intended behavior, not a bug — profiles were still verified strictly
  one-at-a-time on the GPU.

Final state left running: see "State left on gpu-host" at the end of this document (updated).

## Round 11: final LLM-capability evaluation — reasoning, math, programming, vision — all 4 shipped profiles

Last phase of this investigation. Every profile that ships in `docker/` today
(35B A3B+MTP, 27B dense+MTP, 27B "uncensored" HauhauCS-Aggressive, gpt-oss-20b) was given the
same fixed set of three tasks, one request per task per model, at `temperature 0.6` (`1.0` for
gpt-oss-20b, its own profile default) and `max_tokens: 4000` (generous enough to survive each
model's reasoning-channel overhead without truncating the visible answer). Vision support was
checked via `/props` `modalities` rather than an actual image request, per instructions — none
of the four ship an `mmproj` file, so no vision test was forced on any of them.

**Tasks:**
- **Reasoning** — classic chickens-and-rabbits word problem (35 heads, 94 legs). Correct
  answer: chickens=23, rabbits=12.
- **Math/calculation** — `(17 * 23 - 15^2) / 4 + sqrt(144)`. Correct answer: 53.5.
- **Programming** — `two_sum(nums, target)`, O(n) single-pass hash-map, returning indices (not
  values), explicitly required to handle duplicate values and a no-solution case. Verified by
  **actually running** each model's own code (not just reading it) against 4 assertions: the
  model's own 3 demo cases plus one independent case (`[-3, 4, 3, 90], target=0 → (0, 2)`).

### Results

| Model | Reasoning | Math | Programming | Vision |
|---|---|---|---|---|
| 35B A3B+MTP | Correct (23/12), clean algebra | Correct (53.5) | **Pass** — all 4 assertions, own demo included duplicate + no-solution cases | `vision: false`, no mmproj — not applicable |
| 27B dense+MTP | Correct (23/12) | Correct (53.5) | **Pass** — all 4 assertions | `vision: false`, no mmproj — not applicable |
| 27B "uncensored" (HauhauCS) | Correct (23/12) | Correct (53.5) | **Pass** — all 4 assertions | `vision: false`, no mmproj — not applicable |
| gpt-oss-20b | Correct (23/12) | Correct (53.5) | **Pass** — all 4 assertions | `vision: false`, no mmproj — not applicable |

**Verdict: all four shipped profiles pass all three capability checks cleanly.** Every model
produced correct, working answers on the first attempt, no patches needed (unlike the 9B in
Round 9, or Devstral/gpt-oss's own demo bugs seen in Round 5 on the much harder LRU-cache task).
This is expected and reassuring rather than surprising: chickens-and-rabbits, a 6-step
arithmetic expression, and a textbook two-sum are all well within reach of every model tested
here — the point of this round was to confirm there's no basic-capability regression across the
final profile set before closing out the investigation, not to re-discover the harder
differentiation already established by the LRU-cache-with-TTL task in Round 5 (where the 35B
A3B was the only model to pass with zero fixes). No profile is disqualified or re-ranked by
this round; the Round 5 findings on relative code-quality ranking still stand.

Token usage note: the two 27B profiles needed far fewer completion tokens per task (300-900)
than the 35B A3B (1700-2000) or gpt-oss-20b (1100-2300) — consistent with `preserve_thinking`
behavior differing by chat template/model rather than task difficulty; none came close to the
4000-token ceiling, so no answer was truncated.

Champion (35B A3B+MTP) was restored and re-verified healthy (`/health` → `{"status":"ok"}`)
after this round, consistent with every prior round's end state.

## Recommendation for `test-35b-mtp-improvements`

**Adopt row 3**: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL` +
`--spec-type draft-mtp --spec-draft-n-max 2`, keeping `--parallel 3` / `--ctx-size 393216`
(131072/slot) as in the current setup. This is the only config with solid, repeated evidence,
verified quality, and it matches the quantizer's own official recommendation.

Compose flag changes needed in `docker-compose-gpu-qwen-35b-a3b-mtp.yml`:
- `--draft-max 2` → `--spec-type draft-mtp` + `--spec-draft-n-max 2`
- `--no-mmap --mlock` → `--load-mode mlock`
- Document that this requires updating the base image (`docker pull ghcr.io/ggml-org/llama.cpp:full-cuda`) before deploying.

**IQ quants ruled out** (row 10): IQ4_NL+MTP is slower than Q4_K_XL+MTP (37.4 vs 42.0 tok/s)
despite being smaller — no reason to switch.

**27B+MTP still not recommended as the default**, and Round 7 closes out the remaining open
quant questions on this point. The previously-reported +92%/30.2-tok/s baseline (row 6) is
itself suspect (likely the same env-var mislabeling bug that hit rows 4/5); the Round 6
Q4_K_XL+MTP figure (5.84 tok/s) is now also suspect, since it was swap-contaminated and the
clean, swap-free Round 7 Q3_K_XL+MTP number (3.97 tok/s, rows 20-21) came in ~30% lower under
otherwise comparable conditions. Across every quant now tested clean and swap-free — IQ4_XS
(4.1/5.4), IQ3_S (4.29/3.97), Q3_K_XL (4.03/3.97), and the HauhauCS community fine-tune
(4.17-4.40 off / 3.31-3.45 on) — MTP gives at best a small, inconsistent gain (IQ4_XS) and at
worst makes things slightly worse (every other quant), all far below the 35B A3B's 42 tok/s.
IQ2_S is the one outlier worth noting: 5.26 tok/s without any MTP support at all, the fastest
27B-without-MTP number on record, but not enough on its own to reopen the 27B question given
the 2-bit quality tradeoff and the lack of an MTP path for this file. A 27B *dense* model on
12GB VRAM / 23GB RAM is simply CPU/RAM-bound regardless of MTP or quant choice. Worth retrying
if the WSL memory ceiling gets raised (see above), but not before.

**DeepSeek/MiniMax ruled out** for this use case — see dedicated section above.

## Round 12: 27B reliability-over-speed follow-up (thinking ON, large predict budget, external draft model)

Explicit user request: keep thinking mode ON for the 27B profile (already the shipped
config, not up for debate this round) and land on a config that never runs out of
reasoning budget mid-thought on a hard coding task, even if it's slow — speed is no longer
the goal.

**1. Re-ran the exact Round 5 LRU-cache-with-TTL prompt against the shipped config
as-is** (thinking on, `--predict 81920`, temp 0.6/top_p 0.95/top_k 20/min_p 0/
presence_penalty 0/repeat_penalty 1.0, `--parallel 2`, MTP `draft-mtp` n-max 2) — the same
prompt that failed outright in Round 5 at the much smaller 4000/8000-token budgets in place
back then. Result:

- **Completed cleanly within budget**: `finish_reason: stop`, `completion_tokens: 31878`
  (of the 81920 ceiling) — nowhere close to truncation.
- **Reasoning vs answer split**: ~110,528 chars of `reasoning_content` (~27.6K tokens) vs
  11,368 chars of visible `content` (~2.8K tokens) — the model reasoned for a long while but
  did leave itself room to answer, unlike the Round 5 failure.
- **Wall-clock: 8467.6s (~141 minutes / 2h21m)**, generation speed 3.8-5.9 tok/s
  (fluctuating with system load, consistent with the documented 5.4 tok/s ceiling), MTP
  draft acceptance 0.687 (18447/26864 draft tokens accepted).
- **Code quality: flawless.** Extracted the generated Python (dict + doubly-linked-list +
  min-heap for lazy TTL expiry, single `threading.Lock` guarding every method, clock
  injected and used consistently, `contains()`/`__contains__` correctly not touching
  recency). Ran its own embedded demo (`All tests passed.`) AND all 10 independent
  edge-case tests used throughout this document (capacity=1, ttl=0, missing key/default,
  `__contains__` not affecting recency, mixed get/put eviction order, `__len__`, key-update
  reuse, injected-clock expiry, no-TTL entries never expiring, an 8-worker/50-iteration
  concurrency smoke test) — **zero fixes needed, all passed.**
- **Conclusion: the shipped config already satisfies the reliability requirement.** The
  Round 5 failure was specific to that round's much smaller 4000/8000-token budgets, not to
  thinking mode itself or the 27B's reasoning behavior in general — raising `--predict` to
  81920 (already done in an earlier commit, before this round started) already fixed it.
  Nothing about this profile needed to change on correctness grounds; the only open
  question was hardening it further and documenting realistic timing.

**2. External draft-model speculative decoding (`--spec-type draft-simple` + `-md`/
`--model-draft`) — tried, and cleanly rejected.** Confirmed via `llama-server --help` in
the deployed image (`ghcr.io/ggml-org/llama.cpp:full-cuda`, build b10975) that the correct
modern flag for this mechanism is `--spec-type draft-simple` combined with
`--spec-draft-model`/`-md` (not `draft-mtp`, which is the model's own built-in MTP head —
a different mechanism from an external full draft model). Downloaded
`Qwen/Qwen3-0.6B-GGUF:Qwen3-0.6B-Q8_0.gguf` (639MB) as a small, fast, readily-available
same-family drafter and paired it with the 27B target
(`--model /models/Qwen3.8-27B-UD-IQ4_XS.gguf --model-draft /models/Qwen3-0.6B-Q8_0.gguf
--spec-type draft-simple --spec-draft-n-max 5`). Server loads both models but fails to
initialize speculative decoding: `the target and draft vocabs are not compatible` /
`draft model vocab type must match target model to use speculation` — a clean, logged
rejection, not a hang or silent no-op (same failure class as the dflash tensor mismatch in
Round 6). The server falls back to running the 27B alone with no speculation active, so no
speedup was measured because none was possible. This 27B GGUF (`unsloth/Qwen3.8-27B-GGUF`)
does not share a tokenizer/vocab with the generic `Qwen/Qwen3-0.6B-GGUF` release, and no
vocab-compatible small sibling for this specific 27B repo/quant family was found within this
round's time budget. **Verdict: external draft-model speculative decoding is not viable for
this profile with a readily-available small model** — closes the "one lever never tried"
item flagged throughout this document (Rounds 6-8). Would need a purpose-built small draft
GGUF sharing this exact model's tokenizer, which does not appear to exist publicly.

**3. Surgical reasoning-budget control — real, and now adopted.** `llama-server --help`
confirms a genuine `--reasoning-budget N` flag (env `LLAMA_ARG_THINK_BUDGET`): "token budget
for thinking: -1 for unrestricted, 0 for immediate end, N>0 for token budget", paired with
`--reasoning-budget-message MESSAGE` ("message injected before the end-of-thinking tag when
reasoning budget is exhausted"). This is a real, separate cap from `--predict` — it targets
only the reasoning channel, forcing a transition to the visible answer once hit, rather than
capping the whole response length. Not strictly needed to pass this round's test (the model
used only ~27.6K of a would-be 65536 cap), but adopted as a belt-and-suspenders safety net
in the shipped compose file: `--reasoning-budget 65536` (guarantees at least ~16K tokens of
the 81920 total are left for the visible answer even in a worse case) +
`--reasoning-budget-message "Time is nearly up. Stop reasoning now and write the final
answer using what you have concluded so far."` This directly addresses the Round 5 failure
mode at the mechanism level, not just by raising `--predict` and hoping.

**4. Sampling tweaks for "more efficient" reasoning — nothing real found, none applied.**
Re-checked Qwen's own documentation/model-card guidance already consulted earlier in this
investigation for the "thinking mode for precise coding tasks" preset in use
(temp 0.6/top_p 0.95/top_k 20/min_p 0/presence_penalty 0/repeat_penalty 1.0) — this is
Qwen's own recommended preset already in place; there is no separate documented "reasoning
efficiency" or "budget forcing" sampling knob distinct from `--reasoning-budget` above.
Nothing invented; no change made here.

**Final config adopted for `docker-compose-gpu-qwen-27b-mtp.yml`**: unchanged from the
already-shipped config (thinking on, `--predict 81920`, MTP `draft-mtp` n-max 2, Qwen's
official sampling preset), **plus** the new `--reasoning-budget 65536` /
`--reasoning-budget-message` safety net from item 3. External draft-model speculative
decoding stays off (rejected, item 2).

**5. Comparison-only: same prompt with thinking OFF (`--reasoning off`).** Not a candidate
to replace the shipped thinking-ON config (the user explicitly ruled disabling thinking out
for the shipped profile) — run purely as a data point to measure the reliability cost of
thinking mode. Same 27B/IQ4_XS/MTP config, `--reasoning off` instead of the default
preserve-thinking behavior (confirmed via server log: zero `reasoning_content` produced,
real thinking-off this time — earlier rounds noted `preserve_thinking:false` via
chat-template-kwargs does *not* reliably suppress the channel on this endpoint, so this
round used the dedicated `--reasoning off` CLI flag instead, which did work cleanly).

- **Wall-clock: 467.4s (~7.8 minutes)** — 18x faster than thinking-on, as expected with the
  reasoning channel fully removed. `completion_tokens: 2598`, `reasoning_content` empty.
- **Code quality: real functional bug in its own self-authored test, core logic actually
  fine.** The generated `LRUCache` class itself is correct — verified by extracting it and
  running the same 10 independent edge-case tests used throughout this document: **all 10
  passed** (capacity=1, ttl=0, missing key/default, `__contains__` non-mutating, mixed
  get/put order, `__len__`, key-update reuse, injected-clock TTL both sides, no-TTL
  permanence, 10-thread concurrency smoke test). However, its **own embedded `unittest`
  suite fails one of its own tests**: `test_contains_does_not_affect_recency` asserts that
  after checking `"a" in cache` / `cache.contains("a")` (capacity 2, `a` inserted before
  `b`), then inserting `"c"`, `"a"` should survive and `"b"` should be evicted. That is
  backwards — per the class's own (correct) implementation, a `contains()` check must NOT
  bump recency, so `"a"` (inserted first, never legitimately "used") is the correct LRU
  eviction victim, not `"b"`. The model, without a thinking pass to catch this, wrote a test
  whose assertion silently assumed `contains()` *does* affect recency — directly
  contradicting the docstring it wrote one line above and the explicit prompt requirement.
  Running its own demo therefore **raises `AssertionError` and crashes on first run**,
  exactly the kind of self-verification failure thinking mode exists to catch.
- **Conclusion**: disabling thinking does not corrupt the underlying algorithm here (the
  27B is capable enough to get the core LRU/TTL logic right zero-shot), but it removes the
  self-verification pass that catches subtle test-writing mistakes — the visible symptom a
  user would actually hit is "the demo it gave me crashes," same practical failure mode as
  Devstral's and gpt-oss's demo bugs elsewhere in this document. This is concrete evidence
  *for* keeping thinking on for this profile, consistent with the user's instruction not to
  disable it.

| Config | tok/s | Wall-clock (LRU-cache task) | Completed within budget? | Code correctness |
|---|---|---|---|---|
| **Shipped config, thinking ON, `--predict 81920`** (adopted, + reasoning-budget added) | 3.8-5.9 (avg ~4.7) | **141 min** | Yes (31998/81920 tokens) | **Flawless — 0 fixes, all 10 edge cases pass** |
| Same + `--spec-type draft-simple -md Qwen3-0.6B` | n/a — init failed | n/a | n/a | Not reached — vocab-incompatible, rejected before any generation |
| Same, thinking OFF (`--reasoning off`, comparison only, not adopted) | ~35-40 (est. from MTP-off dense-model norms; not separately measured) | **7.8 min** | Yes (2598/81920 tokens) | Core logic correct (10/10 independent tests pass), but **its own demo crashes** on a self-authored test bug thinking mode would likely have caught |

**Recommendation**: keep this profile exactly as documented, with the reasoning-budget
safety net added. Set expectations honestly: **budget 2-2.5 hours wall-clock for a hard
coding task** on this profile. It is not a speed pick — it exists for cases that need a
reliable dense model and can tolerate the wait; the 35B A3B+MTP champion remains the right
default for anyone who needs both speed and reliability.

## Round 12b: does the 27B dense model actually produce *better* code than the 35B A3B+MTP champion?

This is the deciding question the whole profile hinges on — the user's own framing:
*"se supone que el 27b debería de funcionar mejor en cuanto a calidad que el 35b, sino no me
aporta nada con la perdida de velocidad"* (the 27B is supposed to be better quality than the
35B, otherwise it gives nothing for the speed it loses). Round 5's original writeup only
described the 35B's Round-5 output narratively — the actual generated code from that run
was never saved to disk, so a real side-by-side line-level read was not possible against
that specific transcript. To answer honestly, the 35B champion was re-booted this round
(`docker-compose-gpu-qwen-35b-a3b-mtp.yml`, unchanged config) and given the **exact same
prompt, temperature, and sampling parameters** as this round's 27B test, and both finished
code bodies were read side by side and independently tested.

**35B A3B+MTP, this round's regenerated run**: completed in **184s** (3 minutes),
9194 completion tokens (28K reasoning chars / 8K answer chars). Passed its own embedded
demo. Passed 9 of the same 10 independent edge-case tests — **failed the `ttl=0` immediate-
expiry case**: its TTL check uses strict `self.clock() > node.expiry` rather than `>=`, so
an entry with `ttl=0` is not considered expired until *after* the expiry instant has
strictly passed, not at it. Separately, its constructor does `self.clock = clock or
time.time` — meaning if no clock is passed, it silently falls back to real
`time.time()` internally, a direct (if minor/defensive) deviation from the prompt's explicit
"not `time.time()` internally" requirement (this only matters if the caller forgets to pass
a clock; when a clock is provided, as in every test above, `time.time()` is never reached).
Its own self-authored demo also contains a **subtle test-design bug of the same shape** seen
in the 27B thinking-off run above: a comment mislabels which key is MRU vs LRU before a
`__contains__` check, so `demo_and_test()` throws `AssertionError` when actually executed
as its own `__main__` block (only the two isolated `assert` blocks above that specific test
passed; the third block's assertion is backwards for the same reason as the 27B's).

**27B dense+MTP, this round's Round-12 run** (already detailed above): completed in
141 minutes, flawless on its own demo AND all 10 independent tests, correctly used `>=` for
TTL boundary (ttl=0 expires immediately, matching the more defensible reading of the spec),
never silently defaults to `time.time()` (raises `ValueError` if a TTL is requested without
a clock — a stricter, more correct enforcement of "no `time.time()` internally" than the
35B's fallback), and used a min-heap for O(log n) amortized lazy expiry cleanup (a genuinely
more sophisticated design choice than either the 35B's or the no-thinking 27B's plain
linear/dict-based expiry handling) alongside the required O(1) `get`/`put`.

**Honest verdict: yes, on this specific run, the 27B's code is measurably better — but by a
narrow, specific margin, not a decisive one.** Concretely:
- The 27B got a real edge case right (`ttl=0`) that the 35B got wrong.
- The 27B's clock-injection discipline is stricter (hard failure vs. silent fallback) than
  the prompt's explicit ask.
- The 27B's TTL-cleanup data structure (min-heap) is a more considered design choice than
  the 35B's approach.
- **But** the 35B made the *same category* of self-verification mistake in its own demo
  test as the 27B's thinking-OFF run did (a backwards MRU/LRU assumption in a hand-written
  test) — so on the "does more active compute produce more careful demo/test-writing"
  question specifically, the 35B (with thinking ON) did **not** clearly outperform the 27B
  (thinking OFF) on that axis in this comparison; both models' *demos* had a bug, only their
  core cache classes differed in correctness.
- Both models' *core cache logic* passed 9-10 of the same 10 independent tests — this is
  not "35B fundamentally worse," it's a couple of specific boundary-condition misses on an
  otherwise-equivalent implementation.

**What this means for the profile's value proposition**: the 27B does not deliver a
transformative quality jump that would justify its ~46x slower wall-clock time on
raw code quality alone (both models produce working, thread-safe LRU-cache implementations
that pass the vast majority of the same tests). The real, defensible reasons to keep this
profile are (a) it is *measurably* more careful about edge cases and spec literalism in this
one sample (small effect, not zero), and (b) it is the only shipped profile that is dense
(non-MoE, all params active per token) rather than MoE-routed, which matters specifically if
dense-model behavior itself (not raw score) is what's needed — not because "dense = smarter"
in general, which this comparison does not support as a strong claim. Users choosing this
profile should do so for **reliability-with-patience and a preference for a dense
architecture**, not for an expected step-change in code quality over the 35B A3B champion.
Both model outputs still needed a human/test pass to catch their respective single bugs —
neither is "trust blindly," a caveat this document has made about every model tested.

## State left on gpu-host (updated after Round 12)

Per explicit user request this round: **no container was left running at the end** (power
saving, superseding every earlier round's practice of restoring the 35B A3B+MTP champion as
the final state). All containers created or used during this round's testing
(`llama-cpp-gpu-qwen-27b-mtp`, the ad-hoc `llama-27b-draftsimple` draft-model test container)
were stopped and removed; `./scripts/docker/stop-all-servers.sh` was run as the final step
and confirmed 0 MiB VRAM in use. Re-launch with
`./scripts/docker/launch-server.sh` (35B A3B champion, default) or
`./scripts/docker/launch-server.sh .env.gpu.qwen-27b-mtp` (this round's profile) as needed.

Disk: added `Qwen3-0.6B-Q8_0.gguf` (639MB) to `/home/<user>/data/llama-models/` as
the rejected draft-model candidate from item 2 above — left on disk since it's small and
documents the experiment; delete it if disk space is tight, it is not referenced by any
shipped profile.

No commits or pushes were made — all changes (this document, `BENCHMARKS.md`, the 27B
compose file, and its `.env.sample`) are left as uncommitted working-tree edits for review,
per instructions.

## State left on gpu-host (Round 10, historical)

- `llama-cpp-gpu` container healthy, serving **35B A3B Q4_K_XL with MTP on (n_max=2),
  parallel=2, ctx=393216 (196608/slot)** — the recommended default config
  (`.env.gpu.qwen-35b-a3b-mtp.sample`). Re-verified `/health` → `{"status":"ok"}` and a real
  completion request after all other profiles were tested and torn down, per the requirement
  to leave the champion running at the end.
- Disk: all four shipped profiles' model files are present in
  `/home/<user>/data/llama-models/`: `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` (35B A3B+MTP),
  `Qwen3.8-27B-UD-IQ4_XS.gguf` (27B dense+MTP), `Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-IQ2_M.gguf`
  (27B "uncensored", no MTP — re-downloaded this round after being deleted per earlier disk
  discipline), and `gpt-oss-20b-UD-Q4_K_XL.gguf` (re-downloaded this round, same reason). The
  pre-existing `Qwopus3.5-9B-v3.Q4_K_M.gguf` also remains on disk but is **not** used by any
  shipped profile (see Round 9 — rejected on quality grounds).
- gpu-host's git checkout (`/path/to/docker-llama-local`) remains several
  commits behind `origin/main` and was not `git pull`-ed this round either, consistent with
  prior rounds' practice of not disturbing the live experiment mid-session. Round 10's testing
  copied the current Mac-repo compose/env/script files directly onto gpu-host's checkout
  (uncommitted) so that the exact files destined to ship were what got tested, rather than
  trusting the stale local checkout's older versions.
- No commits or pushes were made on either machine — all changes (Mac-side profile renames,
  sampling-parameter tuning, the new "uncensored" profile, the `launch-server.sh` fix, and
  this document) are left as uncommitted working-tree edits for review, per instructions.
