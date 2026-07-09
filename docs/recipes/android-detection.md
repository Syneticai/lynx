# Recipe — Android object detection (Kotlin)

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/android.md`](../install/android.md). API: [`api/kotlin.md`](../api/kotlin.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: load a model, run detection on a `Bitmap`, get boxes + labels + scores. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

`Lynx.open` and `predict` are synchronous and throw; the first load downloads the model, so run them **off the main thread**. The on-device path takes raw **RGB bytes** (HWC, `width*height*3`) — convert your `Bitmap` and pass the bytes with `width`/`height`.

```kotlin
import ai.synetic.lynx.Lynx
import ai.synetic.lynx.Model
import ai.synetic.lynx.Conf
import ai.synetic.lynx.LynxException
import android.graphics.Bitmap

data class Box(val label: String, val score: Float, val left: Float, val top: Float, val right: Float, val bottom: Float)

/** Load once, reuse. Loading downloads the model on first call. */
class Detector {
    private val model: Model = Lynx.open("lynx-basic")   // keyless

    /** Run detection on a Bitmap. Returns [label, score, pixel box]. */
    fun detect(bitmap: Bitmap, minConfidence: Float = 0.4f): List<Box> {
        val (rgb, w, h) = bitmap.toLynxRgb()
        val frame = model.predict(rgb, w, h, conf = Conf.value(minConfidence))
        return frame.use { f ->
            f.detections.map { d ->
                val b = d.box                                  // [x1, y1, x2, y2]
                Box(
                    label = d.className ?: "class ${d.classId}",
                    score = d.confidence,
                    left = b[0], top = b[1], right = b[2], bottom = b[3],
                )
            }
        }
    }

    fun close() = model.close()
}

/** Decode a Bitmap to tightly-packed RGB bytes (width*height*3, HWC) — what predict(image, w, h) expects. */
fun Bitmap.toLynxRgb(): Triple<ByteArray, Int, Int> {
    val src = if (config == Bitmap.Config.ARGB_8888) this else copy(Bitmap.Config.ARGB_8888, false)
    val w = src.width; val h = src.height
    val pixels = IntArray(w * h)
    src.getPixels(pixels, 0, w, 0, 0, w, h)
    val rgb = ByteArray(w * h * 3)
    for (i in pixels.indices) {
        val p = pixels[i]
        rgb[i * 3]     = ((p shr 16) and 0xFF).toByte()   // R
        rgb[i * 3 + 1] = ((p shr 8) and 0xFF).toByte()    // G
        rgb[i * 3 + 2] = (p and 0xFF).toByte()            // B
    }
    return Triple(rgb, w, h)
}
```

## Calling it (off the main thread, update UI on main)

```kotlin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// hold the detector for the app's lifetime; build it once (it downloads on first load).
suspend fun runDetection(detector: Detector, bitmap: Bitmap) {
    try {
        val boxes = withContext(Dispatchers.Default) { detector.detect(bitmap) }
        // back on the caller's context — draw overlays / update UI here
        for (b in boxes) {
            Log.d("lynx", "${b.label} ${b.score} [${b.left}, ${b.top}, ${b.right}, ${b.bottom}]")
        }
    } catch (e: LynxException) {
        Log.e("lynx", "lynx error code=${e.code}: ${e.message}", e)
    }
}
```

> Build the `Detector` itself off the main thread too — its constructor calls `Lynx.open`, which downloads on first run. A plain background thread or `withContext(Dispatchers.Default) { Detector() }` both work.

## If you have an image file instead of a Bitmap

```kotlin
val frame = model.predict("/path/to/image.jpg", conf = Conf.value(0.4f))
frame.use { f -> for (d in f.detections) println("${d.className ?: d.classId} ${d.confidence} ${d.box.toList()}") }
```

## Notes

- `box` is `FloatArray [x1, y1, x2, y2]` in the **input image's** pixels (top-left origin).
- `conf:` — `Conf.value(0.4f)` is a raw threshold; use `Conf.balanced()` / `Conf.maxPrecision()` / `Conf.maxRecall()` for the model's calibrated points, or pass `null` for its default.
- Detection only needs the box head, which every model has. For pose/segmentation/depth on the same model, realize the extra heads on the same `Frame` — pass `tasks = Task.POSE or Task.SEGMENTATION, retain = true` to `predict` (or call `frame.detections.run(...)` after), then read `d.keypoints` (flat `K*3`) / `d.mask` (flat `P*2`); read `frame.depth` for depth. Confirm support first with `model.capabilities`.
- Reuse one `Detector` (one loaded `Model`) across calls; don't reload per image. Free it with `model.close()` (or a `use { }` block) when done.
