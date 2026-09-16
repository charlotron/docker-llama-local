# Model benchmarks and chosen configurations

> **CURATED SUMMARY.** This is the condensed, human-readable version: final profiles, chosen
> configs, what was rejected and why. For the full raw data behind every number here — every
> round, every test, every methodology mistake found and corrected, in chronological order —
> see [`BENCHMARK_RESULTS.md`](./BENCHMARK_RESULTS.md).

This document summarizes the benchmarking work behind the four GPU profiles shipped in
`docker/`, and points to the full raw evidence in [`BENCHMARK_RESULTS.md`](./BENCHMARK_RESULTS.md)
(ten rounds, 27+ speed configurations, a code-quality shootout, and a 9B sanity check).

Host used for all measurements: **gpu-host**, RTX 4070 SUPER (12GB VRAM), WSL2 with a
23GB RAM ceiling (set in `.wslconfig`, not the physical host's real capacity — see
`BENCHMARK_RESULTS.md` "WSL memory ceiling" for how to raise it).

## The four profiles

All four were re-verified end-to-end on gpu-host (Round 10): fresh boot, `/health` check, one
real completion request each. Config shown reflects final values in place at that check
(`--parallel 2`; Qwen profiles run `preserve_thinking:true`, temp 0.6/top_p 0.95/top_k 20/
min_p 0/presence_penalty 0/repeat_penalty 1.0, `--predict 81920`, 196608 ctx-per-slot;
gpt-oss-20b runs temp 1.0/top_p 1.0/top_k 0, `reasoning_effort: high`, 131072 ctx-per-slot).

| Profile | Compose file | Model | Type | Quant | MTP | Speed (gen) | VRAM used | Host RAM used |
|---|---|---|---|---|---|---|---|---|
| **Default — fastest, most reliable** | `docker-compose-gpu-qwen-35b-a3b-mtp.yml` | Qwen 35B A3B | MoE, ~3B active/token | Q4_K_XL | **on** (`draft-mtp`, n-max 2) | **42.0 ± 3.6 tok/s** (n=8) | 9.67/12.28GB | 18.8/23.5GB |
| **Dense alternative** | `docker-compose-gpu-qwen-27b-mtp.yml` | Qwen 27B | dense, 27B active/token | IQ4_XS | **on** (`draft-mtp`, n-max 2) | 5.4 ± 0.5 tok/s (n=5) | 8.65/12.28GB | 18/23GB |
| **Dense, uncensored community fine-tune** | `docker-compose-gpu-qwen-27b-uncensored.yml` | Qwen 27B (HauhauCS-Aggressive fine-tune) | dense, 27B active/token | IQ2_M | **off** (real MTP tensors present but measured slower — 3.45 vs 4.40 tok/s, see Round 7) | 4.40 ± 0.02 tok/s (n=5) | 9.72/12.28GB | swap-free |
| **Fast MoE alternative, smaller footprint** | `docker-compose-gpu-gpt-oss-20b.yml` | gpt-oss-20b | MoE, ~3.6B active/token | Q4_K_XL | n/a (no MTP tensors in this arch) | 42.19 ± 6.00 tok/s (n=5) | 10.44/12.28GB | 6.4/23GB |

**Recommendation**: use the default (35B A3B+MTP) unless you have a specific reason not
to. It's the only config that came out flawless on every test run, including the hardest
code-quality task tried (a thread-safe LRU cache with TTL — see "Code quality" below).

**A 9B dense model (`Qwopus3.5-9B-v3.Q4_K_M.gguf`, `Jackrong/Qwopus3.5-9B-v3-GGUF`) was
evaluated as a possible 5th profile and rejected** — see "Models/configs tried and rejected"
below and `BENCHMARK_RESULTS.md` Round 9 for the full writeup. Fast (44-48 tok/s) but its
generated code doesn't run even after fixing the obvious bugs.

## Why these three, and not others

Every quant/config/model listed here survived a deliberately adversarial process: repeated
speed runs (not single samples), VRAM/RAM captured under load, and — for serious
candidates — code actually executed against edge-case tests, not just read. Configs that
looked good on a first pass but didn't hold up (a suspected mislabeled 27B baseline of
30.2 tok/s, IQ quants for the 35B, several 27B quant/spec-decoding combinations) are kept
in `BENCHMARK_RESULTS.md` with the reasoning for why they were ruled out, so the "why not"
is traceable too.

### Models/configs tried and rejected

