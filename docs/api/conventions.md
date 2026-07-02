# Conventions

> For LYNX SDK **1.0**. These rules hold across every binding; the per-language pages assume them and do not repeat them.

## Errors

Fallible calls **throw** in every binding (Swift `throws`, Kotlin/Java exceptions, Python exceptions). You never check a return code by hand. The thrown error carries:

- a **category** (the stable, switchable identity) and
- a **message** (human-readable detail).

Switch on the category, never on the message string. Categories (and their underlying codes):

| category | code | meaning |
|---|---|---|
| `invalidArg` | -15 | a bad argument (null frame, empty path, out-of-range value) |
| `format` | -2 | the model bytes aren't a valid `.lnx` (wrong file, truncated) |
| `unsupportedTask` | -12 | asked a model for a head it doesn't have |
| `unknownClass` | -13 | named a per-class option that isn't in the model |
| `notFound` | -10 | generic "not found" |
| `modelNotFound` | -16 | the slug/version didn't resolve on the server |
| `decrypt` | -4 | generic decrypt failure |
| `decryptCert` | -17 | the signed cert failed to decrypt/verify |
| `expired` | -7 | generic expiry |
| `licenseExpired` | -18 | the model's license window has passed |
| `unavailable` | -8 | generic unavailable |
| `accUnavailable` | -19 | `require_acceleration` was set but no accelerator initialized |
| `failed` / `other` | -14 / — | unspecified failure |

Swift example:

```swift
do {
    let model = try Lynx.load("lynx-basic")
} catch let e as LynxError where e.category == .modelNotFound {
    // bad slug/version
} catch let e as LynxError where e.category == .licenseExpired {
    // renew
}
```

## Loading a model (`.lnx`)

You load a model **by slug**, not by file path. `Lynx.load("lynx-basic")` resolves the slug through the signed registry, downloads + verifies + caches the `.lnx` on first use, and returns a ready model. The `.lnx` is encrypted and Ed25519-signed; the SDK handles decryption/verification — **you do nothing with keys for the bundled public models.**

- **Public models** (e.g. `lynx-basic`) are keyless: no API key needed; the SDK mints a per-device trial automatically.
- **Licensed/private models** need a per-account key set **once** at startup: `Lynx.setApiKey("lnx_…")` (Swift) before the first `load`. The key is the download credential; it is not passed per call.
- First load does a network fetch + decrypt (a few seconds, cached after). Subsequent loads are local.

Pin a specific build with the `version:` parameter; omit it for the current production version.

## Picking heads (tasks)

A model can expose several heads. `load(tasks: .none)` opens **every** head the model declares; pass a narrowed `Task` to open only some (lower memory/latency). At call time, `predict` runs the frame-global heads; ROI heads (pose, segmentation, oriented box, text, reid) are realized on demand — see each recipe. Check what a loaded model actually supports with `model.capabilities` before requesting a head, or you'll get `unsupportedTask`.

## Arrays

Collections are native in each binding — Swift arrays, Kotlin/Java `List`, Python `list`. You iterate them directly (`for d in frame.detections`); there are no manual pointer/count pairs at the binding level.

## Coordinates & units

- Bounding boxes are `[x1, y1, x2, y2]` in **input-frame pixels** (top-left origin).
- Oriented boxes are `[cx, cy, w, h, angle]`, angle in **radians**.
- Pose keypoints are `(x, y, confidence)` in input-frame pixels.
- Depth is a dense `height × width` row-major array; `isMetric` says whether values are meters (true) or relative (false).

## Lifetime & threading

Models and frames free themselves when they go out of scope (ARC/GC) — no manual close. Run inference off the main thread. Call the process-global teardown (`Lynx.shutdown()`) once at exit, after every model is released.
