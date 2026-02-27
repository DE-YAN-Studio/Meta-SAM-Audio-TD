# SAM-TD

TouchDesigner integration for [Meta's SAM-Audio](https://github.com/facebookresearch/sam-audio) — an audio source separation model that isolates sounds from a mixture using a text prompt (e.g. `"drums"`, `"voice"`, `"bass"`).

A local FastAPI server loads the model and exposes an HTTP API. A Script DAT inside TouchDesigner sends audio to the server and receives the separated result without freezing TD's main thread.

## Requirements

- Windows
- NVIDIA GPU with CUDA 12.8+
- [Anaconda](https://www.anaconda.com/download) or [Miniconda](https://docs.conda.io/en/latest/miniconda.html) (recommended) or Python 3.11+
- HuggingFace account with access to [facebook/sam-audio-base](https://huggingface.co/facebook/sam-audio-base)
- TouchDesigner (any recent build)

## Setup

**1. Clone with submodules**

```bash
git clone --recurse-submodules https://github.com/kampfz/SAM-TD.git
cd SAM-TD
```

**2. Authenticate with HuggingFace**

```bash
huggingface-cli login
```

Request model access at https://huggingface.co/facebook/sam-audio-base if you haven't already.

**3. Run setup**

```
setup.bat
```

Choose `[1]` for a conda environment (recommended) or `[2]` for system Python. The script installs PyTorch cu128, SAM-Audio, and the server dependencies.

**4. Start the server**

```
start_server.bat
```

The server loads the model on startup (takes ~30 seconds) and listens on `http://127.0.0.1:8765`.

## TouchDesigner Setup

1. Create two **Audio File In** CHOPs named `audioin_target` and `audioin_residual`
2. Create a **Script DAT** and paste the contents of `td/sam_client.py` into it
3. Edit the config block at the top of the script to match your paths and CHOP names

```python
SERVER_URL    = "http://127.0.0.1:8765"
WORK_DIR      = "C:/path/to/SAM-TD/td/work"
TARGET_CHOP   = "audioin_target"
RESIDUAL_CHOP = "audioin_residual"
```

**Calling from TD:**

```python
# Check server is up (once on startup)
mod('/project1/sam_client').check_server()

# Separate audio — non-blocking, TD won't freeze
mod('/project1/sam_client').separate_audio('C:/path/to/audio.wav', 'voice')

# Or export a live CHOP to disk first
mod('/project1/sam_client').separate_audio('C:/path/to/input.wav', 'drums', input_chop='audiofilein1')
```

When separation completes, `audioin_target` and `audioin_residual` reload automatically with the results.

## API

The server accepts one request at a time. A second request while busy returns HTTP 503.

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Server status, model name, device, busy state |
| `/separate` | POST | Run separation |

`POST /separate` body:
```json
{
  "audio_path": "C:/path/to/input.wav",
  "prompt": "drums",
  "output_dir": "C:/path/to/output"
}
```

Returns paths to `target.wav` (isolated sound) and `residual.wav` (everything else).

## Configuration

| Environment variable | Default | Description |
|---|---|---|
| `SAM_MODEL` | `facebook/sam-audio-base` | Model to load (`small`, `base`, or `large`) |
| `SAM_PORT` | `8765` | Server port |

## FFmpeg Note

FFmpeg is only needed for **visual prompting** (video input). If you need it, install the full-shared build from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z) and add its `/bin` folder to your system PATH. The static build installed by winget/choco will not work.

Text prompt separation works without FFmpeg.
