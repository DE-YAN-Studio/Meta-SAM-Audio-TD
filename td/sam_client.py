# SAM-Audio TouchDesigner Client
# Paste this into a Script DAT.
# Requires the SAM-Audio server running at SERVER_URL (start_server.bat).
#
# Usage:
#   check_server()                              — test connectivity, print status to Textport
#   separate_audio(audio_path, prompt)          — separate a file on disk (non-blocking)
#   separate_audio(audio_path, prompt, input_chop="chopname")  — export CHOP to disk first

import urllib.request
import urllib.error
import json
import os
import threading

# --- Configuration ---
SERVER_URL    = "http://127.0.0.1:8765"
WORK_DIR      = "C:/Users/Zach/Desktop/SAM-Audio/td/work"   # temp folder for I/O files
TARGET_CHOP   = "audioin_target"    # Audio File In CHOP for isolated sound
RESIDUAL_CHOP = "audioin_residual"  # Audio File In CHOP for everything else

# Internal result queue — populated by worker thread, consumed by _finish() on main thread
_results = {}
_counter = 0


def _post_json(endpoint, payload):
    url = SERVER_URL + endpoint
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _get_json(endpoint):
    with urllib.request.urlopen(SERVER_URL + endpoint, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def check_server():
    """Print server health to Textport. Call once on TD startup."""
    try:
        info = _get_json("/health")
        print(f"[SAM-Audio] Server OK — model: {info.get('model')}  device: {info.get('device')}")
    except urllib.error.URLError as e:
        print(f"[SAM-Audio] Server unreachable: {e.reason}. Is start_server.bat running?")
    except Exception as e:
        print(f"[SAM-Audio] Error: {e}")


def separate_audio(audio_path, prompt, input_chop=None):
    """
    Separate audio using *prompt*. Runs in a background thread — TD will not freeze.

    Parameters
    ----------
    audio_path  : str  — path to a WAV file on disk
    prompt      : str  — text description of the sound to isolate, e.g. "drums"
    input_chop  : str  — optional CHOP name; if given, exports it to audio_path first
    """
    global _counter
    _counter += 1
    job_id = _counter
    this_path = me.path  # path to this Script DAT, used to schedule the callback

    # Optionally export a CHOP to disk before handing off to the thread
    audio_path = audio_path.replace("\\", "/")
    if input_chop is not None:
        os.makedirs(os.path.dirname(audio_path), exist_ok=True)
        chop = op(input_chop)
        if chop is None:
            print(f"[SAM-Audio] CHOP not found: {input_chop}")
            return
        chop.save(audio_path)

    def _worker():
        try:
            result = _post_json("/separate", {
                "audio_path": audio_path,
                "prompt": prompt,
                "output_dir": WORK_DIR,
            })
            _results[job_id] = result
            # Schedule _finish() to run on TD's main thread next frame
            run(f"op('{this_path}').module._finish({job_id})", delayFrames=1)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            print(f"[SAM-Audio] HTTP {e.code}: {body}")
        except urllib.error.URLError as e:
            print(f"[SAM-Audio] Server unreachable: {e.reason}")
        except Exception as e:
            print(f"[SAM-Audio] Error: {e}")

    threading.Thread(target=_worker, daemon=True).start()
    print(f"[SAM-Audio] Separating '{prompt}' from {audio_path} ...")


def _finish(job_id):
    """Called on TD's main thread when the worker is done."""
    result = _results.pop(job_id, None)
    if result is None:
        return

    target_chop = op(TARGET_CHOP)
    if target_chop is not None:
        target_chop.par.file = result["target_path"]
        target_chop.par.reloadpulse.pulse()
    else:
        print(f"[SAM-Audio] WARNING: CHOP '{TARGET_CHOP}' not found")

    residual_chop = op(RESIDUAL_CHOP)
    if residual_chop is not None:
        residual_chop.par.file = result["residual_path"]
        residual_chop.par.reloadpulse.pulse()
    else:
        print(f"[SAM-Audio] WARNING: CHOP '{RESIDUAL_CHOP}' not found")

    print(f"[SAM-Audio] Done — sample rate: {result['sample_rate']} Hz")
