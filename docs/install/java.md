# Install — Java / JVM (Gradle, Maven)

> **LYNX SDK 1.0** · see [Supported platforms & versions](../support.md)

<!-- HUMAN -->
Add the dependency (JDK 17):

```kotlin
implementation("ai.golynx.lynx:lynx-jvm:1.0.0")   // Gradle
```

`import ai.golynx.lynx.Lynx`.

<!-- LLM -->

The SDK is one Maven coordinate — `ai.golynx.lynx:lynx-jvm` — that bundles the Java classes plus the prebuilt JNI native core (the obfuscated C core + crypto). ONNX Runtime is pulled transitively as the inference backend.

The plain dependency (no classifier) is the **fat jar**: it carries every platform's native, so it "just works" on any host.

## Gradle (recommended)

```kotlin
dependencies {
    implementation("ai.golynx.lynx:lynx-jvm:1.0.0")   // <!-- TODO: confirm published version (build default is 0.1.0-dev; publish repo not yet wired) -->
}
```

Groovy DSL:

```groovy
implementation 'ai.golynx.lynx:lynx-jvm:1.0.0'
```

## Maven

```xml
<dependency>
  <groupId>ai.golynx.lynx</groupId>
  <artifactId>lynx-jvm</artifactId>
  <version>1.0.0</version> <!-- TODO: confirm published version -->
</dependency>
```

`com.microsoft.onnxruntime:onnxruntime` (the inference backend) comes transitively via the POM — you don't add it yourself.

## Slim it down (optional)

The fat jar ships every platform's native. To carry only the host you target, depend on the **thin** jar plus the per-platform classifier jar:

```kotlin
implementation("ai.golynx.lynx:lynx-jvm:1.0.0:thin")
runtimeOnly("ai.golynx.lynx:lynx-jvm:1.0.0:linux-x86_64")   // pick your platform
```

Available native classifiers: `linux-x86_64`, `linux-aarch64`, `darwin-aarch64`, `darwin-x86_64`, `windows-x86_64`, and the opt-in GPU build `linux-x86_64-gpu` (CUDA/TensorRT).

## Native library loading

You do nothing — `NativeLoader` handles it. On first use it detects the host (`os.name`/`os.arch` → a classifier like `linux-x86_64`, `darwin-aarch64`, `windows-x86_64`), extracts the matching JNI lib (`liblynx_jni.so` / `.dylib` / `lynx_jni.dll`) from the jar to a version-scoped temp dir, and `System.load`s it once.

- If `java.io.tmpdir` is mounted `noexec`, point extraction at an exec-mounted path with `-Dlynx.nativedir=/some/exec/dir`.
- If you used the thin jar without a matching classifier jar, the first call throws `UnsatisfiedLinkError` naming the missing `ai.golynx.lynx:lynx-jvm:<ver>:<classifier>` — add it (or switch to the fat jar).

## Verify

```java
import ai.golynx.lynx.Lynx;

System.out.println(Lynx.version());   // "1.0.x"
```

## Notes

- No keys needed for public models (e.g. `lynx-basic`) — the SDK mints a per-device trial on first load. For a licensed model, call `Lynx.setApiKey("lnx_…")` once at startup before the first `Lynx.load`/`Lynx.open`.
- First `Lynx.load` does a network fetch + verify + cache (a few seconds); run it off the main thread. Later loads are local.
- Next: [`recipes/java-detection.md`](../recipes/java-detection.md) for a complete working integration.
