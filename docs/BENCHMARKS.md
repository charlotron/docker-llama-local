# Benchmarks: local LLM profiles (RTX 4070 SUPER / WSL2)

Single source of truth. Every number here was measured on this hardware; raw
output files are in [`evidence/round15/`](./evidence/round15/).

Last updated: 2026-09-29.

---

## 1. Test conditions

**Host (the machine under test)**

| | |
|---|---|
| OS | Windows 11 + WSL2 |
| GPU | NVIDIA RTX 4070 SUPER, 12 GB VRAM (12282 MiB usable) |
| RAM | 24 GB total, ~23 GB WSL ceiling |
| CPU | 16 cores (14 given to llama.cpp) |
| Models | `/srv/llama-models` — **native ext4**, not a `/mnt` 9p mount |
| Server | `ghcr.io/ggml-org/llama.cpp:full-cuda`, OpenAI-compatible API on port 12345 |

**Where the harness runs**

The benchmark harness runs on a **separate machine** (a laptop on the same LAN) and
reaches the server over HTTP. It is a pure Python HTTP client and does not
belong on the GPU host, which has 23 GB of RAM shared with a ~14 GB model;
and running evaluation drivers there contributed to three host freezes. Only
`llama-perplexity` runs on the host, because it needs the GPU and the weights.

**Standing configuration for every test unless stated otherwise**

```
--parallel 1            --ctx-size 131072        --fit-target 384
--cache-type-k q4_0     --cache-type-v q4_0      --flash-attn on
--load-mode mlock       --spec-type draft-mtp    --spec-draft-n-max 2
--temp 0.6  --top-p 0.95  --top-k 20  --min-p 0  --repeat-penalty 1.0
```

Sampling values are **Qwen's official preset for thinking mode**, not tuned here.

**Instruments**

| Test | Tool | Settings |
|---|---|---|
| Throughput | `bench_any.sh` | 3-5 samples per config, reports tok/s, VRAM, RAM, OOM count |
| Perplexity | `llama-perplexity` | wikitext-2, `-c 512`, `--chunks 100` |
| Code (public) | EvalPlus 0.3.1, HumanEval+ | 164 problems, pass@1, **greedy (temp 0)** |
| Code (real) | custom, 5 multi-part tasks | **temp 0.6**, no `max_tokens`, independent hidden tests |
| Tool calling | custom, 10 cases | temp 0.6, 5 repeats, scored per failure mode |
| Long context | needle-in-a-haystack | ~118k tokens of filler, depths 10/30/50/70/90 |

---

## 2. Recommended profiles

### Default: `apex-mini`

`docker/alternatives/docker-compose-gpu-qwen-35b-a3b-apex-mini.yml` — Qwen3.6-35B-A3B-APEX-MTP-I-Mini (13.6 GB)

| Metric | Result |
|---|---|
| Throughput | **97.2 tok/s** (measured up to 108 on an idle host) |
| Real coding tasks, production temp | **15/15 (100%)** |
| HumanEval+ (public, greedy) | 87.2% / **82.3%** |
| Tool calling | 28/30 (93%) |
| Context | 128K in a single slot |
| VRAM at rest | ~11.5 GB of 12.3 |
| Idle GPU utilisation | 0-1% |

Wins on speed **and** quality — there is no trade-off to manage here.

### Vision: `apex-mini-vision`

`docker/docker-compose-gpu-qwen-35b-a3b-apex-mini-vision.yml` — identical weights
to `apex-mini`, plus an 861 MB `mmproj` file.

Qwen3.6-35B-A3B is multimodal at the base, but the MTP repo ships the weights
alone, so `/props` reports `"vision": false` and image requests fail with
`500 image input is not supported`. The vision tower lives in the sibling repo
`mudler/Qwen3.6-35B-A3B-APEX-GGUF` as `mmproj.gguf`; loading it alongside the
model turns on both image and video input.

Measured on the same box, same prompt, before and after adding the mmproj:

