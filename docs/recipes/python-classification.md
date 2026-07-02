# Recipe — Python image classification

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: run a **whole-image** classification head — "what is this image?" (one top-1 label + score for the frame), not "where are the objects?".

> **Read this first — capability honesty.** Classification is a real head in the SDK (`lynx.Task.CLASSIFICATION`, read back through `frame.classifications`), but **neither catalog model has one**. `lynx-basic` declares detection, segmentation, pose, and depth; `lynx-ocr-fleet` declares detection only (see [`models/catalog.md`](../models/catalog.md)). So on today's keyless models `frame.classifications` is **empty** — there is no "every model has a classifier" fallback. The code below always checks `model.capabilities` first and tells you the truth, then shows the exact same code working against a classifier model you'd supply by slug.

## Check the capability first

`model.capabilities` is a `lynx.Task` bitmask of the heads the model actually declares. Test for the classification head with `in` before you trust `frame.classifications`.

```python
import lynx

with lynx.open("lynx-basic") as model:
    has_cls = lynx.Task.CLASSIFICATION in model.capabilities
    print("capabilities:", model.capabilities)          # e.g. Task.BOX|SEGMENTATION|POSE|DEPTH
    print("has a classification head:", has_cls)         # False for lynx-basic
```

For `lynx-basic` this prints `False` — it is a detector, so classification is genuinely unavailable. Don't pretend otherwise; branch on `has_cls`.

## The whole thing

`lynx.open` and `model.predict` are synchronous and raise on failure; the first `open` downloads + verifies + caches the model, so do it once and reuse the `Model`. `predict` takes an image **path** directly (or a `(H, W, 3)` uint8 RGB numpy array). Narrow the run to just the classification head with `tasks=lynx.Task.CLASSIFICATION`. The class **name** is resolved through `model.classes` — there's no `Classification.class_name`.

```python
import lynx
from lynx.errors import LynxError, ModelNotFound

def classify(slug, image_path):
    """Open a model (keyless), run the classification head, print top-1 label + score.

    Honest about capability: if the model has no classification head (lynx-basic
    does not), say so instead of faking a label.
    """
    with lynx.open(slug) as model:
        if lynx.Task.CLASSIFICATION not in model.capabilities:
            print(f"{slug!r} has no classification head "
                  f"(capabilities: {model.capabilities}). It is not a classifier.")
            return

        # tasks= narrows the run to just the classification head.
        frame = model.predict(image_path, tasks=lynx.Task.CLASSIFICATION)

        # frame.classifications is the whole-image top-1 collection: len 0 or 1.
        if len(frame.classifications) == 0:
            print(f"No classification produced for {image_path!r}.")
            return

        top = frame.classifications[0]                   # a lynx.Classification
        name = model.classes(top.class_id).name          # e.g. "GOLDEN_RETRIEVER"
        print(f"{name}  {top.confidence:.2%}")


if __name__ == "__main__":
    import sys
    slug = sys.argv[1] if len(sys.argv) > 1 else "lynx-basic"
    image_path = sys.argv[2] if len(sys.argv) > 2 else "photo.jpg"
    try:
        classify(slug, image_path)
    except ModelNotFound as e:
        print("model not found (bad slug/version):", e.message)
    except LynxError as e:
        print(f"lynx error [{e.code}]: {e.message}")
```

Run it against `lynx-basic` and it honestly reports "not a classifier"; run it against a classifier model's slug and the same code prints the label + score.

## Reading the result

`frame.classifications` is a small collection over the C surface's whole-image top-1:

```python
cls = frame.classifications

len(cls)              # 0 when the model emitted no classification, else 1
top = cls[0]          # lynx.Classification — raises IndexError if len == 0
top.class_id          # int class id, resolve the name via model.classes(top.class_id).name
top.confidence        # float in [0, 1]

# vectorized columns (parallel to the collection), for uniform handling:
cls.class_id          # (N,) intp   — N is 0 or 1
cls.confidence        # (N,) float32
```

There is **no** `top_k` / `top5` and **no** `probs` array — the surface exposes top-1 only (the collection shape is forward-compat for a future top-k, but today `len` is 0 or 1). Resolve the human-readable label with `model.classes(top.class_id).name`, the same `classes` enum detection uses.

## Passing pixels instead of a path

If the image is already decoded (Pillow, a camera, `lynx.camera_open`), hand `predict` the array directly — C-contiguous `(H, W, 3)` uint8 **RGB**:

```python
import numpy as np
from PIL import Image                       # pip install pillow

rgb = np.asarray(Image.open("photo.jpg").convert("RGB"))
frame = model.predict(rgb, tasks=lynx.Task.CLASSIFICATION)
```

## Notes

- **No universal classifier.** Only models that declare `lynx.Task.CLASSIFICATION` in `model.capabilities` return classifications; the catalog's `lynx-basic` and `lynx-ocr-fleet` do not. If you need whole-image categories, train/supply a classification model and load it by slug — see [`models/no-model.md`](../models/no-model.md). The old `classify()` / `results.probs.top1()` API is fiction; use `model.predict(..., tasks=lynx.Task.CLASSIFICATION)` → `frame.classifications`.
- **Detection ≠ classification.** To find *where* objects are, use the box head (every model has it) — see [`recipes/python-detection.md`](python-detection.md). Classification answers *what is this whole image*.
- `top.confidence` is a `float` in `[0, 1]`; gate on it (`if top.confidence < 0.6: mark_uncertain()`).
- One model, many heads: a classifier-plus-detector model can run both — open it and pass `tasks=lynx.Task.BOX | lynx.Task.CLASSIFICATION` (or omit `tasks` to run every head it declares), then read both `frame.detections` and `frame.classifications`.
- Reuse one loaded `Model` across calls; don't reopen per image. Run the first `open` off the UI thread (it downloads).
