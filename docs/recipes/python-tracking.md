# Recipe — Python object tracking

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: run detection across a video/frame sequence and follow each object with a **stable id** as it moves frame to frame. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

Tracking is stateful: instead of `model.predict` (one independent image), you drive a **stream**. `model.track(source)` is the sugar — it opens a tracker, feeds it each image from your iterable `source`, and **yields one `Frame` per image** with tracker ids populated. Each `Detection` then carries `d.tracker_id` (a stable int, `0` = untracked), `d.track_state` (a `TrackState`), and `d.track_age` (seconds since the track was first seen). Class **name** is resolved through `model.classes` — there's no `Detection.class_name`.

`source` is any iterable of images, where each image is a path **str** or a `(H, W, 3)` uint8 RGB numpy array — exactly what `predict` accepts. Below the source is a sorted folder of frames (`frame_0001.jpg`, …); swap in a video decoder (see Notes) without changing the tracking loop.

```python
import glob
import lynx
from lynx.errors import LynxError, ModelNotFound


def track_sequence(frames_glob="frames/*.jpg", min_confidence=0.4):
    """Track objects across a frame sequence with lynx-basic (keyless).

    Prints, per frame, each object's stable tracker id + class name + box.
    """
    paths = sorted(glob.glob(frames_glob))
    if not paths:
        print(f"No frames matched {frames_glob!r}.")
        return

    # Open once. First call downloads + verifies + caches the model.
    with lynx.open("lynx-basic") as model:
        # model.track(source) yields one Frame per image, tracker ids populated.
        # `source` here is the list of frame paths; conf is a bare float threshold.
        for frame_no, frame in enumerate(model.track(paths)):
            live = [d for d in frame.detections if d.confidence >= min_confidence]
            print(f"frame {frame_no:04d}: {len(live)} tracked object(s)")
            for d in live:
                if d.tracker_id == 0:
                    continue                              # not yet assigned an id
                name = model.classes(d.class_id).name     # e.g. "PERSON"
                x1, y1, x2, y2 = d.box                     # [x1, y1, x2, y2] pixels
                print(f"    id={d.tracker_id:<4} {name:16} "
                      f"{d.track_state.name:9} age={d.track_age:5.1f}s  "
                      f"box=({x1:.0f}, {y1:.0f}, {x2:.0f}, {y2:.0f})")


if __name__ == "__main__":
    import sys
    pattern = sys.argv[1] if len(sys.argv) > 1 else "frames/*.jpg"
    try:
        track_sequence(pattern)
    except ModelNotFound as e:
        print("model not found (bad slug/version):", e.message)
    except LynxError as e:
        print(f"lynx error [{e.code}]: {e.message}")
```

Because the tracker id is stable, you can follow **one** object across the run by keying on `d.tracker_id` — e.g. accumulate a per-id trail of box centers:

```python
from collections import defaultdict

trails = defaultdict(list)
with lynx.open("lynx-basic") as model:
    for frame in model.track(paths):
        for d in frame.detections:
            if d.tracker_id:                              # skip 0 (untracked)
                x1, y1, x2, y2 = d.box
                trails[d.tracker_id].append(((x1 + x2) / 2, (y1 + y2) / 2))

for tid, points in trails.items():
    print(f"track {tid}: seen in {len(points)} frame(s)")
```

## Driving the tracker yourself

`model.track` is a thin loop over a `Tracker`. Open one directly when you pull frames from a live source (a camera, a socket) rather than a ready-made iterable — call `update(image)` per frame:

```python
with lynx.open("lynx-basic") as model:
    with model.tracker() as tracker:               # a lynx.Tracker; context-managed
        while True:
            image = grab_next_frame()              # your capture -> path or (H,W,3) uint8 RGB
            if image is None:
                break
            frame = tracker.update(image)          # -> Frame, tracker ids populated
            for d in frame.detections:
                if d.tracker_id:
                    print(d.tracker_id, model.classes(d.class_id).name, d.box)
```

A `lynx.Camera` source drops straight in — `cam.read()` returns the `(H, W, 3)` uint8 RGB array `update` wants:

```python
with lynx.open("lynx-basic") as model, \
     lynx.camera_open(0) as cam, \
     model.tracker() as tracker:
    for _ in range(300):                           # ~first 300 frames
        frame = tracker.update(cam.read())
        print(len(frame.detections), "objects")
```

## The active-track view

Every `Frame` also exposes `frame.tracks` — the **full set of active tracks** this frame, including ones the detector missed here (a track can stay alive briefly while `LOST`). Each is a `lynx.Track` with `.id`, `.state`, `.age_s`, `.box`, and `.matched` (whether it was matched to a detection this frame):

```python
for frame in model.track(paths):
    for t in frame.tracks:
        mark = "seen" if t.matched else "coasting"     # unmatched = predicted-through
        print(f"  track {t.id} {t.state.name:9} {mark} age={t.age_s:.1f}s")
```

`frame.index_of(track_id)` maps a track id back to its detection row index in this frame (`-1` if that track has no detection here) — handy to jump from a `Track` to the matching `Detection`:

```python
i = frame.index_of(t.id)
if i >= 0:
    d = frame.detections[i]
    print("matched detection:", model.classes(d.class_id).name, d.confidence)
```

## Notes

- **Ids and lifecycle.** `d.tracker_id` is a stable positive int for the life of a track; `0` means "not tracked" (an object the tracker hasn't confirmed into a track yet). `d.track_state` is a `lynx.TrackState`: `NEW` (just created) → `TENTATIVE` (unconfirmed) → `CONFIRMED` (stable) → `LOST` (missed recent frames, awaiting re-match or expiry). A `LOST` track that isn't re-matched expires and its id is retired; a genuinely new object gets a fresh id.
- **`track_age` is seconds**, not frames — time since the track was first seen (`0` when untracked). `Track.age_s` on the `frame.tracks` view is the same clock.
- **Vectorized columns.** Like detection, `frame.detections` exposes parallel numpy columns for tracking too: `frame.detections.tracker_id` `(N,)`, `frame.detections.track_state` `(N,)`, `frame.detections.track_age` `(N,)` — alongside `.boxes` / `.confidence` / `.class_id`. Use them to filter without a Python loop, e.g. `dets[dets.tracker_id != 0]`.
- **Open once, stream once.** One `Tracker` = one temporal stream; don't reopen it per frame or ids reset. `model.track` and `model.tracker` build the stream for you. Run the first `open` off the UI thread (it downloads the model).
- **From a video file.** Replace the frame-glob source with any generator of RGB arrays. With OpenCV (`pip install opencv-python`), remembering LYNX wants **RGB**:
  ```python
  import cv2

  def video_frames(path):
      cap = cv2.VideoCapture(path)
      try:
          while True:
              ok, bgr = cap.read()
              if not ok:
                  break
              yield cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)   # BGR -> RGB (H,W,3) uint8
      finally:
          cap.release()

  with lynx.open("lynx-basic") as model:
      for frame in model.track(video_frames("clip.mp4")):
          ...
  ```
- **Same model, more heads.** `lynx-basic` also ships segmentation, pose, and depth; tracking composes with them (open with `tasks=`, or realize ROI heads per frame with `frame.detections.run([...])`) — see [`api/python.md`](../api/python.md).
