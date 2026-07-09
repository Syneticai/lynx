# lynx SDK — agent integration docs

> For LYNX SDK **1.0**. Confirm at runtime with `Lynx.version()` (Swift) / `lynx.version()` (Python) / `Lynx.version()` (Kotlin/Java) / `lynx_version()` (C).

lynx is an on-device computer-vision SDK: you load a small signed model (`.lnx`) and run inference locally — no server round-trip, no GPU required. One model can expose several heads (detection, oriented boxes, segmentation, 17-keypoint pose, depth, tracking, OCR); you pick which to run per call. Bindings ship for **Swift (iOS/macOS), Kotlin (Android), Java (JVM), Python, and C** (the core every other binding wraps).

These docs are written to be **acted on directly** — every public symbol, its parameters, and a full copy-paste-runnable example per task. If a fact you need isn't here, that's a doc bug; use `lynx_search_docs`.

> **Keys — read this before the API refs.** The `api/` references show the general flow `set API key → open(slug)`. The two models in this catalog (`lynx-basic`, `lynx-ocr-fleet`) are **keyless**: the SDK mints a per-device trial on first load, so you **skip the key step entirely**. Recipes here are written keyless. You only set a key for your own licensed/custom models — see [`models/catalog.md`](models/catalog.md).
>
> **Source of truth.** The `api/` pages are vendored verbatim from the LYNX-SDK repo (the binding source) — never edited here. Install, recipes, and the model catalog are golynx-specific and live only here.

## Map

- [`support.md`](support.md) — **Installation & system requirements**: choose your binding + supported platforms, language versions, and acceleration (one page; also served at `/install`).
- **install/** — add the SDK to a project.
  - [`install/ios.md`](install/ios.md) — Swift Package / XCFramework.
  - [`install/android.md`](install/android.md) — Gradle / AAR.
  - [`install/java.md`](install/java.md) — Maven / Gradle (JVM), native loader.
  - [`install/python.md`](install/python.md) — `pip install`, platform wheels.
  - [`install/c.md`](install/c.md) — header + library, compile/link flags.
- **api/** — the exact public surface per binding (vendored from LYNX-SDK).
  - [`api/conventions.md`](api/conventions.md) — **read first.** Errors, arrays, the `.lnx` format, threading. Stated once here; the per-language pages don't repeat it. (C is the one exception: it returns error codes, not exceptions — see `api/c.md`.)
  - [`api/swift.md`](api/swift.md) — every Swift type, function, parameter, return.
  - [`api/kotlin.md`](api/kotlin.md) — Kotlin (Android).
  - [`api/java.md`](api/java.md) — Java (JVM).
  - [`api/python.md`](api/python.md) — Python.
  - [`api/c.md`](api/c.md) — C (the error-code authority).
- **recipes/** — complete end-to-end working integrations, one per `<platform>-<task>`.
  - [`recipes/ios-detection.md`](recipes/ios-detection.md) — Swift, object detection.
  - [`recipes/android-detection.md`](recipes/android-detection.md) — Kotlin, object detection.
  - [`recipes/java-detection.md`](recipes/java-detection.md) — Java, object detection.
  - [`recipes/python-detection.md`](recipes/python-detection.md) — Python, object detection.
  - [`recipes/c-detection.md`](recipes/c-detection.md) — C, object detection.
  - [`recipes/python-ocr.md`](recipes/python-ocr.md) — Python, reading text/characters (`lynx-ocr-fleet`).
- **models/** — which model to load.
  - [`models/catalog.md`](models/catalog.md) — the single source of model facts.
  - [`models/no-model.md`](models/no-model.md) — what to do when no pretrained model fits the task.
- [`privacy.md`](privacy.md) — **telemetry & privacy**: what the SDK sends, and how to turn it off (`LYNX_TELEMETRY=0` / `set_telemetry_enabled(false)`).

## The one-call path

To integrate "use lynx in my `<platform>` app to `<task>`": read the matching `recipes/<platform>-<task>.md`. It contains install + load + run + parse, complete. Reach into `api/<language>.md` only for a signature the recipe references.

## JavaScript / React Native / Flutter

**There is no JS, TypeScript, React Native, or Flutter binding.** The SDK ships exactly five bindings — **Swift, Kotlin, Java, Python, C** — and inference runs in the native core, not in JS. Two honest paths to use lynx from a cross-platform JS app:

1. **Native module bridge (on-device).** Write a thin native module that calls the platform SDK directly and returns detections as JSON to JS:
   - iOS: the Swift package (`Lynx.open(...)` → `model.predict(pixels:width:height:)`) — see [`install/ios.md`](install/ios.md) + [`api/swift.md`](api/swift.md).
   - Android: the Kotlin AAR (`Lynx.open(...)` → `model.predict(image: ByteArray, width, height, …)`) — see [`install/android.md`](install/android.md) + [`api/kotlin.md`](api/kotlin.md).
   - Marshal each camera frame's pixel buffer across the RN/Flutter bridge into the native `predict` call; return `[{box, classId, confidence}]` to JS. This is real on-device inference (CoreML / NNAPI), just wrapped by your own module — there is no prebuilt one.
2. **Server-side (fastest to stand up, not on-device).** Run the Python SDK behind an HTTP endpoint and have the JS app POST frames and render the returned detections. See [`install/python.md`](install/python.md) + [`recipes/python-detection.md`](recipes/python-detection.md).

Pick (1) for offline / low-latency / privacy; pick (2) to get a working demo in an afternoon.
