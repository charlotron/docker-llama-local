# Round 15 — raw evidence

Raw output files pulled from the GPU host after the benchmark campaign of
2026-09-27/28, kept so the conclusions in `docs/BENCHMARKS.md`
(Round 15) can be checked against the instruments rather than trusted.

| File | What it is |
|---|---|
| `ppl_results.txt` | `llama-perplexity` on wikitext-2, `-c 512 --chunks 100`, 6 profiles, with +/- error bars |
| `eval_results.txt` | EvalPlus pass@1 — two lines per model: HumanEval then HumanEval+ |
| `needle_results.txt` | Needle-in-a-haystack, KV q4_0/q8_0/f16 at depths 10/30/50/70/90 |
| `needle_raw/` | Full JSON responses behind every needle line, including `reasoning_content` |
| `opt_results.txt` | `--fit-target` sweep across profiles |
| `bench_results.txt` | Throughput runs (tok/s, VRAM, RAM, OOM counter) |
| `stage.log` | Pipeline stage timestamps |
| `evalbox_build.log` | Build of the benchmark container (pinned versions) |

## Reading notes — things that are easy to get wrong here

**`eval_results.txt` has two lines per model, not two runs.** EvalPlus prints
base HumanEval first, then the harder HumanEval+ on the extended tests. So
APEX-Mini is 87.2% / 82.3%, not two conflicting measurements.

**The perplexity gap between APEX-Mini and APEX-Compact is real; the gap
between APEX-Compact and 27B-IQ4_XS is not.**

- APEX-Compact 6.7772 +/- 0.10456 vs APEX-Mini 7.3221 +/- 0.11663 — separated
  by 0.545, far beyond the error bars. Compact genuinely has better perplexity.
- APEX-Compact 6.7772 +/- 0.10456 vs 27B-IQ4_XS 6.7692 +/- 0.10323 — the
  intervals overlap almost completely. These two are **statistically
  indistinguishable**; do not rank one above the other on this data.

That first, real gap is the point: Compact's better perplexity came with
**worse** code (75.6% vs 82.3% HumanEval+) and 28% less speed. The inversion
is not measurement noise, which is what makes it worth recording.

**`gpt-oss-20b` at PPL 152.40 is not a bad score.** Perplexity is only
comparable between quants of the same base model; gpt-oss is a different
family with a different tokenizer. The number is meaningless here and is kept
only to show it was measured and excluded, not silently dropped.

**The needle scores of 3/5 are not recall rates.** The answer appears in
`reasoning_content` in 19 of 19 measurements (check `needle_raw/`); the misses
are the model not copying it into the visible answer under a 400-token cap.
See the `preserve_thinking` gotcha in `AGENTS.md`.

**`KV-f16-v2-d90.json` is 0 bytes on purpose — it is itself evidence.** The
host wedged at that instant. The file is created after the HTTP response
returned and before the container teardown, which places the hang inside the
f16 run itself, not in the profile switch that followed.

**Not present here: MMLU-Pro.** It scored 17.26% (random is 10%) and the cause
was never established — the obvious hypothesis (a Spanish system prompt
breaking the English `The answer is (X)` regex) was tested and disproved. It is
excluded rather than reported as a weak result. Do not cite that number.