| Metric | `apex-mini` | `apex-mini-vision` |
|---|---|---|
| Throughput | 99.4 / 89.9 tok/s | 94.7 / 93.3 / 95.5 tok/s |
| VRAM at rest | 11433 MiB | 11423 MiB |
| Tool calling | works | works |
| `/props` modalities | `vision: false` | `vision: true`, `video: true` |

**No measurable cost.** The `--fit` autofitter absorbs the mmproj inside the
existing `--fit-target 384` budget. Both readings sit inside run-to-run noise,
and VRAM did not move.

Vision verified functionally, not just declared:

- Shapes and colours: "red circle top left, blue square top right, green
  triangle bottom left" — all three correct.
- A code screenshot: transcribed the Python exactly, then correctly identified
  the missing empty-list guard and the resulting `ZeroDivisionError`.

Given it costs nothing, prefer this over `apex-mini` unless you want the
smallest possible footprint. It also makes `vision-qwen25vl` largely redundant:
that profile swaps the 35B MoE for a 7B dense model just to read images.

### Alternatives

| Profile | When | Cost vs default |
|---|---|---|
| `apex-mini-vision` | Image or video input | none measured |
| `apex-compact-2slot` | Two concurrent slots needed | −28% speed, −6.7 pts HumanEval+ |
| `gpt-oss-20b` | Lightest option, most headroom | 84.6 tok/s; different family |
| `vision-qwen25vl` | Image input without the 35B MoE | 7B dense; superseded by `apex-mini-vision` |
| `qwen3.8-27b-fullgpu-best-coding` | Programming, long autonomous agent runs (finished alone 12/12 vs 8/12) | 40 tok/s (about half), no vision, 96K context instead of 128K |
| `qwen-27b-uncensored` | Refusal-free output | **4.4 tok/s**, language drift mid-answer (IQ2_M) |
| `cpu` | No GPU | — |

---

## 3. Results

### 3.0 Master comparison — every candidate measured

Speed is at the best `--fit-target` found for each; "—" means not measured, not
zero. Quality columns come from the sections below, measured under the
conditions in section 1.

| Model / quant | Size | Slots | ctx/slot | fit-target | MTP | tok/s | Real tasks | HumanEval+ | Tools | PPL | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **35B A3B APEX-I-Mini** | 13.6 GB | 1 | 131072 | 384 | yes | **97.2** | **15/15** | **82.3%** | 28/30 | 7.3221 | **ADOPTED — default** |
| 35B A3B APEX-I-MiniPlus V2.1 | 14.5 GB | 1 | 131072 | 384 | yes | 95-100 | — | — | 29/30 | — | Ties everywhere, +0.9 GB — not adopted |
| 35B A3B APEX-I-Compact | 16.5 GB | 1 | 131072 | 384 | yes | 75.7 | — | 75.6% | — | 6.7772 | Kept for 2-slot use |
| gpt-oss-20b UD-Q4_K_XL | 11.3 GB | 1 | 131072 | 384 | n/a | 84.6 | LRU: logic OK, syntax bug | — | harmony fmt OK | 152.4 (n/a) | Kept — lightest |
| 35B A3B UD-Q4_K_XL | 21.3 GB | 1 | 131072 | 384 | yes | 66.4 | **LRU: flawless** | — | — | — | Best documented quality, but **not operable** — wedged the host twice |
| 35B A3B UD-Q4_K_XL | 21.3 GB | 3 | 131072 | 1536 | yes (n=2) | 42.0 | — | — | — | — | Historical baseline (Round 2) |
| 35B A3B IQ4_NL | — | 3 | 131072 | 1536 | yes (n=2) | 37.4 | — | — | — | — | Slower than Q4_K_XL |
| 27B dense APEX-I-Nano | 10.7 GB | 1 | 131072 | 384 | no (dense) | 10.1 | — | — | — | 7.3462 | Too slow |
| 27B dense UD-IQ4_XS | 13.6 GB | 1 | 131072 | 384 | yes (n=2) | 6.7 | — | — | — | 6.7692 | Too slow |
| 27B dense APEX-I-Mini | 13.3 GB | 1 | 131072 | 384 | no (dense) | 6.7 | — | — | — | 6.9788 | Too slow; APEX loses to Unsloth here |
| 27B dense Q5_K_M | — | 1 | 131072 | 1536 | yes (n=2) | 6.65 | — | — | — | — | At 3 slots it swapped: 5.6 tok/s, RAM 94% |
| 27B dense IQ2_S | — | 3 | 131072 | 1536 | **none in GGUF** | 5.26 | — | — | — | — | No MTP tensors present |
| 27B Uncensored IQ2_M | 9.8 GB | 2 | 196608 | 1536 | off (slower with) | 4.4 | — | — | — | — | Refusal-free use only; drifts to English mid-answer |
| Devstral-Small-2507 (24B dense) | — | 3 | 131072 | 1536 | n/a (arch) | 4.3 | **LRU: broken (TTL never implemented)** | — | template OK | — | Too slow **and** functionally wrong |
| 27B dense Q3_K_XL | 16.4 GB | 3 | 131072 | 1536 | no | 4.0 | — | — | — | — | Too slow; MTP gave no gain (3.97) |
| DeepSeek-Coder-V2-Lite | — | 1 | 131072 | 1536 | n/a (no variant) | 23.8 | — | — | **none** | — | **Disqualified — no tool calling in chat template** |
| Qwen3.5-9B / Qwythos-9B | ~5.5 GB | 3 | 131072 | 1536 | varies | — | — | — | — | — | Ruled out on quality (Round 9) |

