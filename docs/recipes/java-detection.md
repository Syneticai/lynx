# Recipe — Java object detection

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/java.md`](../install/java.md). API: [`api/java.md`](../api/java.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: load a model, run detection on an image, get boxes + labels + scores. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

`Lynx.open` and `predict` are synchronous and throw (unchecked `LynxException`); the first load downloads the model, so run them **off the main thread / event loop**. `predict` takes an image **path** (`String`) or raw **RGB bytes** (`byte[]`). The simplest path is a file path.

```java
import ai.golynx.lynx.Detection;
import ai.golynx.lynx.Frame;
import ai.golynx.lynx.Lynx;
import ai.golynx.lynx.LynxException;
import ai.golynx.lynx.Model;

public class Detect {
    public static void main(String[] args) {
        // Keyless: no setApiKey needed for lynx-basic. Loading downloads on first call.
        // try-with-resources frees the native model deterministically at block exit.
        try (Model model = Lynx.open("lynx-basic")) {

            try (Frame frame = model.predict("image.jpg")) {
                for (Detection d : frame.detections()) {
                    String label = (d.className() != null) ? d.className() : "class " + d.classId();
                    float[] box = d.box();   // [x1, y1, x2, y2] in input-frame pixels
                    System.out.printf("%-14s %.2f  [%.0f, %.0f, %.0f, %.0f]%n",
                        label, d.confidence(), box[0], box[1], box[2], box[3]);
                }
            }

        } catch (LynxException.ModelNotFound e) {
            System.err.println("no such model/version: " + e.getMessage());
        } catch (LynxException e) {
            System.err.println("lynx error " + e.code + ": " + e.getMessage());
        }
    }
}
```

`d.confidence()` **is** the detection score (there is no separate `score()` getter). `box()` is `[x1, y1, x2, y2]` in the **input image's** pixels (top-left origin).

## With a confidence threshold

Pass a `Conf` to filter weak detections. `Conf.value(0.4f)` is a raw threshold; `Conf.balanced()` / `Conf.maxPrecision()` / `Conf.maxRecall()` are the model's calibrated operating points; omit (or `null`) for the model's default.

```java
import ai.golynx.lynx.Conf;

try (Frame frame = model.predict("image.jpg", Conf.value(0.4f))) {
    for (Detection d : frame.detections()) {
        System.out.println(d.className() + " " + d.confidence());
    }
}
```

## If you have decoded pixels instead of a file

`predict(byte[], width, height)` takes tightly-packed **RGB** bytes (`width*height*3`, HWC row-major). Convert a `BufferedImage` like this:

```java
import ai.golynx.lynx.Frame;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.io.File;

/** Decode an image file to tightly-packed RGB bytes (width*height*3) — what predict(byte[],…) expects. */
static byte[] rgbBytes(BufferedImage img) {
    int w = img.getWidth(), h = img.getHeight();
    byte[] rgb = new byte[w * h * 3];
    int[] row = new int[w];
    for (int y = 0; y < h; y++) {
        img.getRGB(0, y, w, 1, row, 0, w);   // packed ARGB
        for (int x = 0; x < w; x++) {
            int p = row[x], i = (y * w + x) * 3;
            rgb[i]     = (byte) ((p >> 16) & 0xFF);  // R
            rgb[i + 1] = (byte) ((p >> 8)  & 0xFF);  // G
            rgb[i + 2] = (byte) (p & 0xFF);          // B
        }
    }
    return rgb;
}

// usage:
BufferedImage img = ImageIO.read(new File("image.jpg"));
try (Frame frame = model.predict(rgbBytes(img), img.getWidth(), img.getHeight())) {
    for (var d : frame.detections()) System.out.println(d.className() + " " + d.confidence());
}
```

## Vectorized columns (instead of per-detection)

`Detections` exposes parallel arrays — handy for bulk work:

```java
var dets = frame.detections();
int[]     ids   = dets.classId();      // class id per detection
float[]   confs = dets.confidence();   // score per detection
float[][] boxes = dets.boxes();        // each [x1,y1,x2,y2]
```

## Notes

- Reuse one loaded `Model` across calls — don't reload per image. Loading downloads/verifies; inference is local.
- Detection only needs the box head, which every model has. For pose/segmentation/depth on the same model, realize the ROI heads on the same `Frame`: `frame.detections().run(Task.POSE.or(Task.SEGMENTATION));` then read `d.keypoints()` / `d.mask()`; for depth use `frame.depthMap()` or per-object `d.depth()`.
- `LynxException` is unchecked (a `RuntimeException`) — no `throws` clause is required, but catch it to handle bad slugs, expired licenses, decrypt failures, etc. Catch the broad type or a specific subtype (`LynxException.ModelNotFound`, `LynxException.LicenseExpired`, …) — see [`api/java.md`](../api/java.md#errors).
- `Model` and `Frame` are `AutoCloseable`; `try (…)` frees the native handles deterministically. They also self-free on GC, so a missed `close()` won't leak.
