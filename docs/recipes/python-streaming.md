# Recipe — Python live camera / video streaming

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/python.md`](../install/python.md). API: [`api/python.md`](../api/python.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: open a webcam, run **tracked** detection on every frame in a loop, and print the detections (with stable track ids) per frame. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

Detection with `model.predict` is stateless — each frame is independent, track ids are always `0`. For a live source you want a **`Tracker`**: it carries state across frames so the same object keeps the same `id`. Get one from `model.tracker()` and feed it frames with `tracker.update(frame)`.

## The whole thing

`lynx.camera_open(0)` opens the default webcam through the C core (Media Foundation on Windows, V4L2 on Linux, AVFoundation on macOS). `cam.read()` returns one `(H, W, 3)` uint8 **RGB** ndarray — exactly what `tracker.update()` wants. Open the model **once** (the first `open` downloads + verifies + caches it), warm it up, then loop.

```python
import lynx

def stream(max_frames=600):
    """Open lynx-basic (keyless), track objects from the default webcam, print
    per-frame detections with stable track ids."""
    with lynx.open("lynx-basic") as model:
        # Build the size-1 engine up front so the first real frame doesn't stall
        # on cold-start engine compilation (see Notes -> warmup).
        model.prepare([1])

        with lynx.camera_open(0) as cam:          # 0 = default device, native format
            w, h, fps = cam.actual_format
            print(f"camera: {w}x{h} @ {fps:.3g} fps")

            # A Tracker keeps object identity across frames. window is the temporal
            # history (seconds) Tracker.value() reduces over; 0.0 = core default.
            with model.tracker(window=0.0) as tracker:
                for i in range(max_frames):
                    frame_rgb = cam.read()        # (H, W, 3) uint8 RGB; blocks for one frame
                    frame = tracker.update(frame_rgb)

                    dets = frame.detections
                    if len(dets) == 0:
                        continue

                    parts = []
                    for d in dets:
                        name = model.classes(d.class_id).name    # e.g. "PERSON"
                        tid = d.tracker_id                        # stable id (0 = untracked)
                        parts.append(f"{name}#{tid}:{d.confidence:.2f}")
                    print(f"frame {i:5d}  {len(dets):2d} obj  " + "  ".join(parts))


if __name__ == "__main__":
    stream()
```

`d.tracker_id` is the stable identity — the same physical object keeps the same id across frames while the `Tracker` sees it. `d.track_state` (`lynx.TrackState.NEW/TENTATIVE/CONFIRMED/LOST`) and `d.track_age` (seconds since first seen) round out the per-object track info; `frame.tracks` gives the full active-track snapshot (`Track.id`, `.state`, `.age_s`, `.box`, `.matched`) including tracks with no detection this frame.

## Iterating a source instead of a hand loop

`model.track(source, ...)` is sugar for the loop above: it builds a `Tracker` internally and yields one `Frame` per item of any iterable of frames (RGB arrays **or** image paths). Feed it the camera, a list of frames, or your own video-decode generator:

```python
def camera_frames(cam):
    while True:
        yield cam.read()                          # (H, W, 3) uint8 RGB

with lynx.open("lynx-basic") as model, lynx.camera_open(0) as cam:
    for frame in model.track(camera_frames(cam), window=0.0):
        print(len(frame.detections), "objects",
              [t.id for t in frame.tracks])
```

There is no built-in video-file decoder in the SDK — to stream a `.mp4`, decode it yourself (OpenCV / imageio / PyAV) and yield `(H, W, 3)` uint8 RGB arrays into `model.track(...)`, same as `camera_frames` above.

## Drop-frames-friendly: capture off the inference thread

`cam.read()` blocks for one frame, and `tracker.update()` blocks for the whole forward pass. Chaining them serially means a slow inference frame **backs up** the camera and you accumulate latency — the tracker falls further behind real time. The live-video fix is to run capture on its own thread that keeps only the **newest** frame (older un-consumed frames are dropped), so inference always works on the freshest pixels and slow frames drop instead of queueing.

```python
import threading
import lynx


