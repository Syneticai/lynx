# LYNX SDK — Swift API Reference

`import Lynx`. Swift Package Manager, swift-tools-version 5.9; platforms iOS 15+,
macCatalyst 15+, macOS 12+.

```swift
.package(url: "<repo-url>", from: "<version>")
// target dependency: .product(name: "Lynx", package: "Lynx")
```

> **Packaging prerequisite:** the binary target `LynxCore.xcframework` (the
> prebuilt obfuscated core + ONNX Runtime) must be present next to `Package.swift`
> (or the binaryTarget pointed at the released URL+checksum). Headers resolve
> without it, but linking fails until it's staged.

## Quickstart

```swift
import Lynx

try Lynx.setApiKey("YOUR_ACCOUNT_KEY")

let model = try Lynx.open("lynx-basic")          // defaults: all heads, no conf override
let frame = try model.predict(path: "image.jpg")

for d in frame.detections {
    let name = d.className ?? "class \(d.classId)"
    print(name, d.confidence, d.box)             // box = [x1, y1, x2, y2]
}

// vectorized columns
let ids   = frame.detections.classId
let confs = frame.detections.confidence

Lynx.shutdown()                                  // once, after all Model/Frame refs drop
```

Raw pixels (HWC RGB, `width*height*3` bytes):
```swift
let frame = try model.predict(pixels: rgbBytes, width: 640, height: 480)
```

## `enum Lynx` — entry point (namespace; all static)

| Member | |
|---|---|
| `static func version() -> String` | |
| `static func setApiKey(_ key: String) throws` | Download credential. |
| `static func providers() -> [Provider]` | Host providers (no model load). |
| `static func setFeedbackEnabled(_ enabled: Bool)` | |
| `static func open(_ slug: String = "lynx-basic", tasks: Task = .none, conf: Conf? = nil, size: ModelSizeCategory? = nil, goal: Goal? = nil, version: String? = nil) throws -> Model` | Open a model. |
| `static func shutdown()` | Release process-global state at teardown. |

## `final class Model`

Obtained from `Lynx.open`. Freed on `deinit`.

**Properties:**

| Property | Type |
|---|---|
| `classes` | `ClassRegistry` |
| `version` | `String?` |
| `buildId` | `String?` |
| `capabilities` | `Task` |
| `size` | `ModelSize` |
| `license` | `License` |
| `providers` | `[Provider]` |

| Method | |
|---|---|
| `func predict(path: String, conf: Conf? = nil, maxDet: Int32 = 0, tasks: Task = .none, retain: Bool = false) throws -> Frame` | From a file. |
| `func predict(pixels: [UInt8], width: Int, height: Int, conf: Conf? = nil, maxDet: Int32 = 0, tasks: Task = .none, retain: Bool = false) throws -> Frame` | Raw RGB. |
| `func prepare(batchSizes: [Int32]) throws` | Build batch engines. |

## `final class Frame`

**Properties:**

| Property | Type | Notes |
|---|---|---|
| `detections` | `Detections` | lazy |
| `classification` | `Classification?` | |
| `depth` | `Depth?` | |
| `opticalFlow` | `Flow?` | |

| Method | |
|---|---|
| `func run(_ tasks: Task) throws` | Realize a frame-global head (e.g. `.depth`) — needs `retain: true`. |
| `func index(ofTrack id: Int) -> Int` | Track id → detection index this frame, or -1. |

## `Detections: Sequence` & `struct Detection`

**`Detections`** — members:

| Member | Signature | Notes |
|---|---|---|
| `count` | | |
| `subscript(i)` | `-> Detection` | |
| iteration | | `Sequence` |
| `run` | `func run(_ tasks: Task) throws` | Realize ROI heads for all. |

**`Detections`** — columns:

| Column | Type |
|---|---|
| `classId` | `[Int]` |
| `confidence` | `[Float]` |
| `boxes` | `[[Float]]` |
| `trackerId` | `[Int]` |

**`Detection`** (scalar view):

