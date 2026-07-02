# LYNX SDK — Java API Reference

Package `ai.golynx.lynx`. Java 17.

```gradle
implementation 'ai.golynx.lynx:lynx-jvm:<version>'        // fat jar — all platforms' natives
// thin alternative: 'ai.golynx.lynx:lynx-jvm:<version>:thin' + a classifier jar
//   classifiers: linux-x86_64, linux-aarch64, darwin-aarch64, darwin-x86_64,
//                windows-x86_64, linux-x86_64-gpu (opt-in GPU)
```

Transitively pulls `com.microsoft.onnxruntime:onnxruntime:1.20.0`. The native
`liblynx_jni` is extracted from the classpath and loaded automatically on first
use (override the extract dir with `-Dlynx.nativedir=<path>` if `tmpdir` is noexec).

## Quickstart

```java
import ai.golynx.lynx.*;

Lynx.setApiKey(System.getenv("LYNX_API_KEY"));

try (Model model = Lynx.open("lynx-basic");
     Frame frame = model.predict("image.jpg")) {
    for (Detection d : frame.detections()) {
        System.out.printf("%s  conf=%.2f  box=%s%n",
            d.className(), d.confidence(), java.util.Arrays.toString(d.box()));
    }
    int[]   ids  = frame.detections().classId();          // vectorized columns
    float[] conf = frame.detections().confidence();
}
```

`Model`, `Frame`, `Tracker` are `AutoCloseable` (use try-with-resources; also
GC-cleaned via a `Cleaner` if you forget `close()`).

## `Lynx` — entry point (static)

```java
static String version()
static void setApiKey(String key)
static List<Provider> providers()
static Model open()                                       // slug "lynx-basic"
static Model open(String slug)
static Model open(String slug, Task tasks)
static Model open(String slug, Task tasks, Conf conf, Size size, Goal goal, String version)
static Model open(String slug, Task tasks, Conf conf, Size size, Goal goal, String version, Nms nms)
```

`conf == null` opens at the model's calibrated-balanced operating point (not a
flat floor). All `open` overloads throw `LynxException`.

## `Model implements AutoCloseable`

**Accessors:**

| Method | Returns |
|---|---|
| `classes()` | `ClassRegistry` |
| `version()` | `String` |
| `buildId()` | `String` |
| `capabilities()` | `Task` |
| `nmsFree()` | `boolean` |
| `size()` | `ModelSize` |
| `license()` | `License` |
| `providers()` | `List<Provider>` |

```java
Frame predict(String image)
Frame predict(String image, Conf conf)
Frame predict(String image, Conf conf, int maxDet, Task tasks, boolean retain)
Frame predict(String image, Conf conf, int maxDet, Task tasks, boolean retain, Nms nms)
Frame predict(byte[] image, int width, int height, …)    // raw RGB, HWC, width*height*3
List<Frame> predict(List<String> images, …)              // batch
void prepare(int[] batchSizes)
Tracker tracker()                                         // or tracker(double window) — seconds
void close()
```

## `Frame implements AutoCloseable`

```java
Detections detections()           // lazy, cached
Classifications classifications() // lazy, cached
float[] depthMap()                // dense H*W row-major, nullable
int[] depthMapShape()             // [H, W, metricFlag], nullable
boolean depthIsMetric()
void run(Task tasks)              // realize a frame-global head (e.g. Task.DEPTH)
int indexOf(int trackId)          // track id -> detection index, or -1
void submitFeedback(String imagePath, String correction)
```

## `Detections implements Iterable<Detection>`

```java
int size();  Detection get(int i);  Iterator<Detection> iterator();
Detections filter(Predicate<Detection> p);     // sub-view over same result
float[][] boxes();        // N x 4
float[][] orientedBoxes();// N x 5
int[] classId();  float[] confidence();
int[] trackerId();  int[] trackState();  float[] trackAge();
List<float[]> masks();  List<float[]> embeddings();  List<String> text();
float[] angleAt(Keypoint kp);                  // degrees; NaN where undefined
float[] distance(Keypoint a, Keypoint b);      // pixels; NaN where undefined
void run(Task tasks);                          // realize ROI heads for these
```

## `Detection` (scalar view)