**Read the config columns before comparing any two rows.** Rows at `fit-target
384` / 1 slot are from the final rounds; rows at `1536` / 3 slots are earlier
baselines measured before the `--fit-target` finding. The same Q4_K_XL model
appears twice on purpose — 42.0 then 66.4 — and the whole difference is
configuration, not the model. `n=2` means `--spec-draft-n-max 2`.

**Note on the original Q4_K_XL.** It is listed as not operable because 21.3 GB
does not fit this host's memory budget — but on quality it was the *strongest*
model tested. On the hardest task ever run here (thread-safe LRU cache, TTL via
an injectable clock, `__contains__` that must not affect recency) it was the
only candidate to pass its own demo **and** all 10 independent edge-case tests
with zero fixes. The decision to drop it was forced by memory, not by quality.
See section 10, Round 5.

The decisive pattern: **MoE beats dense on this hardware, by an order of
magnitude.** Every 35B A3B MoE variant runs at 66-97 tok/s; every dense model
tried (27B, 24B Devstral) sits at 4-10 tok/s, because dense activates all
parameters per token while A3B activates ~3B of 35B.

**Correction (2026-09-29): the 27B was never compute-bound, it was spilling.**
Every 27B row above ran with 2-3 slots and 131K-393K of total context, and
that KV cache pushed layers out of VRAM onto DDR5. Qwen3.8-27B is hybrid (16
of 64 layers are full attention), so its context is cheap once it is kept to
one slot. `qwen3.8-27b-fullgpu-best-coding` (UD-Q2_K_XL 9.83 GB, 1 slot, KV q4_0,
`--gpu-layers all --fit off`) loads at 11.1 GB with 64K and 11.74 GB with
100K (peak 11.86 GB on a 93K-token prompt: prefill 958 tok/s, generation
24.5 tok/s, needle found). The table below was measured at 64K:

| | 27B fullgpu | APEX-I-Mini |
|---|---|---|
| Generation | **40.3 tok/s** (36.7 at 18.6K ctx) | 86.2 tok/s |
| Prefill, 18.6K-token prompt | 1257 tok/s | — |
| Real tasks, same harness (below) | **14/15** | 13/15 |
| Wall clock for the 15 runs | 49 min | 28 min |

The real-task numbers come from a rebuilt 5-task harness (the original was not
kept), each hidden test validated against a reference solution first, so the
13/15 here is not comparable with the 15/15 in section 3.2. All three
failures are genuine logic bugs: 27B joined the decimal part with `,`; Mini
failed the TTL boundary once and parsed `'1.234,50'` wrongly once. At n=15 the
two models are statistically tied on isolated tasks. The 27B spends ~8.4K
tokens per task because `--reasoning-budget 8192` cuts it off every time;
Mini hits its own 16384 budget on the hardest tasks.

