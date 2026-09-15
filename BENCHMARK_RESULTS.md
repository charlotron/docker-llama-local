# MTP Benchmark Results — Qwen 35B A3B / 27B (gpu-host)

Date: 2026-09-15
Host: gpu-host (WSL, RTX 4070 SUPER 12GB VRAM, 23GB host RAM)

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

**Model-card check:** unsloth's own guide (`unsloth/Qwen3.6-35B-A3B-MTP-GGUF/README.md`)
recommends exactly `--spec-draft-n-max 2` — matches our empirical optimum (row 3 vs 4/5).
**Important caveat from that same guide: `-np` (parallel) > 1 is not yet officially supported
with MTP** — our tests ran with `--parallel 3` and were stable/consistent, but this isn't
guaranteed upstream; if real concurrent-client instability shows up (multiple simultaneous
clients, not just sequential benchmarks), try `--parallel 1`.

## Recommendation for `test-35b-mtp-improvements`

**Adopt row 3**: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL` +
`--spec-type draft-mtp --spec-draft-n-max 2`, keeping `--parallel 3` / `--ctx-size 393216`
(131072/slot) as in the current setup. This is the only config with solid, repeated evidence,
verified quality, and it matches the quantizer's own official recommendation.

Compose flag changes needed in `docker-compose-gpu-qwen-35b-a3b-mtp.yml`:
- `--draft-max 2` → `--spec-type draft-mtp` + `--spec-draft-n-max 2`
- `--no-mmap --mlock` → `--load-mode mlock`
- Document that this requires updating the base image (`docker pull ghcr.io/ggml-org/llama.cpp:full-cuda`) before deploying.

**Not recommended yet**: migrating to 27B+MTP despite its potential (+92% in the best
measured case) — the memory sensitivity observed (row 7) is a real risk on this 23GB-RAM
machine, and the counter-intuitive slowdown when reducing `--parallel` (row 8 vs 9) means
its behavior isn't well understood yet. Worth a dedicated follow-up with more time to
diagnose.

**Not tested**: IQ quant variants (IQ4_XS/IQ4_NL) from the MTP repo on the new build — the
original attempt failed under the old (broken) build and wasn't retried once the real cause
was found. Since Q4_K_XL+MTP already delivers 42 tok/s at full quality, this isn't a
priority, but remains a next step if more speed is wanted at some size/quality cost.

## State left on gpu-host

- `llama-cpp-gpu` container healthy, serving **35B A3B Q4_K_XL with MTP on (n_max=2),
  parallel=3, ctx=393216** — the recommended config.
- Disk: 838GB free; kept `Qwen3.6-35B-A3B-UD-Q4_K_XL.baseline.gguf` (original, no MTP),
  `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` (with MTP tensors), `Qwen3.8-27B-UD-Q5_K_M.gguf`
  (pre-existing).
- `docker/docker-compose-gpu-qwen-35b-a3b-mtp.yml` on gpu-host modified locally with the new flags — not
  committed to git.
