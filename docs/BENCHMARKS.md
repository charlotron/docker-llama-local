# Model benchmarks and chosen configurations

This document summarizes the benchmarking work behind the three GPU profiles shipped in
`docker/`, and points to the full raw evidence in [`BENCHMARK_RESULTS.md`](../BENCHMARK_RESULTS.md)
at the repo root (eight rounds, 27+ speed configurations, a code-quality shootout).

Host used for all measurements: **gpu-host**, RTX 4070 SUPER (12GB VRAM), WSL2 with a
23GB RAM ceiling (set in `.wslconfig`, not the physical host's real capacity — see
`BENCHMARK_RESULTS.md` "WSL memory ceiling" for how to raise it).

## The three profiles

| Profile | Compose file | Model | Type | Quant | MTP | Speed (gen) | VRAM used | Host RAM used |
|---|---|---|---|---|---|---|---|---|
| **Default — fastest, most reliable** | `docker-compose-gpu-qwen-35b-a3b-mtp.yml` | Qwen 35B A3B | MoE, ~3B active/token | Q4_K_XL | **on** (`draft-mtp`, n-max 2) | **42.0 ± 3.6 tok/s** (n=8) | 9.67/12.28GB | 18.8/23.5GB |
| **Dense alternative** | `docker-compose-gpu-qwen-27b.yml` | Qwen 27B | dense, 27B active/token | IQ4_XS | **on** (`draft-mtp`, n-max 2) | 5.4 ± 0.5 tok/s (n=5) | 8.65/12.28GB | 18/23GB |
| **Fast MoE alternative, smaller footprint** | `docker-compose-gpu-gpt-oss-20b.yml` | gpt-oss-20b | MoE, ~3.6B active/token | Q4_K_XL | n/a (no MTP tensors in this arch) | 42.19 ± 6.00 tok/s (n=5) | 10.44/12.28GB | 6.4/23GB |

**Recommendation**: use the default (35B A3B+MTP) unless you have a specific reason not
to. It's the only config that came out flawless on every test run, including the hardest
code-quality task tried (a thread-safe LRU cache with TTL — see "Code quality" below).

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
./scripts/docker/launch-server.sh                       # default: 35B A3B + MTP
./scripts/docker/launch-server.sh .env.gpu.qwen-27b      # dense 27B + MTP
./scripts/docker/launch-server.sh .env.gpu.gpt-oss-20b   # gpt-oss-20b
```

Each `.env.*.sample` points `COMPOSE_FILE` at the matching compose file and `HF_REPO`/
`HF_FILE` at the benchmarked model — copy the sample you want to `.env` (or pass it
directly as shown above) and the launch script downloads the model on first run.
