# Installation & system requirements

> LYNX is in **private beta** (pre-release). Details may shift before general availability.

LYNX is **one C inference core with a thin, idiomatic binding per language** — the same models and the same `open → predict → detections` shape everywhere, from a Swift app to a Python script.

## Supported platforms & versions

**SDK version: 1.0.** The build/patch number increments over time; confirm the exact build at runtime with `version()` (`Lynx.version()` / `lynx.version()` / `lynx_version()`).

**CPU-only inference** is supported on every platform via ONNX Runtime — no GPU required, at reduced throughput. **Python wheels** are selected automatically by `pip`. **Jetson** compiles to TensorRT on first run and caches the engine (JetPack 5 & 6).

### Python

| Platform | Architecture | Min version | Acceleration |
|---|---|---|---|
| Linux | x86_64, aarch64 | Python 3.10–3.14 | CUDA / TensorRT · CPU |
| macOS | Apple Silicon, Intel | Python 3.10–3.14 | CoreML · CPU |
| Windows | x86_64 | Python 3.10–3.14 | CUDA / DirectML · CPU |
| Jetson | aarch64 | Python 3.10–3.14 · JetPack 5/6 | TensorRT |

### C

| Platform | Architecture | Min version | Acceleration |
|---|---|---|---|
| Linux | x86_64, aarch64 | — | CUDA / TensorRT · CPU |
| macOS | Apple Silicon, Intel | — | CoreML · CPU |
| Jetson | aarch64 | JetPack 5/6 | TensorRT |

### Swift

| Platform | Architecture | Min version | Acceleration |
|---|---|---|---|
| iOS / iPadOS | arm64 | iOS 16 | CoreML (Neural Engine) |
| macOS | Apple Silicon, Intel | macOS 12 (Swift 5.9) | CoreML · CPU |

### Kotlin

| Platform | Architecture | Min version | Acceleration |
|---|---|---|---|
| Android | arm64-v8a | `minSdk 24` (Android 7.0) | GPU · CPU |

### Java

| Platform | Architecture | Min version | Acceleration |
|---|---|---|---|
| Linux | x86_64, aarch64 | JDK 17 | CUDA / TensorRT · CPU |
| macOS | Apple Silicon, Intel | JDK 17 | CoreML · CPU |
| Windows | x86_64 | JDK 17 | CUDA / DirectML · CPU |

## Offline operation

Inference runs on-device — no per-frame network calls, no cloud dependency, and your video never leaves your hardware. **Telemetry is optional and can be turned off.** Trial verification uses periodic connectivity when available; paid licenses can be configured for extended offline operation. See the [licensing page](https://golynx.ai/licensing) for how activation works.