### 3.1 Throughput and the `--fit-target` lever

`--fit-target` is the VRAM margin **left free**, not a cap. Lowering it puts
more of the model on the GPU. This was the single largest speed lever found.

| Profile | fit 1536 | fit 768 | **fit 384** | Gain |
|---|---|---|---|---|
| **APEX-I-Mini 35B** | 83.80 | 93.02 | **97.23** | +16% |
| gpt-oss-20b | 60.42 | 77.52 | **84.56** | **+40%** |
| Q4_K_XL 35B | 59.99 | 65.77 | **66.35** | +11% |
| APEX-Compact 35B | — | — | **75.74** | — |
| 27B APEX-Nano | 8.16 | 9.53 | **10.10** | +24% |
| 27B IQ4_XS | 6.32 | — | **6.74** | +7% |
| 27B Uncensored IQ2_M | 4.40 | — | — | — |

The gain is largest where the model is smallest — more of it fits.

### 3.2 Real coding tasks (the number to trust)

Five multi-part tasks at **temperature 0.6**, **no `max_tokens`** (exactly what
OpenCode sends), each with an independent check the model never sees. None of
these tasks appear in any public benchmark.

| Task | What the hidden test verifies | Result |
|---|---|---|
| LRU cache with per-entry TTL | Correct LRU eviction *and* TTL expiry | 3/3 |
| `retry` decorator | Exactly N attempts, exponential backoff, re-raises | 3/3 |
| Spanish money parsing | `'1.234,50'` → `1234.50`, grouped and summed | 3/3 |
| Tokenizer | Decimals and unary negatives after `(` | 3/3 |
| Deep config merge | Lists replaced, **input not mutated** | 3/3 |
| **Total** | | **15/15 (100%)** |

Speed held at 95-101 tok/s across all 15 runs. Zero empty responses.

### 3.3 HumanEval+ (public benchmark — read with caveats)

| Profile | HumanEval | HumanEval+ |
|---|---|---|
| **APEX-I-Mini** | **87.2%** | **82.3%** |
| APEX-I-Compact | 78.7% | 75.6% |

Both at an identical 4096-token cap. Raising Mini's cap to 8192 moved it to
93.9 / 87.2 — **the score is sensitive to the token budget**, so only compare
runs measured at the same cap.

Two caveats on this instrument: HumanEval dates from 2021 and is very likely in
training data, and EvalPlus `--greedy` forces **temperature 0**, which is not
the production setting. Section 3.2 is the better evidence.

### 3.4 Tool calling

10 cases x 5 repeats, scored per failure mode — an agent breaks differently
depending on *how* the call is wrong.

| Case | MiniPlus | Mini |
|---|---|---|
| simple / selection / args_exact | 3/3 | 3/3 |
| args_multi — 3 required args from messy prose | 3/3 | 2/3 |
| trap — reads like tool A, needs tool B | 2/3 | 3/3 |
| chain — must search before it can read | 3/3 | 3/3 |
| multiturn — use the result, do not re-call | 3/3 | 2/3 |
| abstain / abstain_hard — answer, do not call | 3/3 | 3/3 |
| long_ctx — correct call after ~8K tokens of noise | 3/3 | 3/3 |
| **Total** | 29/30 (97%) | 28/30 (93%) |

One success apart at n=3 is a tie. What held for both, and matters more:
**valid JSON in all 60 calls**, exact arguments (dates as `YYYY-MM-DD`,
decimals preserved), and no tool invoked on general-knowledge questions.

### 3.5 Perplexity (kept as evidence, not used to choose)

wikitext-2, `-c 512`, `--chunks 100`. Only comparable **between quants of the
same base model**.

| Profile | PPL | ± |
|---|---|---|
| 27B-IQ4_XS | 6.7692 | 0.103 |
| APEX-Compact-35B | 6.7772 | 0.105 |
| 27B-APEX-Mini | 6.9788 | 0.108 |
| APEX-Mini-35B | 7.3221 | 0.117 |
| 27B-APEX-Nano | 7.3462 | 0.114 |
| gpt-oss-20b | 152.40 | 2.990 |

