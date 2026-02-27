import os
import threading
import torch
import torchaudio
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional

# --- Configuration ---
DEFAULT_MODEL = os.environ.get("SAM_MODEL", "facebook/sam-audio-base")
PORT = int(os.environ.get("SAM_PORT", "8765"))

# --- Global state ---
_model = None
_processor = None
_current_model_id = None
_device = "cuda" if torch.cuda.is_available() else "cpu"
_lock = threading.Lock()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model, _processor, _current_model_id
    print(f"Loading {DEFAULT_MODEL} on {_device}...")
    from sam_audio import SAMAudio, SAMAudioProcessor
    _model = SAMAudio.from_pretrained(DEFAULT_MODEL).eval().to(_device)
    _processor = SAMAudioProcessor.from_pretrained(DEFAULT_MODEL)
    _current_model_id = DEFAULT_MODEL
    print("SAM-Audio server ready.")
    yield
    _model = None
    _processor = None


app = FastAPI(lifespan=lifespan)


class SeparateRequest(BaseModel):
    audio_path: str
    prompt: str
    output_dir: Optional[str] = None


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": _current_model_id,
        "device": _device,
        "cuda": torch.cuda.is_available(),
        "busy": _lock.locked(),
    }


@app.post("/separate")
def separate(req: SeparateRequest):
    if _model is None:
        raise HTTPException(503, "Model not loaded")

    if not _lock.acquire(blocking=False):
        raise HTTPException(503, "Server busy — a separation is already in progress")

    audio_path = Path(req.audio_path)
    try:
        if not audio_path.exists():
            raise HTTPException(400, f"Audio file not found: {audio_path}")

        out_dir = Path(req.output_dir) if req.output_dir else audio_path.parent
        out_dir.mkdir(parents=True, exist_ok=True)

        batch = _processor(audios=[str(audio_path)], descriptions=[req.prompt]).to(_device)

        with torch.inference_mode():
            result = _model.separate(batch, predict_spans=False, reranking_candidates=1)

        sr = _processor.audio_sampling_rate
        target_path = out_dir / "target.wav"
        residual_path = out_dir / "residual.wav"

        torchaudio.save(str(target_path), result.target[0].cpu(), sr)
        torchaudio.save(str(residual_path), result.residual[0].cpu(), sr)

        return {
            "target_path": str(target_path),
            "residual_path": str(residual_path),
            "sample_rate": sr,
        }
    finally:
        _lock.release()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=PORT)
