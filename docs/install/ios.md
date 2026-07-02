# Install — iOS / macOS (Swift)

> **LYNX SDK 1.0** · see [Supported platforms & versions](../support.md)

<!-- HUMAN -->
Add the Swift Package (Xcode → File → Add Packages, or `Package.swift`):

```swift
.package(url: "https://github.com/Syneticai/LYNX-SDK.git", from: "1.0.0"),
// per target: .product(name: "Lynx", package: "LYNX-SDK")
```

`import Lynx` · minimum **iOS 16 / macOS 12**.

<!-- LLM -->

The SDK is a Swift package (`Lynx`) plus a prebuilt binary core (`LynxCore.xcframework`, the obfuscated C core + ONNX Runtime + crypto). You add the package and make the xcframework available to its `binaryTarget`.

## Swift Package Manager (recommended)

In Xcode: **File ▸ Add Package Dependencies…** and add the Lynx package URL, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Syneticai/LYNX-SDK.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "Lynx", package: "LYNX-SDK")]),
]
```

The package's `LynxCore` is a `.binaryTarget`. Use the versioned XCFramework artifact (URL + checksum) published with the release; if you vendor it manually, drop `LynxCore.xcframework` next to the package manifest. Without it the package resolves but won't link.

Then:

```swift
import Lynx
```

## Verify

```swift
print(Lynx.version())   // "1.0.x"
```

## Notes

- No keys needed for public models (e.g. `lynx-basic`) — the SDK mints a per-device trial on first load. For a licensed model, call `Lynx.setApiKey("lnx_…")` once at startup before the first `Lynx.load`.
- First `Lynx.load` does a network fetch + verify + cache (a few seconds); run it off the main thread. Later loads are local.
- Next: [`recipes/ios-detection.md`](../recipes/ios-detection.md) for a complete working integration.
