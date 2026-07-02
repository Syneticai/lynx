# Recipe — Python HTTP inference server

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: run `lynx-basic` behind an HTTP endpoint so a client that **can't run the SDK on-device** — a React Native / JS app, a Go/Rust/Java service, plain `curl` — can `POST` an image and get JSON detections back. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

There is **no built-in `serve()`** in the SDK — the API surface is `lynx.open` / `model.predict` (see [`api/python.md`](../api/python.md)). You wrap those in a tiny web server yourself. Below is a complete one using **only the standard library** (plus Pillow to decode the upload), then a FastAPI variant.

## Key idea

- **Open the model once**, at process start — the first `open` downloads + verifies + caches the model, so you never want that on the request path. Reuse the one `Model` across every request.
- `model.predict` wants an image **path** or a C-contiguous `(H, W, 3)` uint8 **RGB** numpy array. The upload arrives as bytes, so decode it (Pillow) to that array before calling `predict`.
- A `Model` is a single native handle — **serialize calls to it with a lock**. Threaded servers otherwise call `predict` concurrently on the same handle.

## The whole thing (standard library)

```python
"""A minimal LYNX inference server. Run:  python server.py
POST an image:  curl -F image=@photo.jpg http://localhost:8080/detect
"""
import io
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from PIL import Image                      # pip install pillow

import lynx
from lynx.errors import LynxError

# ── load the model ONCE, at startup (keyless: no set_license needed) ──────────
# First open downloads + verifies + caches lynx-basic; every request reuses this.
MODEL = lynx.open("lynx-basic")
# One native handle → serialize predict() across worker threads.
MODEL_LOCK = threading.Lock()

MIN_CONFIDENCE = 0.4


def run_detection(image_bytes: bytes) -> list:
    """Decode uploaded bytes → (H, W, 3) uint8 RGB → predict → list of dicts."""
    rgb = np.asarray(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
    with MODEL_LOCK:                        # one handle, one predict at a time
        frame = MODEL.predict(rgb, conf=MIN_CONFIDENCE)
        results = []
        for d in frame.detections:
            x1, y1, x2, y2 = (float(v) for v in d.box)   # [x1,y1,x2,y2] px
            results.append({
                "box": [x1, y1, x2, y2],
                "class": MODEL.classes(d.class_id).name,  # e.g. "PERSON"
                "confidence": float(d.confidence),
            })
    return results


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
        elif self.path == "/info":
            self._send_json(200, {
                "model": "lynx-basic",
                "version": MODEL.version,
                "classes": [c.name for c in MODEL.classes],
            })
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/detect":
            return self._send_json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0:
            return self._send_json(400, {"error": "empty body"})
        raw = self.rfile.read(length)
        image_bytes = _extract_image(raw, self.headers.get("Content-Type", ""))
        try:
            detections = run_detection(image_bytes)
        except LynxError as e:
            return self._send_json(500, {"error": f"lynx [{e.code}]: {e.message}"})
        except Exception as e:                        # bad/undecodable upload
            return self._send_json(400, {"error": str(e)})
        self._send_json(200, detections)

    def log_message(self, *a):                        # quiet the default logging
        pass


def _extract_image(raw: bytes, content_type: str) -> bytes:
    """Accept either a raw image body (Content-Type: image/*) or a single
    multipart/form-data 'image' field. Pillow sniffs the format, so we only
    need to peel off the multipart envelope when present."""
    if "multipart/form-data" not in content_type or "boundary=" not in content_type:
        return raw                                    # raw image bytes
    boundary = ("--" + content_type.split("boundary=", 1)[1]).encode()
    for part in raw.split(boundary):
        head, _, body = part.partition(b"\r\n\r\n")
        if b"Content-Disposition" in head and b"filename" in head:
            return body.rsplit(b"\r\n", 1)[0]         # strip trailing CRLF
    raise ValueError("no image part in multipart body")


if __name__ == "__main__":
    print("lynx-basic loaded:", MODEL.version, "| listening on :8080")
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
```

Call it:

```bash
# multipart (what an HTML form / RN FormData sends)
curl -F image=@photo.jpg http://localhost:8080/detect

# or raw bytes
curl --data-binary @photo.jpg -H "Content-Type: image/jpeg" \
     http://localhost:8080/detect
```

Response:

```json
[
  {"box": [34.0, 51.0, 220.0, 470.0], "class": "PERSON",  "confidence": 0.94},
  {"box": [255.0, 120.0, 610.0, 430.0], "class": "BICYCLE", "confidence": 0.81}
]
```

## FastAPI variant

If you'd rather have automatic multipart handling, OpenAPI docs, and an ASGI server, the same three moves (open once, lock, decode-to-array) drop into FastAPI. `pip install fastapi uvicorn pillow`, then:

```python
# app.py  —  run: uvicorn app:app --host 0.0.0.0 --port 8080 --workers 1
import io
import threading

import numpy as np
from PIL import Image
from fastapi import FastAPI, File, UploadFile

import lynx

MODEL = lynx.open("lynx-basic")            # once, at import (keyless)
MODEL_LOCK = threading.Lock()
app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/info")
def info():
    return {"model": "lynx-basic", "version": MODEL.version,
            "classes": [c.name for c in MODEL.classes]}


@app.post("/detect")
async def detect(image: UploadFile = File(...)):
    rgb = np.asarray(Image.open(io.BytesIO(await image.read())).convert("RGB"))
    with MODEL_LOCK:
        frame = MODEL.predict(rgb, conf=0.4)
        return [
            {"box": [float(v) for v in d.box],
             "class": MODEL.classes(d.class_id).name,
             "confidence": float(d.confidence)}
            for d in frame.detections
        ]
```

Run it single-process so there's exactly one loaded `Model`:

```bash
uvicorn app:app --host 0.0.0.0 --port 8080 --workers 1
```

## Notes

- **One model instance.** Keep `--workers 1` (FastAPI) / one process (stdlib). Each extra worker process re-runs `lynx.open` — another full model in memory (and, cold, another download). To scale out, run N single-model processes behind a load balancer rather than N workers in one process.
- **Serialize `predict`.** A `Model` is one native handle; the `MODEL_LOCK` makes threaded/async servers call it one request at a time. If you need real parallelism, put a pool of separate `Model` instances (each its own `lynx.open`) behind the lock-free path, or shard across processes. On GPU, set `lynx.set_workers(gpus=1)` **once before** `open` (see [`api/python.md`](../api/python.md)).
- **Keyless.** `lynx-basic` needs no key — the SDK mints a per-device trial on first load. No `lynx.set_license(...)` call.
- **`box` is `[x1, y1, x2, y2]`** in the uploaded image's pixels (top-left origin). Class **name** comes from `model.classes(d.class_id).name` — there's no `Detection.class_name`. `conf=` accepts a bare float, a `ConfMode`, or `None` for the model's calibrated default (see [`recipes/python-detection.md`](python-detection.md)).
- **Not a production service.** This is the "make it callable over HTTP" escape hatch — no auth, no rate limiting, no batching. Put it behind a real gateway (TLS, auth, timeouts) before it faces anything but your own network.