```java
int index();  float[] box();  float[] orientedBox();
int classId();  float confidence();  String className();   // className nullable
float[] keypoints();   // K*3
float depth();         // meters if frame.depthIsMetric() else relative; NaN if none
float[] mask();  float[] embedding();  String text();      // text "" if none
int trackerId();  TrackState trackState();  float trackAge();
float angleAt(Keypoint kp);  float distance(Keypoint a, Keypoint b);
```

## Classifications, classes, value types

| Type | Method | Notes |
|---|---|---|
| `Classifications` | `int size()` | 0/1 |
| | `Classification get(int)` | |
| | `int[] classId()` | |
| | `float[] confidence()` | |
| `Classification` | `int classId()` | |
| | `float confidence()` | |
| `ClassRegistry implements Iterable<LynxClass>` | `int size()` | |
| | `LynxClass get(int id)` | |
| | `LynxClass get(String name)` | nullable |
| `LynxClass` | `int id()` | |
| | `String name()` | |
| | `List<Keypoint> keypoints()` | |
| | `boolean hasPose()` | |
| | `Keypoint keypoint(String name)` | throws `LynxException.NotFound` |
| `Keypoint` | `classId()` | |
| | `index()` | |
| | `name()` | |
| `ModelSize` | `Size category()` | |
| | `long numParams()` | |
| | `long diskBytes()` | |
| `License` | `LicenseStatus status()` | |
| | `long expiresAt()` | unix s, 0 = perpetual |
| | `boolean isPerpetual()` | |
| | `boolean isPaid()` | |

## `Tracker implements AutoCloseable`

```java
try (Model model = Lynx.open("lynx-basic");
     Tracker t = model.tracker(2.0)) {              // 2-second window
    for (String path : framePaths) {
        try (Frame frame = t.update(path)) {
            for (Detection d : frame.detections())
                System.out.printf("track %d %s age=%.1f%n", d.trackerId(), d.trackState(), d.trackAge());
        }
    }
}
```

| Method | Returns | Notes |
|---|---|---|
| `update(String image)` | `Frame` | sync |
| `submit(String image)` | `int` | async enqueue |
| `processNext()` | `Frame` | blocking dequeue+infer |

## Confidence & enums

`Conf.balanced()` / `maxRecall()` / `maxPrecision()` / `value(float threshold)`.

| Enum | Values |
|---|---|
| `Task` (int-bits wrapper) | `Task or(Task)`, `boolean contains(Task)`; constants `NONE, BOX, OBB, SEGMENTATION, DEPTH, POSE, CLASSIFICATION, REID, TEXT` |
| `Provider` | `CPU, CUDA, TENSORRT, COREML` |
| `Goal` | `BALANCED, LATENCY, THROUGHPUT` |
| `Nms` | `AUTO, ON, OFF` |
| `Size` | `AUTO, PICO, NANO, MEDIUM, LARGE` |
| `TrackState` | `NEW, TENTATIVE, CONFIRMED, LOST` |
| `LicenseStatus` | `VALID, EXPIRED, UNKNOWN` |

```java
try (Model m = Lynx.open("lynx-basic", Task.BOX.or(Task.SEGMENTATION));
     Frame f = m.predict("img.jpg", Conf.maxPrecision(), 100, Task.BOX.or(Task.SEGMENTATION), false, Nms.AUTO)) {
    Detections people = f.detections().filter(d -> "person".equals(d.className()) && d.confidence() > 0.5f);
}
```

## Exceptions

`abstract class LynxException extends RuntimeException` (unchecked; `int code`).

| Subtype | Code | Subclass |
|---|---|---|
| `InvalidArg` | -15 | |
| `Format` | -2 | |
| `UnsupportedTask` | -12 | |
| `UnknownClass` | -13 | |
| `Failed` | -14 | |
| `NotFound` | -10 | `ModelNotFound(-16)` |
| `Decrypt` | -4 | `DecryptCert(-17)` |
| `Expired` | -7 | `LicenseExpired(-18)` |
| `Unavailable` | -8 | `AccUnavailable(-19)` |
| `Other` | | |

```java
try { Lynx.open("nope"); }
catch (LynxException.NotFound e) { /* incl. ModelNotFound */ }
catch (LynxException e) { System.err.println("lynx " + e.code + ": " + e.getMessage()); }
```

## Notes

`Track`, `Attr`, `Op`, `TimeUnit` are present but not yet wired into any public
method (reserved for a future temporal-measurement API). Camera/video I/O and
3D-from-depth are in the C/Python surface; see [c.md](c.md).
