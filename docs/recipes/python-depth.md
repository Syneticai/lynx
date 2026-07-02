# Recipe — Python depth

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: run detection **and** depth in one pass, read the dense depth map plus a per-object depth, and turn depth into a picture you can display. Model: `lynx-basic` (keyless — it ships a depth head alongside detection; see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

Depth is a **frame-global head**, so you ask for it with `tasks=`. Combine the box head with the depth head: `tasks=lynx.Task.BOX | lynx.Task.DEPTH`. The result carries a dense `frame.depth_map` (an `HxW` numpy array, or `None` if no depth was realized) and each detection gets a scalar `d.depth` sampled at the object. `frame.depth_is_metric` tells you whether those numbers are **meters** or an unitless **relative** scale. To show depth to a human, `lynx.depth_to_u8(frame)` renders it as a displayable `(H, W, 3)` uint8 RGB image (closer = brighter) at the original input resolution.

```python
import lynx
from lynx.errors import LynxError, ModelNotFound

def depth(image_path, min_confidence=0.4):
    """Load lynx-basic (keyless), run detection + depth, print per-object depth."""
    # Open once. First call downloads + verifies + caches the model.
    with lynx.open("lynx-basic") as model:
        # Ask for BOTH heads: the box head (detections) and the depth head.
        frame = model.predict(
            image_path,                              # path, or an (H, W, 3) uint8 RGB array
            tasks=lynx.Task.BOX | lynx.Task.DEPTH,
            conf=min_confidence,
        )

        # Dense frame-global depth grid — an (H, W) ndarray, or None if the model
        # realized no depth for this frame.
        dmap = frame.depth_map
        if dmap is None:
            print("No depth map for this frame.")
            return

        unit = "m" if frame.depth_is_metric else "rel"   # meters vs. relative scale
        print(f"depth map {dmap.shape[1]}x{dmap.shape[0]}, "
              f"{'metric (meters)' if frame.depth_is_metric else 'relative (unitless)'}")

        # Per-object depth: a scalar sampled at each detection's root.
        print(f"{len(frame.detections)} detection(s) in {image_path!r}:")
        for d in frame.detections:
            name = model.classes(d.class_id).name        # e.g. "PERSON"
            z = d.depth                                  # float; NaN if no depth here
            z_str = "n/a" if z != z else f"{z:.2f}{unit}"  # z != z tests for NaN
            print(f"  {name:16} {d.confidence:.2f}  depth={z_str}")

        # Render depth as a displayable image (closer objects brighter than far).
        depth_rgb = lynx.depth_to_u8(frame)              # (H, W, 3) uint8 RGB, or None
        if depth_rgb is not None:
            from PIL import Image                         # pip install pillow
            Image.fromarray(depth_rgb).save("depth.png")
            print("wrote depth.png")


if __name__ == "__main__":
    import sys
    image_path = sys.argv[1] if len(sys.argv) > 1 else "photo.jpg"
    try:
        depth(image_path)
    except ModelNotFound as e:
        print("model not found (bad slug/version):", e.message)
    except LynxError as e:
        print(f"lynx error [{e.code}]: {e.message}")
```

## The dense depth map

`frame.depth_map` is a plain `(H, W)` numpy array at the model's depth resolution — index it, threshold it, or feed it to your own code:

```python
dmap = frame.depth_map                       # (H, W) float ndarray, or None
if dmap is not None:
    print("nearest:", float(dmap.min()), "farthest:", float(dmap.max()))

    # Depth under a detection's box (input-pixel coords), averaged:
    d = frame.detections[0]
    x1, y1, x2, y2 = (int(v) for v in d.box)
    patch = dmap[y1:y2, x1:x2]
    if patch.size:
        print("mean depth over box:", float(patch.mean()))
```

## Rendering depth for display

`lynx.depth_to_u8(frame)` (equivalently `frame.depth_u8()`) normalizes and resizes depth to a viewable RGB image in the C core — no matplotlib needed. It returns `None` when the frame has no depth map:

```python
depth_rgb = lynx.depth_to_u8(frame)          # (H, W, 3) uint8 RGB at input resolution
if depth_rgb is not None:
    from PIL import Image
    Image.fromarray(depth_rgb).show()
```

## Confirm the model has a depth head

Not every model emits depth. Check `model.capabilities` (a `Task` bitmask) before asking for it:

```python
if lynx.Task.DEPTH in model.capabilities:
    frame = model.predict(image_path, tasks=lynx.Task.BOX | lynx.Task.DEPTH)
else:
    frame = model.predict(image_path, tasks=lynx.Task.BOX)   # detection only
```

## Notes

- **Metric vs. relative.** `frame.depth_is_metric` is `True` when `frame.depth_map` and `d.depth` are in **meters**; `False` when they're a unitless **relative** scale (near/far only, no absolute distance). Always branch on it before treating a number as meters.
- **`None` / `NaN` when there's no depth.** `frame.depth_map` and `lynx.depth_to_u8(frame)` return `None` if depth wasn't realized (e.g. you didn't pass `Task.DEPTH`, or the model has no depth head). Per-object `d.depth` returns `NaN` when no depth map was realized or the sampled point has no valid depth — test with `z != z` (NaN is never equal to itself).
- **Ask for depth explicitly.** Pass `tasks=lynx.Task.BOX | lynx.Task.DEPTH` to `predict` (opening with `tasks=0`, the default, opens every head the model declares — but being explicit keeps the pass lean). `d.depth` needs a box to sample at, so keep `Task.BOX` in the mix.
- **Depth resolution.** `frame.depth_map` is at the model's depth grid resolution; `lynx.depth_to_u8(frame)` resizes back to the original input resolution for display. `d.box` coordinates are in input pixels — scale if you index `depth_map` directly with them.
- **3D from depth (beta).** With camera intrinsics you can unproject an object to a camera-frame 3D point: `d.position_3d(lynx.Intrinsics(fx, fy, cx, cy))` → `Point3D` (or `None`), and `d.box_3d(...)` → `Box3D`. Units follow the depth map (meters when `depth_is_metric`).
- Reuse one loaded `Model` across calls; don't reopen per image. Run the first `open` off the UI thread (it downloads).
