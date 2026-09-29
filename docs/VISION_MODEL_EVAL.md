# Vision model evaluation — Qwen2.5-VL-7B-Instruct

> Separate from `BENCHMARKS.md`/`BENCHMARKS.md` on purpose: this is a different
> model category (multimodal image+text, not text-only) and a different weight class
> (7B vision-language model vs. the 27B/35B text models in the main investigation), so
> "is it better than the other models" doesn't have a fair apples-to-apples answer on
> general text/coding tasks. This doc answers the actual useful question instead: is
> this vision model good enough to keep around for document/image analysis tasks.

## Background

A pre-existing, separate project (`llama-image-analyzer-gpu`) was found running on
the GPU host, stopped ("Exited (0) 2 months ago"). It runs a different model family
(Qwen2.5-VL, vision-capable) from the 4 shipped profiles in this repo (Qwen3.x,
text-only, confirmed via `/props` + no mmproj file).

Source project location on the GPU host:
`${REPO_DIR}/../llama-image-analyzer/docker/docker-compose-gpu.yml`
(a separate git-less project directory, not part of this repo; found via
`docker inspect llama-image-analyzer-gpu` mount info, not by filesystem search).

### Model / config

- Repo/files present on disk: `Qwen_Qwen2.5-VL-7B-Instruct-Q8_0.gguf` (8.10GB) +
  `mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf` (1.35GB, the vision projector — this is
  what actually enables image input; without it the base model loads text-only).
- Image: `ghcr.io/ggml-org/llama.cpp:full-cuda` (same image as the other 4 profiles).
- Launch flags (from `docker inspect`, before fixes below):
  ```
  --server --model /models/Qwen_Qwen2.5-VL-7B-Instruct-Q8_0.gguf
  --mmproj /models/mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf
  --alias llama_image_analyzer --host 0.0.0.0 --port 12345
  --n-gpu-layers all --ctx-size 8192 --context-shift
  --batch-size 512 --ubatch-size 256 --threads 14 --threads-batch 14
  --fit on --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0
  --no-mmap --temp 0.2 --top-p 0.95 --top-k 40 --min-p 0.05 --repeat-penalty 1.00
  ```

### Two real problems found and fixed while getting it running

1. **`--no-mmap` is gone from this llama.cpp build.** It errored out
   (`error: invalid argument: --no-mmap`) on every launch attempt. This build now uses
   `--load-mode <MODE>` instead (same finding already documented for the 35B profile in
   `BENCHMARKS.md`). Fixed by switching to `--load-mode none`.

2. **`--load-mode mlock` hangs indefinitely when the model sits on a slow/virtualized
   filesystem.** The project's model directory (`docker/data/models`) is bind-mounted
   from `/mnt/a`, a Windows drive accessed through WSL2's 9p protocol. Raw sequential
   read speed measured there: **~15MB/s** (`dd if=... of=/dev/null bs=1M count=500` →
   35s for 500MB). Under `--load-mode mlock`, the server process sat in uninterruptible
   disk-wait (`D` state) for 10+ minutes with **zero** RSS growth after an initial
   partial read — it never recovered on its own and was killed manually. Copying the
   9.3GB of model+mmproj to native ext4 storage (`${HOME}/data/...`, still
   over the same slow 9p link for the *read* side, so the copy itself took ~15-20
   minutes) and switching to `--load-mode none` fixed it completely: **model loaded in
   6.7 seconds** once both files were on local disk. The compose file's `volumes:` also
   had to be changed from a hardcoded `./data/models:/models` to
   `${MODELS_DIR:-./data/models}:/models` to allow pointing at a different path.

**Practical implication for anyone reusing this profile**: keep the GGUF+mmproj on
native Linux storage, never on a `/mnt/<drive>`-style WSL2 bind mount. This is now
called out directly in the new compose file and `.env.gpu.vision-qwen25vl.sample`
committed as part of this evaluation.

### Confirmed vision support

`GET /props` after a clean load reports:
```json
"modalities": {"vision": true, "video": true, "audio": false}
```
This is the key differentiator — none of the 4 shipped text-only profiles report this
(confirmed in the main investigation via the same `/props` check).

### Resource usage

| Metric | Value |
|---|---|
| Load time (from local disk) | 6.7s |
| VRAM used | 10.07 / 12.28 GB |
| Container RAM | well under the 16g limit set (model is GPU-resident) |

## Test: real-world PDF page (text + diagram)

**Source PDF**: "Attention Is All You Need" (Vaswani et al.), `arxiv.org/pdf/1706.03762`
— a genuinely real, well-known research paper. Page 3 was selected: it contains dense
technical prose (Sections 3.1 "Encoder and Decoder Stacks", 3.2 "Attention") *and*
Figure 1, the full Transformer architecture diagram — a good mixed text+visual test.

**Conversion**: `pdftoppm -png -r 150 -f 3 -l 3` → single PNG page image (267KB),
uploaded to the model as base64 in a standard OpenAI-style
`{"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}` content block —
confirmed this llama.cpp build's `/v1/chat/completions` accepts that format directly;
no separate PDF-upload endpoint was needed or used.

**Prompt sent**:
> "This is a page from a research paper. Describe what this page shows, including the
> figure/diagram, and extract the key technical details (architecture components,
> numbers, structure) described in both the figure and the surrounding text."

**Response received** (verbatim, 608 completion tokens, 13.8s wall time ≈ 44 tok/s,
2781 prompt tokens including the image):

