# LYNX SDK — Kotlin API Reference

Package `ai.synetic.lynx` — `import ai.synetic.lynx.*`. The JNI library
`lynx_jni` loads automatically on first use (must be on `java.library.path`).
Set the API key once before opening a model.

## Quickstart

```kotlin
import ai.synetic.lynx.*

Lynx.setApiKey(System.getenv("LYNX_API_KEY"))

Lynx.open("lynx-basic").use { model ->                 // AutoCloseable
    model.predict("image.jpg").use { frame ->
        for (d in frame.detections) {
            println("${d.className ?: d.classId} conf=${d.confidence} box=${d.box.toList()}")
        }
        val ids:  IntArray   = frame.detections.classId      // vectorized columns
        val conf: FloatArray = frame.detections.confidence
    }
}
```

## `object Lynx` — entry point

| Member | |
|---|---|
| `fun version(): String` | |
| `fun setApiKey(key: String)` | Download credential. |
| `fun providers(): List<Provider>` | Host providers (no model load). |
| `fun open(slug: String = "lynx-basic", tasks: Task = Task.NONE, conf: Conf? = null, size: Size? = null, goal: Goal? = null, version: String? = null, nms: Nms = Nms.AUTO): Model` | Open a model. `conf == null` → calibrated balanced operating point. |

Defaults are Kotlin-only (not `@JvmOverloads` — the `Task` value class mangles
the name). A JVM shutdown hook is registered on first `open`.

## `class Model : AutoCloseable`

**Properties:**

| Property | Type |
|---|---|
| `classes` | `ClassRegistry` |
| `version` | `String?` |
| `buildId` | `String?` |
| `capabilities` | `Task` |
| `nmsFree` | `Boolean` |
| `size` | `ModelSize` |
| `license` | `License` |
| `providers` | `List<Provider>` |

| Method | |
|---|---|
| `fun predict(image: String, conf: Conf? = null, maxDet: Int = 0, tasks: Task = Task.NONE, retain: Boolean = false, nms: Nms = Nms.AUTO): Frame` | From a file path. |
| `fun predict(image: ByteArray, width: Int, height: Int, …): Frame` | Raw RGB, HWC, `width*height*3`. |
| `fun predict(images: List<String>, …): List<Frame>` | Batch. |
| `fun prepare(batchSizes: IntArray)` | Build batch engines. |
| `fun tracker(window: Double = 0.0): Tracker` | Streaming tracker (`window` = seconds). |
| `override fun close()` | Idempotent. |

No `suspend`/coroutine APIs.

## `class Frame : AutoCloseable`

**Properties:**

| Property | Type | Notes |
|---|---|---|
| `detections` | `Detections` | lazy |
| `classifications` | `Classifications` | lazy |
| `depth` | `FloatArray?` | H*W row-major |
| `depthShape` | `IntArray?` | `[H,W,metric]` |
| `depthIsMetric` | `Boolean` | |

| Method | |
|---|---|
| `fun run(tasks: Task)` | Realize a frame-global head. |
| `fun indexOf(trackId: Int): Int` | Track id → detection index, or -1. |
| `fun submitFeedback(imagePath: String, correction: String)` | Active-learning feedback. |

## `class Detections : Iterable<Detection>`

**Columns:**

| Column | Type | Notes |
|---|---|---|
| `size` | | |
| `boxes` | `Array<FloatArray>` | N×4 |
| `orientedBoxes` | | N×5 |
| `classId` | `IntArray` | |
| `confidence` | `FloatArray` | |
| `trackerId` | `IntArray` | |
| `trackState` | `IntArray` | |
| `trackAge` | `FloatArray` | |
| `masks` | `List<FloatArray?>` | |
| `embeddings` | `List<FloatArray?>` | |
| `text` | `List<String>` | |

| Method | |
|---|---|
| `operator fun get(i): Detection` / `iterator()` | |
| `fun filter(predicate): Detections` | Sub-view over the same result. |
| `fun angleAt(kp: Keypoint): FloatArray` / `fun distance(a, b: Keypoint): FloatArray` | Per-row; NaN where undefined. |
| `fun run(tasks: Task)` | Realize ROI heads for these detections. |

