# Install — Android (Kotlin)

> **LYNX SDK 1.0** · see [Supported platforms & versions](../support.md)

<!-- HUMAN -->
Add the Gradle dependency (`arm64-v8a`, `minSdk 24`) with `google()` + `mavenCentral()` repos:

```kotlin
implementation("ai.synetic:lynx:<version>")
```

`import ai.synetic.lynx.Lynx`. (Until it publishes, vendor the `.aar` — see full guide.)

<!-- LLM -->

The SDK is an Android library (`.aar`) — the obfuscated C core + JNI shim (`liblynx_jni.so`, plus `libc++_shared.so`) compiled per-ABI, with the Kotlin wrapper on top. ONNX Runtime for Android is the inference backend and comes in transitively.

## Gradle dependency

Maven coordinates from the library's publishing config: group `ai.synetic`, artifact `lynx`.

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
```

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.synetic:lynx:<version>")   // <!-- TODO: confirm published version + repository — the AAR's maven-publish block is configured (groupId=ai.synetic, artifactId=lynx) but NOT yet wired to a repository; default project version is "0.1.0-dev". Until it publishes, vendor the .aar (see below). -->
}
```

### Vendoring the AAR (until it publishes)

Build the AAR from the SDK repo (`lynx/kotlin/`) with `./gradlew assembleRelease` (pass `-PabiFilter=arm64-v8a` to build only the shipping ABI, and `-PlynxPrebuiltJni=<dir>` to package the harness-tested obfuscated `.so`), then drop the `.aar` into your app's `libs/` and:

```kotlin
// app/build.gradle.kts
dependencies {
    implementation(files("libs/lynx-release.aar"))
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0") // backend, transitive in the published artifact
}
```

## ABI

Restrict the packaged ABIs to the one that ships — `arm64-v8a`:

```kotlin
// app/build.gradle.kts
android {
    defaultConfig {
        ndk { abiFilters += "arm64-v8a" }
    }
}
```

## Permissions

The library manifest already declares `android.permission.INTERNET` (needed to resolve + download the `.lnx` on first load) and merges into your app — no extra manifest entry required.

## Native load

The native library loads itself: the internal `Native` object calls `System.loadLibrary("lynx_jni")` on first use of the SDK. You never call `loadLibrary` yourself. The `.so` is shipped uncompressed + page-aligned (16 KB, Play-compliant).

## Verify

```kotlin
import ai.synetic.lynx.Lynx
Log.d("lynx", Lynx.version())   // "1.0.x"
```

## Notes

- No keys needed for public models (e.g. `lynx-basic`) — the SDK mints a per-device trial on first load. For a licensed model, call `Lynx.setApiKey("lnx_…")` once at startup before the first `Lynx.open`.
- First `Lynx.open` does a network fetch + verify + cache (a few seconds); run it **off the main thread**. Later loads are local.
- Next: [`recipes/android-detection.md`](../recipes/android-detection.md) for a complete working integration.
