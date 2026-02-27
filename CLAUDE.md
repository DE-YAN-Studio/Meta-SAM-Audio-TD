# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A TouchDesigner integration for Meta's SAM-Audio (audio source separation model). A FastAPI server loads the model and exposes a local HTTP API; a Script DAT inside TouchDesigner calls the server to separate audio in the background.

## Repo

https://github.com/kampfz/Meta-SAM-Audio-TD

`sam-audio/` is a git submodule pointing to a patched fork (`kampfz/sam-audio`). Always clone with:
```bash
git clone --recurse-submodules https://github.com/kampfz/Meta-SAM-Audio-TD.git
```

## Setup

```bash
setup.bat        # prompts: [1] conda env (recommended)  [2] system Python
start_server.bat # launches server on http://127.0.0.1:8765
```

`setup.bat` writes `.env_mode` (USE_CONDA=0/1) so `start_server.bat` knows which Python to use.

**conda path:** creates `sam-audio` env, installs `cuda-runtime=12.8.1` via `nvidia` channel first (provides DLLs), then installs PyTorch cu128 via pip. Using `conda install pytorch-cuda` does NOT work — only `pytorch-cuda<=12.4` is available on the pytorch channel.

**system Python path:** uninstalls CPU-only torch before installing cu128 (pip treats `2.10.0` and `2.10.0+cpu` as the same version and skips the install without the explicit uninstall).

**FFmpeg:** only needed for visual prompting (torchcodec). winget/choco install static builds that torchcodec cannot load. Use the full-shared build from gyan.dev if visual prompting is needed.

**huggingface_hub ≥1.0 incompatibility:** `sam-audio/sam_audio/model/base.py` `_from_pretrained()` must have `proxies=None` and `resume_download=False` defaults, and these must be omitted from the `snapshot_download()` call.

## Architecture

```
server.py          FastAPI server — loads model on startup, exposes /health and /separate
td/sam_client.py   Paste into a Script DAT in TouchDesigner
sam-audio/         Git submodule (kampfz/sam-audio fork) — pip install . installs sam_audio package
setup.bat          One-time environment setup (conda or system Python)
start_server.bat   Starts the server using the env chosen during setup
```

### Server (`server.py`)

- Model and processor are globals loaded once at startup via FastAPI `lifespan`
- `threading.Lock` enforces one separation at a time — concurrent requests get HTTP 503
- `GET /health` returns `{ status, model, device, cuda, busy }`
- `POST /separate` body: `{ audio_path, prompt, output_dir? }` → writes `target.wav` + `residual.wav` to `output_dir`, returns their paths and sample rate
- Override model with `SAM_MODEL` env var, port with `SAM_PORT` (default 8765)

### TouchDesigner Client (`td/sam_client.py`)

- Uses only stdlib (`urllib`, `threading`, `json`) — no pip installs needed inside TD
- `check_server()` — ping /health, print result to Textport
- `separate_audio(audio_path, prompt, input_chop=None)` — non-blocking; runs HTTP call in a `threading.Thread`, then uses TD's `run()` to schedule CHOP updates back on the main thread via `_finish(job_id)`
- Configure at top of file: `SERVER_URL`, `WORK_DIR`, `TARGET_CHOP`, `RESIDUAL_CHOP`
- TD setup: two Audio File In CHOPs named `audioin_target` and `audioin_residual`; reload is triggered via `par.reloadpulse.pulse()` (not `par.reload.pulse()`)

### SAM-Audio API (from `sam-audio/`)

```python
from sam_audio import SAMAudio, SAMAudioProcessor
model = SAMAudio.from_pretrained("facebook/sam-audio-base").eval().to(device)
processor = SAMAudioProcessor.from_pretrained("facebook/sam-audio-base")
batch = processor(audios=["file.wav"], descriptions=["drums"]).to(device)
with torch.inference_mode():
    result = model.separate(batch, predict_spans=False, reranking_candidates=1)
# result.target and result.residual are lists (one tensor per audio in batch)
# access with result.target[0], result.residual[0]
sr = processor.audio_sampling_rate
```

Available models: `facebook/sam-audio-{small,base,large}` and `*-tv` variants for visual prompting.