## `class Detection`

**Properties:**

| Property | Type | Notes |
|---|---|---|
| `index` | | |
| `box` | `FloatArray` | 4 |
| `orientedBox` | | 5 |
| `classId` | | |
| `confidence` | | |
| `keypoints` | `FloatArray` | K*3 |
| `mask` | `FloatArray?` | |
| `embedding` | `FloatArray?` | |
| `text` | `String` | "" |
| `trackerId` | | |
| `trackState` | `TrackState` | |
| `trackAge` | | |
| `className` | `String?` | |

| Method | Notes |
|---|---|
| `fun angleAt(kp): Float` | |
| `fun distance(a, b): Float` | NaN where undefined |

## Classifications, classes, value types

| Type | Members |
|---|---|
| `Classifications` | `size` (0/1), `get(0): Classification`, `classId`, `confidence` |
| `data class Classification(classId: Int, confidence: Float)` | |
| `ClassRegistry : Iterable<LynxClass>` | `size`, `get(id)`, `get(name): LynxClass?` |
| `LynxClass` | `id`, `name`, `keypoints: List<Keypoint>`, `hasPose`, `keypoint(name): Keypoint` (throws `LynxException.NotFound`) |
| `Keypoint` | `classId`, `index`, `name` |
| `data class ModelSize(category: Size, numParams: Long, diskBytes: Long)` | |
| `data class License(status: LicenseStatus, expiresAt: Long, isPerpetual: Boolean, isPaid: Boolean)` | |

## `class Tracker : AutoCloseable`

From `model.tracker(window)`.

```kotlin
model.tracker(window = 2.0).use { t ->
    val frame = t.update("frame0.jpg")            // synchronous step
    frame.detections.forEach { println("${it.trackerId} ${it.trackState}") }
}
```

| Method | Notes |
|---|---|
| `fun update(image: String): Frame` | |
| `fun submit(image: String): Int` | async enqueue |
| `fun processNext(): Frame` | blocking dequeue+infer |

## Confidence & enums

`Conf.balanced()` / `maxRecall()` / `maxPrecision()` / `value(threshold: Float)`.

| Type | Members |
|---|---|
| `@JvmInline value class Task(bits: Int)` | `or`, `contains`; `NONE, BOX, OBB, SEGMENTATION, DEPTH, POSE, CLASSIFICATION, REID, TEXT` |
| `Size` | `AUTO, PICO, NANO, MEDIUM, LARGE` |
| `Goal` | `BALANCED, LATENCY, THROUGHPUT` |
| `Nms` | `AUTO, ON, OFF` |
| `Provider` | `CPU, CUDA, TENSORRT, COREML` |
| `TrackState` | `NEW, TENTATIVE, CONFIRMED, LOST` |
| `LicenseStatus` | `VALID, EXPIRED, UNKNOWN` |

## Errors

`sealed class LynxException(code: Int, message) : RuntimeException`. Subclasses:

| Subclass | Code | Subclass-of |
|---|---|---|
| `InvalidArg` | -15 | `LynxException` |
| `Format` | -2 | `LynxException` |
| `UnsupportedTask` | -12 | `LynxException` |
| `UnknownClass` | -13 | `LynxException` |
| `Failed` | -14 | `LynxException` |
| `NotFound` | -10 | `LynxException` |
| `ModelNotFound` | -16 | `NotFound` |
| `Decrypt` | -4 | `LynxException` |
| `DecryptCert` | -17 | `Decrypt` |
| `Expired` | -7 | `LynxException` |
| `LicenseExpired` | -18 | `Expired` |
| `Unavailable` | -8 | `LynxException` |
| `AccUnavailable` | -19 | `Unavailable` |
| `Other` | | `LynxException` |

```kotlin
try { Lynx.open("nope") }
catch (e: LynxException.NotFound) { /* incl. ModelNotFound */ }
catch (e: LynxException) { println("lynx ${e.code}: ${e.message}") }
```

## Notes

`Track`, `Attr`, `Op`, `TimeUnit` are defined but not yet wired into any public
method (reserved for a future temporal-measurement API). Camera/video I/O and
3D-from-depth are in the C/Python surface; see [c.md](c.md).
