# Model catalog

> For LYNX SDK **1.0**. **Single source of truth for model facts** — recipes and the `lynx_find_model` tool read from here. Load any model by its slug: `Lynx.load("<slug>")` (Swift) / `lynx.open("<slug>")` (Python) / `Lynx.load("<slug>")` (Kotlin/Java) / `lynx_open("<slug>", …)` (C).

Two models are available. Both are **keyless** (no API key — the SDK mints a per-device trial on first load), **production version 2.0**, and ship for **linux-x64 (ONNX), ios-arm64 (CoreML), android-arm64-v8a (TFLite)**, input **640×640**.

| slug | task | classes | heads | use it for |
|---|---|---|---|---|
| `lynx-basic` | general object detection | 80 (COCO 2017: person, bicycle, car, … toothbrush) | detection, segmentation, pose (keypoints), depth | "detect / segment / find objects / poses / depth" on everyday scenes |
| `lynx-ocr-fleet` | text / OCR (character detection) | 67 character classes — `0`–`9`, `A`–`Z`, `a`–`z`, and `-` `/` `.` `(` `)` | detection (one detection per character) | reading short text / IDs / codes off an image |

> Class 0 (`qr`, a reserved anti-tamper channel) is hidden by the SDK — `model.classes` and detection class ids are the public set above (80 for basic, 67 for ocr-fleet).

## How to choose

- **Detect everyday objects** → `lynx-basic`. Detection uses the box head every model has; this model also exposes **segmentation, pose, depth** on the same `Frame` (realize per-detection ROI heads, or read `frame.depth`). Confirm at runtime with `model.capabilities`.
- **Read text / characters / a code or ID** → `lynx-ocr-fleet`. It detects individual characters as boxes; you order them left-to-right and read each detection's class name (the class name *is* the character). See the OCR recipe.
- **A class not in COCO-80, or oriented/rotated objects, or any task neither model covers** → no off-the-shelf fit: go to [`no-model.md`](no-model.md). That's a real path (synthetic data → trained `.lnx` → same API), not a dead end.

## Loading specifics

- Both are keyless: `Lynx.load("lynx-basic")` / `lynx.open("lynx-ocr-fleet")` just works — no `setApiKey`.
- First load downloads + verifies + caches (a few seconds); subsequent loads are local. Run the first load off the main thread.
- Pin a build with `version:`/`version=` (e.g. `"2.0"`); omit for the current production version.
