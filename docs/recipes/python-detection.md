# Recipe — Python object detection

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: load a model, run detection on an image, get boxes + labels + scores. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

`lynx.open` and `model.predict` are synchronous and raise on failure; the first `open` downloads the model, so do it once and reuse the `Model`. `predict` takes an image **path** directly (or a `(H, W, 3)` uint8 RGB numpy array). A detection's class **name** is resolved through `model.classes` — there's no `Detection.class_name`.

```python
import lynx
from lynx.errors import LynxError, ModelNotFound

def detect(image_path, min_confidence=0.4):
    """Load lynx-basic (keyless), run detection, print each label + score + box."""
    # Open once. First call downloads + verifies + caches the model.
    with lynx.open("lynx-basic") as model:
        # conf is a bare float threshold; pass a path or an (H, W, 3) uint8 RGB array.
        frame = model.predict(image_path, conf=min_confidence)

        if len(frame.detections) == 0:
            print(f"No objects found in {image_path!r}.")
            return

        print(f"{len(frame.detections)} detection(s) in {image_path!r}:")
        for d in frame.detections:
            name = model.classes(d.class_id).name        # e.g. "PERSON"
            x1, y1, x2, y2 = d.box                        # [x1, y1, x2, y2] input pixels
            print(f"  {name:16} {d.confidence:.2f}  "
                  f"box=({x1:.0f}, {y1:.0f}, {x2:.0f}, {y2:.0f})")


if __name__ == "__main__":
    import sys
    image_path = sys.argv[1] if len(sys.argv) > 1 else "photo.jpg"
    try:
        detect(image_path)
    except ModelNotFound as e:
        print("model not found (bad slug/version):", e.message)
    except LynxError as e:
        print(f"lynx error [{e.code}]: {e.message}")
```

## Working with the vectorized columns

`frame.detections` also exposes parallel numpy columns — handy for filtering or plotting without a Python loop:

```python
dets = frame.detections
boxes  = dets.boxes          # (N, 4) float32, each [x1, y1, x2, y2]
scores = dets.confidence     # (N,) float32
ids    = dets.class_id       # (N,) int

# boolean-index to a sub-collection view, then iterate it:
people = dets[ids == model.classes["PERSON"]]
print(f"{len(people)} person(s)")
```

## Passing pixels instead of a path

If you already have the image decoded (e.g. from Pillow or a camera), hand `predict` the array directly — it must be C-contiguous `(H, W, 3)` uint8 **RGB**:

```python
import numpy as np
from PIL import Image                       # pip install pillow

rgb = np.asarray(Image.open("photo.jpg").convert("RGB"))
frame = model.predict(rgb, conf=0.4)
```

## Notes

- `box` is `[x1, y1, x2, y2]` in the **input image's** pixels (top-left origin).
- `conf=` accepts a bare `float` (raw threshold), a `ConfMode` (e.g. `lynx.ConfMode.MAX_PRECISION` for the model's calibrated point), a `Conf`, or `None` for the model's calibrated default.
- Detection only needs the box head, which every model has. For pose/segmentation/depth on the same model, open with those tasks (or realize them per-frame) and read `frame.detections.run([lynx.Task.POSE])` → `d.keypoints` / `d.mask`, and `frame.depth_map` / `d.depth` for depth — see [`api/python.md`](../api/python.md).
- Reuse one loaded `Model` across calls; don't reopen per image. Run the first `open` off the UI thread (it downloads).