**Perplexity ranked the models backwards.** APEX-Compact beats APEX-Mini by
0.545 — real, far beyond the error bars — yet writes *worse* code (75.6% vs
82.3%) and runs 28% slower. Choosing on perplexity would have shipped the worse
model on every axis that matters.

The top two overlap almost completely and are **statistically
indistinguishable**; do not rank them. `gpt-oss-20b` at 152 is a different
family and the number is meaningless here.

### 3.6 KV-cache precision and long context

Needle-in-a-haystack at ~118k tokens (`prompt_tokens=117887`).

| KV type | Prefill | Time/query | Score |
|---|---|---|---|
| **q4_0** | **1033 tok/s** | **124 s** | 3/5 |
| q8_0 | 962 tok/s | 133 s | 3/5 |
| f16 | 748 tok/s | 170 s | 2/4 |

**f16 costs 27% throughput and buys nothing.** All three score the same and
their misses fall at different, non-overlapping depths — noise, not
degradation. KV `q4_0` is free at this context length. Do not "upgrade" it.

The 3/5 is **not** a recall rate: the needle appeared in the reasoning channel
in **19 of 19** measurements. The misses are the model not copying it into the
visible answer under a 400-token cap — see section 4.

---

### 3.7 27B quantization and context ceiling (reference host, 2026-10-08)

Host: RTX 4070 SUPER 12 GB (12282 MiB), WSL2 28 GB. One slot, `--gpu-layers all
--fit off --flash-attn on`, KV cache `q4_0`, server on `--ctx-size 98304`.
Same server flags for every row. Thinking was **unbounded** in these runs (no
`--reasoning-budget`), unlike the production profile.

Method: "empty" is a 400-token generation on a short prompt. "Full" is a
~91.5K-token prompt followed by a 300-token generation, so it measures generation
speed with the context nearly full. Both numbers come from the server's own
timing lines (`eval time`, `prompt eval time`).

| Quant | File | VRAM at 98K | Empty gen | Full: prefill / gen | Notes |
|---|---|---|---|---|---|
| **UD-Q2_K_XL** (production) | 9.83 GB | 11.74 GB | 34.8 tok/s | 839 / **21.3** tok/s | Full at 65K: 23.9 tok/s |
| UD-IQ2_S | 8.37 GB | 10.68 GB | 37.7 tok/s | 820 / **22.7** tok/s | Needle recalled |
| UD-IQ2_S, 131K ctx | 8.37 GB | 11.42 GB | 37.7 tok/s | 825 / 22.5 tok/s | Fits, not used (see limit below) |
| UD-IQ2_S, K q8_0 / V q4_0 | 8.37 GB | 11.46 GB | 38.2 tok/s | 828 / 14.9 tok/s | Needle recalled; -34% at full context |

Not measured: UD-IQ2_XXS (7.3 GB, download incomplete), UD-IQ3_XXS (10.9 GB;
estimated ~12.8 GB at 98K, does not fit on this card).

What the numbers say:

- **No row reaches 25 tok/s with the context full.** Generation loses ~35-40%
  between an empty and a ~91K context on every quant tested.
- **IQ2_S frees ~1.1 GB of VRAM** versus Q2_K_XL at the same context, and is
  ~8% faster with an empty context. The gain is headroom, not speed. IQ2_S is a
  viable option; production keeps Q2_K_XL (see the decision below).
- **Quantizing K to q8_0 costs more speed than it is worth here** (-34% at full
  context, +0.8 GB of VRAM). Keep `q4_0` for both K and V.
- **Q2_K_XL at 100K (102400) collapses** to ~2-3 tok/s: VRAM reaches 11.9 GB of
  12.28 GB; the slowdown looks like layers spilling to system RAM (not verified).
  98K (98304) does not show it (11.74 GB).
  IQ2_S at 131K still fits in 11.42 GB, so its spill risk is lower.
- **Coherence beyond 100K** was reported by the maintainer in use; it is not
  measured here. The production context stays at 98304 (96K) for that reason.