| Model | Type | Quant | MTP | Speed | Why rejected |
|---|---|---|---|---|---|
| Qwen 35B A3B (original repo, old llama.cpp build) | MoE | Q4_K_XL | inert flag, no effect | 36.7 tok/s | Superseded once the image was updated and MTP actually worked |
| Qwen 35B A3B | MoE | IQ4_NL | on | 37.4 tok/s | Slower than Q4_K_XL+MTP despite being smaller — IQ dequant cost outweighs size on this heavily CPU-offloaded MoE |
| Qwen 27B | dense | Q5_K_M | off | 30.2 tok/s (**unreliable, likely mislabeled**) | Never reproduced; a smaller IQ4_XS quant measured 7x slower, which doesn't add up for a dense model — treat as untrustworthy, not ground truth |
| Qwen 27B | dense | Q5_K_M | on | 5.6 tok/s | Swap-contaminated (RAM at 94%, 3.1GB swap) — not a clean number |
| Qwen 27B | dense | Q4_K_XL | on/off | 3.6–5.8 tok/s | Bigger quant, no better than IQ4_XS; the "on" number is swap-contaminated too |
| Qwen 27B | dense | IQ3_S | on/off | 3.97–4.29 tok/s | Smaller quant, still slow even mostly in VRAM — proved the 27B is compute-bound, not memory-bound |
| Qwen 27B | dense | IQ4_XS | `draft-dflash` | 3.15 tok/s (no-op) | This GGUF has no dflash tensors — silent no-op, not a working alternative to MTP |
| Qwen 27B | dense | IQ4_XS | `ngram-simple` | 3.6 tok/s (no gain) | No repeated token sequences in a from-scratch code prompt for ngram matching to exploit |
| Qwen 27B | dense | IQ2_S | n/a | 5.26 tok/s | Fastest 27B-without-MTP number on record, but this GGUF has **no MTP/nextn tensors at all** — clean error on `--spec-type draft-mtp`, so it can't meet the profile's MTP requirement |
| Qwen 27B | dense | Q3_K_XL | on/off | 3.97–4.03 tok/s | Same compute-bound ceiling as every other 27B quant; MTP gives no gain (slightly worse) — also the clean baseline that exposed row above's Q4_K_XL+MTP 5.84 tok/s as likely swap-inflated |
| Qwen 27B (**community fine-tune**, HauhauCS-Aggressive) | dense | Q2_K_P / IQ2_M | on/off | 3.31–4.40 tok/s | Real MTP tensors confirmed present (unlike IQ2_S), but same compute-bound pattern — MTP is worse than off on both quants; not an official unsloth quantization, kept separate from the base-model line |
| Qwen 27B (**community fine-tune**, nerkyor EfficientThink Q2-LynnStyle) | dense | Q2-LynnStyle | `draft-dflash` (real DFlash2 draft GGUF, n-max 2) | 3.97 ± 0.82 tok/s | Genuine, working DFlash2 tensors (unlike the earlier no-op) but no speedup over ngram/no-spec baseline, and 11.52GB VRAM (vs 9.77GB) for the same throughput |
| Qwen 27B (same repo/quant) | dense | Q2-LynnStyle | `ngram-simple` | 3.81 ± 0.03 tok/s | Same compute-bound ceiling as every other 27B config; tightest-spread 27B result on record but not a speed win |
| Ornith-1.5-35B-A3B-DFlash2 | MoE draft model | — | n/a | not tested | **Wrong format for this stack**: `sglang`-only safetensors `DFlash2DraftModel`, no `.gguf` anywhere in the repo — llama.cpp cannot load it, ruled out before download |
| DeepSeek-Coder-V2-Lite-Instruct | MoE, 2.4B active | Q4_K_M | n/a | 23.8 tok/s | Fast, but **no tool-calling support** in its chat template — disqualifying for the agentic use case regardless of speed |
| Devstral-Small-2507 | dense, 24B | Q4_K_XL | n/a | 4.34 tok/s | Too slow (dense forward-pass cost); also found to have a **real functional bug** — TTL is entirely unimplemented in generated code despite being an explicit requirement |
| GLM-4.5-Air | MoE, 106B total | IQ4_XS | n/a | not tested | Doesn't fit — first shard alone is ~50GB, total >60GB |
| MiniMax-M2 | MoE, 230B-class | — | n/a | not tested | No realistically small quant found; doesn't fit this hardware |
| Qwopus3.5-9B-v3 (`Jackrong/Qwopus3.5-9B-v3-GGUF`) | dense, 9B active | Q4_K_M | n/a — **no MTP/nextn tensors in this GGUF**, clean `context type MTP requested but model doesn't contain MTP layers` error | 44-48 tok/s (fastest on record — fits almost entirely in VRAM) | Fast, but **generated code is broken**: crashes immediately (`class LRUCacheWithTTL(threading.Lock)` — subclassing a C type), and after patching that out, `get()` calls an undefined method (`self._move_to_end`) and fails on its first real call. Also needs a much larger reasoning budget than any other profile (16000 tokens) just to produce a visible answer at all. See `BENCHMARK_RESULTS.md` Round 9. |

## Code quality: not just speed

Speed alone doesn't tell you if a model is trustworthy. This round gave every viable
candidate the same hard, objectively verifiable task — a thread-safe LRU cache with O(1)
`get`/`put`, TTL via an injectable clock, and a `__contains__` that doesn't affect
recency — at a fixed seed, and **actually executed the generated code** against 10
independent edge-case tests instead of eyeballing it.