class LatestFrame:
    """Single-slot frame buffer: capture thread overwrites, consumer takes the
    newest. Stale frames are dropped, never queued (bounded latency)."""
    def __init__(self):
        self._frame = None
        self._lock = threading.Lock()
        self._new = threading.Condition(self._lock)
        self._stop = False

    def put(self, frame):
        with self._lock:
            self._frame = frame                   # overwrite -> drops any un-taken frame
            self._new.notify()

    def get(self):
        with self._lock:
            while self._frame is None and not self._stop:
                self._new.wait()
            frame, self._frame = self._frame, None
            return frame

    def stop(self):
        with self._lock:
            self._stop = True
            self._new.notify()


def capture_loop(cam, buf):
    try:
        while not buf._stop:
            buf.put(cam.read())                   # keep only the freshest frame
    except Exception:
        buf.stop()


def stream(max_frames=600):
    with lynx.open("lynx-basic") as model:
        model.prepare([1])                        # warm up before the clock starts
        with lynx.camera_open(0) as cam:
            buf = LatestFrame()
            grabber = threading.Thread(
                target=capture_loop, args=(cam, buf), daemon=True)
            grabber.start()

            with model.tracker(window=0.0) as tracker:
                for i in range(max_frames):
                    frame_rgb = buf.get()         # newest available; older ones dropped
                    if frame_rgb is None:
                        break
                    frame = tracker.update(frame_rgb)

                    for d in frame.detections:
                        name = model.classes(d.class_id).name
                        print(f"frame {i:5d}  {name}#{d.tracker_id} {d.confidence:.2f}")

            buf.stop()
            grabber.join(timeout=1.0)


if __name__ == "__main__":
    stream()
```

The camera thread only ever holds one frame; whenever inference is busy, incoming frames overwrite each other and the SDK never sees the backlog. Latency stays bounded to roughly one inference pass regardless of how far behind the camera would otherwise fall.

### Overlapping capture with inference (submit / process_next)

If you'd rather hand frames to the SDK and let it overlap capture with the forward pass, `Tracker` also has a non-blocking `submit()` + `process_next()` pair: `submit(frame)` enqueues without blocking, `process_next()` blocks until the next result is ready.

```python
with model.tracker(window=0.0) as tracker:
    tracker.submit(cam.read())                    # prime the pipeline
    for i in range(max_frames):
        tracker.submit(cam.read())                # enqueue frame i+1 (non-blocking)
        frame = tracker.process_next()            # get result for frame i (blocks)
        print(i, len(frame.detections), "objects")
```

Keep `submit()` and `process_next()` balanced (submit one ahead, then one-in / one-out) so the internal queue doesn't grow unbounded — for a hard latency cap the single-slot `LatestFrame` pattern above is stricter.

## Notes

- **Warmup.** The first `predict`/`update` on a fresh model builds the native inference engine and is much slower than steady state. Call `model.prepare([1])` once at startup (size 1 is the cold-start warm-up bucket) so the first live frame runs at full speed. Do the `open` + `prepare` off your UI/event thread — `open` downloads on first use.
- **Throughput.** Steady-state frame rate is bounded by the forward pass, not by capture. On CPU that can be well under camera fps — the drop-frames pattern above is what keeps a live feed real-time (you process the newest frame and skip the rest). To use a GPU, call `lynx.set_workers(gpus=1)` **once** before `open` (see [`api/python.md`](../api/python.md)); check the active provider with `model.execution_provider`.
- **Track ids.** `d.tracker_id` is `0` for an untracked detection (e.g. a stateless `model.predict()` result); it's a stable non-zero id once the `Tracker` confirms the object. Use `d.track_state` / `d.track_age` (or the `frame.tracks` snapshot) to filter tentative vs. confirmed tracks.
- **Frames are RGB.** `cam.read()` returns `(H, W, 3)` uint8 **RGB** (top-left origin). Boxes from `d.box` are `[x1, y1, x2, y2]` in those same input pixels.
- **Cleanup.** `Camera`, `Tracker`, and the `Model` are context managers — the `with` blocks close the capture device, the stream, and the model handle even on Ctrl-C or an exception. If you record annotated output, add a `lynx.video_writer(path, w, h, fps)` and `writer.write(frame.plot(image=frame_rgb))` inside the loop (the SDK's `examples/record_depth.py` is the recorder pattern).