**Decision (2026-10-08):** production stays on UD-Q2_K_XL at 98304. IQ2_S is
viable (lower VRAM, similar speed, passes the recall check), but the maintainer
has seen Q2_K_XL behave more reliably in day-to-day use. Our runs did not
separate the two on quality, so this choice rests on that experience, not on a
measured difference. Revisit with the coding-task harness if that changes.

### 3.8 Reasoning effort: `xhigh` (template default) vs `medium`

Coding harness, 4 tasks x 2 samples, Python with unit tests (parse EUR amounts,
LRU cache with TTL, interval merge, slugify). Same server and sampling as
production (Q2_K_XL, 98304, thinking budget 8192). The only change is
`--reasoning-effort`.

| Effort | Passed | Completion tokens | Wall time | Aggregate tok/s | Cut by budget |
|---|---|---|---|---|---|
| default (`xhigh`) | 8/8 | 50,637 | 1,524 s | 33.2 | 0 |
| `medium` | 8/8 | 17,465 | 518 s | 33.7 | 0 |

`medium` used 65% fewer tokens and finished in a third of the time, with the same
pass rate. Speed per token is unchanged, so the gain is all in how much the
model thinks. Limits: 8 samples, tests written for this harness, pass/fail only.
It does not show quality differences on harder tasks. Production uses `medium`;
revisit if a harder task set shows a drop.

Recall check: a single code inserted at 10% of the ~91K prompt was returned
correctly in the visible answer by IQ2_S with both KV settings. One case per
setting is not a recall rate.

---

## 4. Production gotchas (these bite silently)

### `preserve_thinking` + a small `max_tokens` returns EMPTY content, not an error

Reasoning is billed against the same budget as the answer, and comes first.
Measured: **2227 reasoning tokens and 0 content tokens** on a request capped at
768. The response is HTTP 200 with `finish_reason: "length"` and `content: ""`.

This corrupted two measurements before it was understood: HumanEval scoring
5.5%, and the needle test scoring 3/5.

### `--reasoning-budget` must sit BELOW the client's `max_tokens`

The budget caps the thinking channel and nudges the model to answer — but it
can only fire if the request is still alive when the budget is reached.

```
client max_tokens  >  --reasoning-budget  +  room for the answer
```

Measured with the ordering wrong (budget 16384, client cap 8192): **38% of 164
HumanEval problems returned empty solutions.** The budget never fired once.

Verified behaviour on a hard task:

| Client sends | finish | Answer |
|---|---|---|
| **no `max_tokens`** (what OpenCode sends) | stop | 10,922 chars |
| `max_tokens=4096` | length | **0 chars** |
| `max_tokens=24576` | stop | 12,202 chars |

**The shipped setup is safe**: OpenCode sets no `max_tokens`, so the server's
`--predict 81920` applies and the budget fires correctly. Any client that sets
a cap needs ≥24576 with the shipped `--reasoning-budget 16384`.

### State the exact signature when asking for code

The same five real tasks scored **6/10 with open prompts and 15/15 once the
signatures were named**. Every failure was
`TypeError: unexpected keyword argument` — correct logic, different parameter
names from the caller's. Left open, this model invents reasonable-but-arbitrary
names.

---

## 5. Rejected, and why

| Candidate | Reason |
|---|---|
| **Whole 27B dense family** (superseded, see `qwen3.8-27b-fullgpu-best-coding`) | 10.1 tok/s at best vs 97.2, measured with the KV cache pushing layers to the CPU. Within it, APEX does not beat Unsloth's quant (IQ4_XS 6.7692 vs APEX-Mini 6.9788 at equal size and speed) |
| **An APEX-MTP 27B** | Impossible — MTP needs a trained MTP head, present only in A3B MoE models |
| **Q4_K_XL (21.3 GB)** | Not operable here. Under perplexity it re-read weights every chunk (35+ min, zero chunks, container in D-state); as a server with `mlock` it made the host unreachable 40+ min. A `--memory 17g` cgroup makes it worse — a 17 GB limit around a 21.3 GB mmap forces constant page eviction |
| **KV f16 / q8_0** | Cost without benefit (section 3.6) |
| **TurboQuant** | Investigated, rejected — led to the `--fit-target` finding instead |
| **APEX-I-MiniPlus V2.1** | Ties on every measured axis (95-100 tok/s, 29/30 tools) for +0.9 GB. Its author's headline "93.3% SWE-bench (46/60)" appears **verbatim on three different model cards** with different base models — boilerplate, not a measurement |
| **External draft-model speculation** | `--spec-type draft-simple` fails at init: "target and draft vocabs are not compatible" |