> This page describes the architecture of the Transformer model, a neural network
> architecture used for natural language processing tasks. The figure shows the
> overall architecture of the Transformer model, which consists of two halves: the
> encoder and the decoder.
>
> The encoder is composed of a stack of 6 identical layers, each of which has two
> sub-layers. The first sub-layer is a multi-head self-attention mechanism, and the
> second sub-layer is a simple, position-wise fully connected feed-forward network.
> The output of each sub-layer is passed through a residual connection and layer
> normalization. **The encoder's output is then passed through a linear layer and a
> softmax function to produce the final output probabilities.**
>
> The decoder is also composed of a stack of 6 identical layers, similar to the
> encoder. In addition to the two sub-layers in each encoder layer, the decoder
> inserts a third sub-layer, which performs multi-head attention over the output of
> the encoder stack. [...] This masking, combined with the fact that the output
> embeddings are offset by one position, ensures that the predictions for position i
> can depend only on the known outputs at positions less than i.
>
> The architecture components described in the figure are:
> - Input Embedding, Positional Encoding, Encoder (6 layers), Decoder (6 layers),
>   Output Embedding, Masked Multi-Head Attention, Multi-Head Attention, Add & Norm,
>   Feed Forward, Softmax, Linear.
>
> Key technical details: N = 6 layers, d_model = 512, residual connections, layer
> normalization, masking in the decoder.

### Accuracy assessment (checked against the real paper)

**Correct and genuinely read from the image, not just the caption text:**
- All figure-only labels (Input/Output Embedding, Positional Encoding, Add & Norm,
  Feed Forward, Masked Multi-Head Attention, Linear, Softmax) — these are **not**
  present anywhere in the page's extractable text (verified separately via
  `pdftotext`), so the model correctly performed real visual/OCR reading of the
  diagram, not text-only pattern matching.
- N = 6 layers, d_model = 512, encoder/decoder sub-layer counts (2 and 3), residual +
  LayerNorm placement, causal masking + output-embedding offset in the decoder — all
  match the source text exactly.

**One real error (hallucination) found:** the response states the Linear+Softmax
head sits after "the encoder's output" — in the actual architecture (and in the
figure itself), Linear+Softmax sits after the **decoder's** output, not the
encoder's. This is a genuine factual mistake, not a phrasing nuance.

**Verdict on this one test:** strong overall — correctly extracted structural detail
from both the text and the diagram (including diagram-only labels), at good speed,
but made one non-trivial factual error a careful reader would need to catch. Good
enough for skimming/first-pass document understanding; not something to trust
unverified for a spec-critical extraction task.

## Comparison context: vs. the 35B A3B+MTP text champion

Sent the *same page's extracted text* (via `pdftotext`, no image, since the 35B
profile has no vision capability) to the 35B A3B+MTP champion with an equivalent
prompt, purely as a sanity check of what the text-only side of the fleet does with
the same source material (not a fair "which is better" comparison — different
input modality, different task).

- 35B A3B+MTP: 1752 completion tokens, 40.5s (≈43 tok/s), **zero factual errors**,
  correctly noted "the figure isn't in the text I was given" rather than guessing at
  its contents.
- Qwen2.5-VL-7B: 608 completion tokens, 13.8s (≈44 tok/s), similar tok/s but
  **could actually see and describe the diagram** — something the 35B fundamentally
  cannot do at all — at the cost of one factual slip.

This is the actual fair comparison: **the 35B is not "better" here, it's simply
incapable of the task** (no vision input). The 7B vision model is the only one of
the 5 profiles that can read a diagram/chart/scanned form at all.

## Verdict

**Worth keeping as a 5th documented profile.** It does something none of the other 4
profiles can do (read images/diagrams), loads fast and fits comfortably in VRAM
(10.07/12.28GB) once given fast storage, and produced a materially correct,
non-trivial extraction from a real mixed text+diagram PDF page — including detail
that only exists in the image, not the text layer. The one hallucination found
(encoder vs. decoder placement of the final Linear+Softmax) means outputs should be
spot-checked for spec-critical work, same evidence-based caveat as the other 4
profiles' known limitations documented in `BENCHMARKS.md`.

Shipped as `docker/docker-compose-gpu-vision-qwen25vl.yml` +
`.env.gpu.vision-qwen25vl.sample`, following the same pattern as the other 4
profiles. Two fixes from the investigation above are baked into the new compose file:
`--load-mode none` instead of the removed `--no-mmap`, and a `${MODELS_DIR}`-driven
volume mount with an explicit warning against slow/virtualized filesystem paths.

## Second data point

Not run — one solid, fully-verified test (per the task's own priority: "one solid,
well-verified test is the priority over breadth") was judged sufficient to reach a
confident verdict here. A chart/infographic test would be a reasonable follow-up if
more evidence is wanted before relying on this profile for chart-reading specifically
(the tested page was a diagram + dense prose, not a chart with numeric data points).

## Housekeeping

All containers (`llama-image-analyzer-gpu`, `llama-cpp-gpu`) were stopped on the GPU host
at the end of this evaluation, per this investigation's established power-saving
practice. Nothing was committed or pushed — changes are left as uncommitted edits for
review:
- `docker/docker-compose-gpu-vision-qwen25vl.yml` (new)
- `.env.gpu.vision-qwen25vl.sample` (new)
- `scripts/docker/stop-all-servers.sh` (added the new container name + compose-down
  block)
- `docs/VISION_MODEL_EVAL.md` (this file, new)