| Model | Result |
|---|---|
| Qwen 35B A3B+MTP | **Flawless.** Zero fixes needed, all tests passed first try. |
| gpt-oss-20b | Correct cache logic once a trivial syntax bug in its own demo was patched. Its own concurrency test failed, but the test itself was flawed (guaranteed race, not a real bug). |
| Devstral-Small | **Broken.** TTL is completely unimplemented (`_get_ttl()` always returns `None`) despite being explicitly required — a real functional regression, not a style issue. |
| Qwen 27B+MTP | Not completed — burned its entire token budget on internal reasoning without producing an answer, consistent with it already being ruled out on speed. |

Full transcripts and line-level bug descriptions are in `BENCHMARK_RESULTS.md`, "Round 5".

## Final capability check: reasoning, math, programming, vision (all 4 shipped profiles)

Closing round of this investigation. All four shipped profiles were given the same fixed set
of three tasks — a reasoning word problem, a multi-step arithmetic expression, and a `two_sum`
programming task (code actually executed, not just read) — plus a vision-support check via
`/props`.

| Model | Reasoning | Math | Programming | Vision |
|---|---|---|---|---|
| 35B A3B+MTP | Pass | Pass | Pass (executed, all assertions) | No (`vision: false`, no mmproj) |
| 27B dense+MTP | Pass | Pass | Pass (executed, all assertions) | No |
| 27B "uncensored" (HauhauCS) | Pass | Pass | Pass (executed, all assertions) | No |
| gpt-oss-20b | Pass | Pass | Pass (executed, all assertions) | No |

All four pass cleanly, no fixes needed — see `BENCHMARK_RESULTS.md` "Round 11" for the exact
prompts, verification methodology, and per-model token-usage notes. This confirms no basic
capability regression across the final profile set; it does not override the harder
differentiation from the LRU-cache-with-TTL task above (Round 5), where the 35B A3B remains
the only model that passed with zero fixes.

## Open questions / not yet decided

- **gpt-oss-20b as a formally supported profile**: speed and core code-quality are both
  solid, but its harmony chat format needs a larger token budget than Qwen (already
  reflected in `docker-compose-gpu-gpt-oss-20b.yml`'s higher `--predict`), is less
  disciplined about length constraints, and its tool-call round-trip hasn't been verified
  end-to-end (template presence confirmed, an actual function-call cycle has not). The
  profile is included here because the data is promising, not because it's a proven drop-in
  replacement — validate tool-calling for your specific agent workflow before relying on it.
- **27B + external draft-model speculative decoding**: the one lever not yet tried for the
  27B (a small separate Qwen model as an `-md` drafter, a different mechanism from MTP).
  Every other lever tried — bigger/smaller quant (Q5_K_M down to IQ2_S), MTP, dflash (both
  the earlier no-op and a genuinely working DFlash2 draft in Round 8), ngram, and two
  community fine-tunes with real MTP/DFlash2 tensors — tops out around 4–6 tok/s, and the
  best *clean* number remains IQ4_XS+MTP at 5.4 tok/s.
- **Stacking `--spec-type` strategies (e.g. dflash + ngram together)**: confirmed
  structurally impossible on this llama.cpp build — `--spec-type` is a single-choice flag
  (`none,draft-simple,draft-eagle3,draft-mtp,draft-dflash,draft-dspark,ngram-simple,
  ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache`), not a stackable set. Not a
  model-specific limitation; ruled out generally in Round 8.
- **Raising the WSL memory ceiling**: `.wslconfig` currently caps WSL at 24GB; the
  physical host may have more. Raising it and re-testing the 27B is a candidate for a
  future round if dense-model throughput becomes a priority.

## How to switch profiles

```bash
./scripts/docker/launch-server.sh                              # default: 35B A3B + MTP
./scripts/docker/launch-server.sh .env.gpu.qwen-27b-mtp         # dense 27B + MTP
./scripts/docker/launch-server.sh .env.gpu.qwen-27b-uncensored  # dense 27B, HauhauCS fine-tune, no MTP
./scripts/docker/launch-server.sh .env.gpu.gpt-oss-20b          # gpt-oss-20b
```

Each `.env.*.sample` points `COMPOSE_FILE` at the matching compose file and `HF_REPO`/
`HF_FILE` at the benchmarked model — copy the sample you want to `.env` (or pass it
directly as shown above) and the launch script downloads the model on first run.

**Container-name bug found and fixed in Round 10**: `launch-server.sh` used to hardcode
`CONTAINER_NAME="llama-cpp-gpu"` for every non-CPU profile, but three of the four GPU compose
files run under a different `container_name:` (`llama-cpp-gpu-qwen-27b-mtp`,
`llama-cpp-gpu-qwen-27b-uncensored`, `llama-cpp-gpu-gpt-oss-20b`). The script's own
readiness-wait used to fail to attach to logs and report `Container stopped unexpectedly` even
when the container was actually up and healthy. Fixed the same round: `CONTAINER_NAME` is now
derived from each compose file's own `container_name:` line, so the script's readiness message
is reliable for all four profiles.