---

## 6. Limitations — what these numbers do not tell you

- **HumanEval+ was measured at temperature 0**, not the production 0.6, and is
  likely contaminated. Section 3.2 exists because of this.
- **The real-task suite is 5 tasks.** It is the most relevant evidence here, but
  15/15 on five tasks is not a precision estimate.
- **Tool calling used n=3-5 per case.** Good enough to show both models are
  usable; not enough to rank them.
- **MiniPlus has no comparable code-quality number.** Three attempts were made;
  the host wedged twice and was powered off once.
- **MMLU-Pro is excluded.** It scored 17.26% (random is 10%) and the cause was
  never established — the obvious hypothesis (a Spanish system prompt breaking
  the English `The answer is (X)` regex) was tested and **disproved**. Do not
  cite that number.

---

## 7. Corrections made during this work

Recorded because each one nearly shipped as a finding.

| Reported | Actually |
|---|---|
| HumanEval 5.5% | EvalPlus hardcodes `max_new_tokens: 768`, consumed by reasoning |
| Needle 0/5 | 6500 filler lines = 212k tokens against a 131k window |
| Capability suite: 3 of 4 coding tasks `NameError` | My code extractor |
| Real tasks 6/10 | Prompts never stated the signatures the checks called |
| "The 82.3% is inflated" | **Retracted.** Same-difficulty tasks at production temperature scored 15/15 |
| "`--reasoning-budget` fixed the empty responses" | Only true at `max_tokens 81920`; at a realistic cap it never fires |
| "KV f16 caused the host freeze" | **Retracted.** The second freeze happened on q4_0 with the small model; cause still unknown |

**Four of these were defects in the measuring instrument, not the model.** A
surprisingly bad number is more often a broken harness than a real finding.

---

## 8. Host stability

The GPU host's WSL2 froze three times under sustained GPU benchmarking. Symptom:
ping fine, TCP 22 accepted, **SSH banner never arrives** — so `ping` and `nc`
prove nothing; only a completed remote command proves the host is alive.

It **cannot be recovered remotely**: WinRM (5985/5986) and RDP are closed, and
port 22 is WSL's own sshd. Only `wsl --shutdown` from Windows brings it back.

Mitigations now in place:

- `hostguard.sh` on the host traces RAM, load, swap, GPU and power to
  `blackbox.log` every 5 s, and kills the benchmark if available RAM drops
  below 2500 MB or load exceeds 40. Registered as `@reboot` in crontab.
- The evaluation harness runs off-host (section 1).
- One model resident at a time. A SIGKILLed `docker run` orphans its container,
  which once left two models loaded simultaneously (load average 86).

**Idle cost of a loaded model**: ~11.5 GB of 12.3 GB VRAM and ~90 W, at 0-1%
GPU utilisation. The GPU is effectively unavailable for anything else. Stop the
container when not in use — startup is 20 seconds.

---

## 9. How to switch profiles

See [`../AGENTS.md`](../AGENTS.md) for the two supported patterns, the
`.sample` vs real `.env` distinction, and the deployment gotchas
(Compose relative-path resolution, `mlock` on slow filesystems, WSL2 port
exclusions).


---

## 10. Appendix — full historical measurements

Earlier rounds, kept so any number above can be traced. Conditions differ
between rounds (notably `--parallel 3` and higher `--fit-target` in the early
ones), so **do not compare across rounds** — compare within a table.

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
The local file on the GPU host was verified **byte-exact** against the HF-hosted copy (both
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
