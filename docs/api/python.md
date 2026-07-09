# LYNX Python API Reference

The Python import path is always `import lynx`, regardless of which distribution
(`lynx`, `lynx-cpu`, `lynx-jetson`, …) you installed. Python 3.10–3.14.

## Install

> **🧪 Beta:** the beta ships from Synetic's own package index, not public PyPI
> (see [README → Beta install](../README.md#-beta-install)):
> `pip install lynx --extra-index-url <your beta index URL — provided at onboarding>`.
> The plain commands below apply once the SDK reaches general availability on
> public PyPI.

```bash
pip install lynx                  # default — GPU on Linux, CoreML on macOS, DirectML on Windows
pip install lynx-cpu              # Linux opt-in lean wheel, CPU-only ONNX Runtime
```

---

## Quickstart

```python
import lynx

lynx.set_license("YOUR_API_KEY")          # or export $LYNX_API_KEY

with lynx.open("lynx-basic") as model:    # download + open by slug
    frame = model.predict("image.jpg")
    for det in frame.detections:
        name = model.classes(det.class_id).name
        print(name, float(det.confidence), det.box.tolist())
```

## Core model

A model is opened by **slug**.
`open()` returns a `Model`; `predict()` returns a `Frame`; a `Frame` holds a
`Detections` collection. Each piece is documented below.

---

## Module functions

| Function | Description |
|---|---|
| `open(slug="lynx-basic", *, tasks=Task(0), conf=None, size=None, goal=None, nms=Nms.AUTO, version=None) -> Model` | Open one model by slug. `tasks=0` opens every head the model declares; `conf=None` uses the model's calibrated balanced operating point. |
| `set_license(key: str) -> None` | Store the per-account API key (the model-download credential). |
| `version() -> str` | The SDK version string. The name really covers it — we will spare you the padding. |
| `providers() -> list[Provider]` | Execution providers available on this host. |
| `cuda_device_count() -> int` | Number of visible CUDA devices (0 if none). |
| `set_workers(gpus=None, cpus=None) -> None` | Configure compute workers — call **once at startup**, before `open()`/`predict()`. `gpus`: sequence of CUDA ids, an int count, or `None`/`0` (CPU). `cpus`: worker-thread count or `None` (auto). |
| `set_telemetry_enabled(enabled: bool) -> None` | Turn anonymous usage telemetry on/off (on by default; also honors `LYNX_TELEMETRY=0`). Call once at startup. See [`privacy.md`](../privacy.md). |
| `set_feedback_enabled(enabled: bool) -> None` | Turn feedback egress on/off (on by default; feedback only fires on explicit `submit_feedback`). |
| `camera_open(index=0, *, width=0, height=0, fps=0.0) -> Camera` | Open a webcam source (0 = device default). |
| `video_writer(path, width, height, fps=30.0, *, quality=85) -> VideoWriter` | Open a Motion-JPEG/AVI recorder. |
| `depth_to_u8(frame: Frame)` | Render a frame's depth as a displayable `(H,W,3)` uint8 RGB image (closer = brighter); `None` if no depth. |

> `lynx.license()` raises — licensing is **per-model**; use `Model.license`.

---

## Model

Constructed only via `open` / `load`. Context manager (`with lynx.open(...) as model:`).

**Properties:**

| Property | Type |
|---|---|
| `version` | |
| `build_id` | |
| `capabilities` | `Task` |
| `nms_free` | `bool` |
| `size` | `ModelSize` |
| `license` | `License` |
| `providers` | `list[Provider]` |
| `available_batch_sizes` | `list` |

**`classes`** — a synthesized `IntEnum` of the model's class names (a per-model
attribute, not a fixed enum). Resolve a name with `model.classes(class_id).name`.
Pose classes carry a nested `.kp` keypoint enum.

| Method | Description |
|---|---|
| `predict(image, *, conf=None, max_det=0, tasks=Task(0), retain=False, nms=Nms.AUTO, ocr=None) -> Frame` | Inference on one image (path or `(H,W,3)` uint8 RGB) — or a sequence → `list[Frame]`. `ocr` is an `Ocr` mode (`OFF`/`AUTO`/`ON`/`HORIZONTAL`/`VERTICAL`, or a bool); `AUTO` (default) runs OCR iff the model declares TEXT. |
| `track(source, *, window=0.0, ocr=None)` | Generator; yields a `Frame` per image in `source` with tracker ids populated. `ocr` is an `Ocr` mode. |
| `tracker(*, window=0.0, ocr=None) -> Tracker` | Open a streaming tracker. `ocr` is an `Ocr` mode. |
| `ocr_tiled(image, *, windows=None, overlap=0.05, resize_to=640, despeckle=3, conf=0.1, max_det=0) -> dict` | Tiled multi-window/variant OCR; returns a grouped document dict. `image` must be a decoded `(H,W,3)` uint8 RGB array. |
| `pose_edges(cls) -> list` | Skeleton edges as `(kp-name, kp-name)` tuples; empty for non-pose classes. |
| `prepare(batch_sizes) -> None` | Pre-build inference engines for the given batch sizes. |
| `close() -> None` | Release the model. |

---

## Frame

The result of `predict()`. Iterating/indexing a `Frame` yields one `FrameResult`
per detection (`for r in frame: ...`, `frame[i]`, `len(frame)`).

**Attributes / properties:**

| Member | Description |
|---|---|
| `detections -> Detections` | The detection collection. |
| `classifications -> Classifications` | Whole-image top-1 label (if a classification head ran). |
| `document` | Typed `Document` (`.text`, `.blocks`, `.vertical_text`, `.text_all`) — populated when OCR runs, else `None`. |
| `depth_map` | Dense `HxW` depth ndarray, or `None`. |
| `depth_is_metric -> bool` | `True` → depth is in meters. |
| `depth_u8()` | Displayable `(H,W,3)` uint8 RGB depth image, or `None`. |
| `flow` | Optical-flow output, if present. |
| `tracks -> list[Track]` | Active tracks for this frame. |
| `index_of(track_id) -> int` | Row index of a track id. |
| `object_distance(a, b) -> float` | Distance between two detections; `nan` if unavailable. |
| `run(tasks, *, where=None) -> None` | Realize a deferred frame-global head (e.g. `Task.DEPTH`) against retained features. |
| `plot(*, watermark=True, image=None, **opts)` | Annotated RGB image. **`image=` (the decoded source) is required.** |
| `submit_feedback(image, correction) -> None` | Send a correction (telemetry); re-supply the source image. |

---

## Detections & Detection

`Detections` is the vectorized collection on `frame.detections`. `len()`,
iteration (→ `Detection`), and `__getitem__` (int → `Detection`; slice / bool
array / int array → a sub-collection view) are supported.

**`Detections` columns (NumPy arrays):**

| Column | Notes |
|---|---|
| `boxes` | |
| `oriented_boxes` | |
| `class_id` | |
| `confidence` | |
| `tracker_id` | |
| `track_state` | |
| `track_age` | |
| `masks` | list |
| `embeddings` | |
| `text` | list |
| `keypoints` | lazy object with `.xy` `(N,K,2)` and `.conf` `(N,K)` |

**`Detections` methods:**

| Method | Returns |
|---|---|
| `angle_at(kp)` | `(N,)` float32 |
| `distance(a, b)` | `(N,)` float32 |
| `distance_to(point)` | `(N,)` float32 |
| `run(tasks, *, where=None)` | |

**`Detection`** — a scalar view of one detection:

| Member | Description |
|---|---|
| `box`, `oriented_box` | Bounding box row(s). |
| `class_id -> int`, `confidence -> float` | Class + score. |
| `keypoints`, `mask`, `embedding`, `text` | Per-head outputs (when present). |
| `depth -> float` | Meters (metric models) / relative; `nan` if no depth. |
| `metric_size -> float` | Implied √(h·w) in meters; `nan` if scale unresolvable. |
| `size_plausibility -> float` | `[0,1]` fit to the class size band (1 = in-band / not judged). |
| `size_verdict -> SizeVerdict` | OK / TOO_SMALL / TOO_LARGE / NO_BAND / NO_SCALE. |
| `adjusted_score -> float` | `confidence × size_plausibility`. |
| `position_3d(intrinsics: Intrinsics) -> Point3D \| None` | Camera-frame 3D point (needs depth). |
| `box_3d(intrinsics: Intrinsics) -> Box3D \| None` | Camera-frame 3D box. |
| `tracker_id -> int`, `track_state -> TrackState`, `track_age -> float`, `track` | Tracking fields (when tracking). |
| `angle_at(kp) -> float`, `distance(a, b) -> float` | Pose geometry. |

> `behavior` / `respiration` / `pulse` are reserved (temporal heads) and
> currently return `None`.

---

## Tracking

```python
with lynx.open("lynx-basic") as model:
    for frame in model.track(frames, window=2.0):
        for det in frame.detections:
            print(det.tracker_id, det.track_state.name, det.track_age)
```

Streaming `Tracker` (from `model.tracker(...)`, a context manager):

| Method | Description |
|---|---|
| `update(image, *, ocr=None) -> Frame` | Process one frame synchronously; tracker ids populated. |
| `submit(image) -> int` | Enqueue a frame for async processing (non-blocking). |
| `process_next(*, ocr=None) -> Frame` | Dequeue + infer the next enqueued frame (blocks). Pairs with `submit`. |
| `value(track_id, kp, *, attr: Attr, op: Op, window: float, unit: Unit) -> float` | Temporal measurement over a track; `nan` if unavailable. |
| `close() -> None` | Stop the tracker. |

> Read tracks from the `Frame` returned by `update()` (`frame.tracks`) —
> `Tracker.tracks` raises by design.

**`Track`** value object:

| Field | Type |
|---|---|
| `id` | `int` |
| `state` | `TrackState` |
| `age_s` | `float` |
| `box` | float32 ndarray |
| `matched` | `bool` |

---

## OCR

```python
# on a loaded OCR model:
frame = model.predict(rgb_array, ocr=Ocr.AUTO)   # or ocr=True; Ocr.OFF/ON/HORIZONTAL/VERTICAL
doc = frame.document                              # a typed Document (None if OCR didn't run)
print(doc.text)                                   # horizontal reading
for v in doc.vertical_text:                       # vertical columns (e.g. a top-to-bottom ID)
    print(v.text)
for block in doc.blocks:
    for line in block.lines:
        print(line.text, [w.char for w in line.words])
```

OCR inputs must be decoded `(H,W,3)` uint8 RGB arrays.

---

## Depth & 3D

```python
frame  = model.predict("scene.jpg", tasks=lynx.Task.BOX | lynx.Task.DEPTH)
dmap   = frame.depth_map           # HxW ndarray or None
metric = frame.depth_is_metric     # bool
vis    = lynx.depth_to_u8(frame)   # (H,W,3) uint8 RGB

# 3D back-projection (needs pinhole intrinsics, in pixels):
intr = lynx.Intrinsics(fx=900.0, fy=900.0, cx=640.0, cy=360.0)
for det in frame.detections:
    p = det.position_3d(intr)      # Point3D(x, y, z) or None
    b = det.box_3d(intr)           # Box3D(center, width, height) or None
```

---

## Confidence & tasks

`open()`/`predict()` default to every declared head at the model's calibrated
balanced operating point. Override per call:

```python
model.predict(img, conf=lynx.ConfMode.MAX_PRECISION)   # MAX_RECALL / BALANCED / MAX_PRECISION
model.predict(img, conf=0.5)                            # raw float threshold
model.predict(img, tasks=lynx.Task.BOX | lynx.Task.SEGMENTATION, max_det=100)
```

`conf=` accepts:

| Accepted value | Notes |
|---|---|
| `None` | open-time default |
| a `ConfMode` | |
| a `Conf` selector | `Conf.balanced()`, `Conf.max_recall()`, `Conf.max_precision()`, `Conf.value(t)` |
| a bare float | |

---

## Enums

`Task` (IntFlag) members:

| Member | Value |
|---|---|
| `BOX` | `1` |
| `OBB` | `2` |
| `SEGMENTATION` | `4` |
| `DEPTH` | `8` |
| `POSE` | `16` |
| `CLASSIFICATION` | `32` |
| `REID` | `64` |
| `TEXT` | `128` |
| `Task(0)` | all declared heads |

Other enums:

| Enum | Members |
|---|---|
| `ConfMode` | `BALANCED`, `MAX_RECALL`, `MAX_PRECISION` |
| `Nms` | `AUTO`, `ON`, `OFF` |
| `Provider` | `CPU`, `CUDA`, `TENSORRT`, `COREML` |
| `TrackState` | `NEW`, `TENTATIVE`, `CONFIRMED`, `LOST` |
| `SizeVerdict` | `OK`, `TOO_SMALL`, `TOO_LARGE`, `NO_BAND`, `NO_SCALE` |
| `Size` | `AUTO`, `PICO`, `NANO`, `MEDIUM`, `LARGE` |
| `Goal` | `BALANCED`, `LATENCY`, `THROUGHPUT` |
| `LicenseStatus` | `VALID`, `EXPIRED`, `UNKNOWN` |
| `Attr` | `LOCATION_X`, `LOCATION_Y`, `ANGLE`, `SPEED`, `CONFIDENCE` (for `Tracker.value`) |
| `Op` | `LATEST`, `DELTA`, `RATE`, `MEAN`, `MIN`, `MAX` (for `Tracker.value`) |
| `Unit` | `FRAMES`, `SECONDS` (for `Tracker.value`) |

**Value types:**

| Type | Fields |
|---|---|
| `License` | `status`, `expires_at`, `is_perpetual`, `is_paid` |
| `ModelSize` | `category: Size`, `num_params`, `disk_bytes` |
| `Intrinsics` | `fx,fy,cx,cy` |
| `Point3D` | `x,y,z` |
| `Box3D` | `center,width,height` |

---

## Camera & video I/O

```python
cam = lynx.camera_open(0)                       # webcam
writer = lynx.video_writer("out.avi", 1280, 720, fps=30.0)
with cam, writer:
    for _ in range(300):
        rgb = cam.read()                        # (H,W,3) uint8 RGB
        frame = model.predict(rgb)
        writer.write(frame.plot(image=rgb))
    writer.finish()
```

`Camera`:

| Member | Notes |
|---|---|
| `read()` | |
| `actual_format` | property → `(w,h,fps)` |
| `close()` | |

`VideoWriter`:

| Member | Notes |
|---|---|
| `write(frame)` | |
| `frames` | property |
| `finish()` | |
| `close()` | |

---

## CLI

```bash
lynx info <slug>             # version, capabilities, classes, license, providers
lynx predict <slug> <image>  # run one image, print detections (alias: lynx detect)
lynx providers               # execution providers on this host
lynx --version               # SDK version
```

I/O flags:

| Flag | Value |
|---|---|
| `--model` / positional | slug |
| `--source` / `--input` / positional | image |
| `--license` | else `$LYNX_API_KEY` |

---
