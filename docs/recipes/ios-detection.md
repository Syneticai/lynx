# Recipe — iOS object detection (Swift)

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/ios.md`](../install/ios.md). API: [`api/swift.md`](../api/swift.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: load a model, run detection on an image, get boxes + labels + scores. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

## The whole thing

`Lynx.load` and `predict` are synchronous and throw; the first load downloads the model, so run them **off the main thread**. The model takes an image **path** or raw **RGB bytes**; a helper to convert a `UIImage` is included.

```swift
import Lynx
import UIKit

struct Box { let label: String; let score: Float; let rect: CGRect }

/// Load once, reuse. Loading downloads the model on first call.
final class Detector {
    private let model: Model
    init() throws { self.model = try Lynx.load("lynx-basic") }

    /// Run detection on a UIImage. Returns [label, score, pixel rect].
    func detect(_ image: UIImage, minConfidence: Float = 0.4) throws -> [Box] {
        guard let (rgb, w, h) = image.lynxRGBBytes() else {
            throw NSError(domain: "app", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not read image pixels"])
        }
        let frame = try model.predict(pixels: rgb, width: w, height: h, conf: .value(minConfidence))
        return frame.detections.map { d in
            Box(label: d.className ?? "class \(d.classId)",
                score: d.confidence,
                rect: CGRect(x: CGFloat(d.box[0]), y: CGFloat(d.box[1]),
                             width: CGFloat(d.box[2] - d.box[0]),
                             height: CGFloat(d.box[3] - d.box[1])))
        }
    }
}

extension UIImage {
    /// Decode to tightly-packed RGB bytes (width*height*3, row-major) — what predict(pixels:) expects.
    func lynxRGBBytes() -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = self.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i*3+0] = rgba[i*4+0]; rgb[i*3+1] = rgba[i*4+1]; rgb[i*3+2] = rgba[i*4+2]
        }
        return (rgb, w, h)
    }
}
```

## Calling it (off the main thread, update UI on main)

```swift
// hold the detector for the app's lifetime; build it once.
let detector = try Detector()        // do this in a Task / background queue (it downloads)

Task.detached {
    do {
        let boxes = try detector.detect(uiImage)
        await MainActor.run {
            for b in boxes { print(b.label, b.score, b.rect) }   // draw overlays here
        }
    } catch let e as LynxError {
        print("lynx error:", e.category, e.message)
    }
}
```

## If you have a file instead of a UIImage

```swift
let frame = try model.predict(path: "/path/to/image.jpg", conf: .value(0.4))
for d in frame.detections { print(d.className ?? "?", d.confidence, d.box) }
```

## Notes

- `box` is `[x1, y1, x2, y2]` in the **input image's** pixels (top-left origin).
- `conf:` — `.value(0.4)` is a raw threshold; use `.balanced()` / `.maxPrecision()` / `.maxRecall()` for the model's calibrated points, or omit for its default.
- Detection only needs the box head, which every model has. For pose/segmentation/depth on the same model, see the corresponding recipe — they're realized on the same `Frame` (`try frame.detections.run([.pose, .segmentation])`, then read `d.keypoints` / `d.mask`; `frame.depth` for depth).
- Reuse one `Detector` (one loaded `Model`) across calls; don't reload per image.