| Member | Signature |
|---|---|
| `index` | |
| `classId` | |
| `confidence` | |
| `className` | `String?` |
| `box` | `[Float]` |
| `orientedBox` | `[Float]?` |
| `keypoints` | `[(x,y,confidence)]` |
| `mask` | `[(x,y)]?` |
| `embedding` | `[Float]?` |
| `text` | `String?` |
| `trackerId` | |
| `trackState` | `TrackState` |
| `angle` | `func angle(at: Keypoint) throws -> Float?` |
| `distance` | `func distance(_ a: Keypoint, _ b: Keypoint) throws -> Float?` |

**Result value structs:**

| Struct | Fields |
|---|---|
| `Classification` | `classId, confidence` |
| `Depth` | `values: [Float], height, width, isMetric` |
| `Flow` | `uv: [Float], height, width` |
| `ModelSize` | `category, numParams, diskBytes` |
| `License` | `status, expiresAt, isPerpetual, isPaid` |

## Classes & keypoints

**`ClassRegistry`** (`Sequence`):

| Member | Signature |
|---|---|
| `count` | |
| `subscript(id)` | `-> LynxClass` |
| `subscript(name)` | `-> LynxClass?` |

**`LynxClass`**:

| Member | Signature |
|---|---|
| `id` | |
| `name` | |
| `keypoints` | `[Keypoint]` |
| `hasPose` | |
| `keypoint` | `keypoint(_ name:) throws -> Keypoint` |

**`Keypoint`**:

| Member |
|---|
| `classId` |
| `index` |
| `name` |

```swift
let person = model.classes["person"]!
let elbow  = try person.keypoint("left_elbow")
let angle  = try frame.detections[0].angle(at: elbow)   // degrees, optional
```

## Confidence — `struct Conf`

| Factory | |
|---|---|
| `Conf.balanced()` | |
| `Conf.maxRecall()` | |
| `Conf.maxPrecision()` | |
| `Conf.value(_ threshold: Float)` | |

Passing `conf: nil` to `open`/`predict` means "no global override" (raw 0.0), **not** the
calibrated default — pass `.balanced()` for the calibrated balanced point.

## Enums

| Enum | Cases |
|---|---|
| `Task: OptionSet` | `.box, .orientedBox, .segmentation, .depth, .pose, .classification, .reid, .text, .none` |
| `ModelSizeCategory` | `auto, pico, nano, medium, large` |
| `Goal` | `balanced, latency, throughput` |
| `Provider` | `cpu, cuda, tensorRT, coreML` |
| `TrackState` | `new, tentative, confirmed, lost` |
| `LicenseStatus` | `valid, expired, unknown` |

## Errors

`struct LynxError: Error`:

| Property | Type |
|---|---|
| `code` | `Int32` |
| `message` | `String` |
| `category` | `Category` |

All `throws` methods throw `LynxError`. `Category` cases mirror the C codes:

| Case |
|---|
| `.invalidArg` |
| `.format` |
| `.modelNotFound` |
| `.decryptCert` |
| `.licenseExpired` |
| `.accUnavailable` |
| `.unsupportedTask` |
| `.unknownClass` |
| `.failed` |
| … |

Match the exact case you need:

```swift
do { _ = try Lynx.open("nope") }
catch let e as LynxError where e.category == .modelNotFound { /* ... */ }
```

## Tracking

There's no separate tracker class in Swift today — per-detection track state is
carried on results across repeated `predict` calls (each auto-assigns a timestamp):

```swift
for d in frame.detections {
    let tid = d.trackerId          // 0 = untracked
    let state = d.trackState       // .new/.tentative/.confirmed/.lost
}
let idx = frame.index(ofTrack: 42) // -1 if absent
```

## Deferred realization (load with `retain: true`)

```swift
let f = try model.predict(path: "img.jpg", tasks: .box, retain: true)
try f.detections.run([.pose, .segmentation])   // ROI heads
try f.run(.depth)                                // frame-global head
```

## Not yet in the Swift binding

The streaming tracker class, batch inference, camera/video I/O, 3D-from-depth,
and the temporal track-value query (`Attribute`/`TemporalOp`/`TimeUnit` enums are
present but unused) are available in the C/Python/Kotlin/Java surfaces but not yet
wired into Swift. See [c.md](c.md) for the full superset.
