# Install — C / C++

> **LYNX SDK 1.0** · see [Supported platforms & versions](../support.md)

<!-- HUMAN -->
Download the C SDK (header + shared lib) from a build run and compile against it:

```sh
gh run download <build-run-id> -R Syneticai/LYNX-SDK -n core-sdk-linux-x64-cpu -D ./lynx_sdk
cc app.c -I./lynx_sdk/include -L./lynx_sdk/lib -llynx -o app
```

`#include "lynx.h"`.

<!-- LLM -->

The C deliverable is **one header + one library**:

- **Header:** `lynx.h` — the curated public surface (the `LYNX_PUBLIC` symbols). It ships with only `lynx_export.h` beside it and pulls in no sibling headers, so you copy those two files and nothing else.
- **Library:** `liblynx.so` / `liblynx.dylib` — the core, with ONNX Runtime, libsodium/OpenSSL, libcurl, and the image codecs (jpeg/png/webp/heif/tiff) linked in as its dependencies.

## Get the SDK

The CI build publishes a ready-to-link bundle that contains `liblynx.so`, `lynx.h`, and `libonnxruntime.so` together — no build step:

```sh
gh run download <build-run-id> -R Syneticai/LYNX-SDK \
    -n core-sdk-linux-x64-cpu -D ./lynx_sdk
# -> ./lynx_sdk/include/lynx.h , ./lynx_sdk/lib/liblynx.so , libonnxruntime.so
```

<!-- TODO: confirm the GA distribution channel + download URL for the C SDK tarball. Today it is delivered as the CI artifact `core-sdk-linux-x64-cpu` (and per-platform siblings); a versioned customer-facing tarball/release URL is not yet documented in the repo. -->

## Compile & link

Point the compiler at the bundle's `include/` and `lib/`, link `-llynx`, and make the libraries discoverable at runtime:

```sh
cc app.c -I./lynx_sdk/include -L./lynx_sdk/lib -llynx -o app

# run: the loader must find liblynx.so + libonnxruntime.so
LD_LIBRARY_PATH=./lynx_sdk/lib ./app image.jpg
```

On macOS, link the same way (`-llynx` resolves `liblynx.dylib`) and use `DYLD_LIBRARY_PATH` (or an `@rpath`/`install_name` for a bundled app). `liblynx` carries ONNX Runtime and the codecs as its own dependencies, so an app links just `-llynx` — you don't add `-lonnxruntime`, `-lsodium`, etc. yourself.

C++ is fine: `lynx.h` is wrapped in `extern "C"`, so `#include "lynx.h"` works unchanged from a `.cpp`.

## Verify

```c
#include <stdio.h>
#include "lynx.h"
int main(void) { printf("lynx %s\n", lynx_version()); return 0; }   /* -> "lynx 1.0.x" */
```

## Supported platforms

| platform | library | acceleration |
|---|---|---|
| linux-x64 (glibc) | `liblynx.so` | CPU; CUDA + TensorRT execution providers when present |
| linux-aarch64 (glibc) | `liblynx.so` | CPU (generic ARM) |
| macOS (Apple Silicon / Intel) | `liblynx.dylib` | CoreML |

<!-- TODO: confirm the shipping Windows C deliverable name (a Win core build — liblynx.lib / lynx.dll — exists in the repo build tooling, but the customer-facing Windows C SDK packaging/flags aren't documented in README/BUILDING; the liblynx.mk shared-lib target only emits ELF (.so) and Mach-O (.dylib)). -->

> Acceleration is detected at runtime; with no accelerator the SDK falls back to CPU automatically (unless you set `require_acceleration` in `lynx_model_opts_t`, which makes `lynx_open` fail with `LYNX_ERR_UNAVAILABLE`). Probe what initializes on a host with `lynx_available_providers(...)` — see [`api/c.md`](../api/c.md).

## Notes

- **No keys for public models** — `lynx-basic` and `lynx-ocr-fleet` are keyless; the SDK mints a per-device trial on first load. For a licensed/private model, call `lynx_set_apikey("lnx_…")` once at startup before the first `lynx_open`.
- **First `lynx_open` does a network fetch** + verify + cache (a few seconds); later opens are local. Resolving a catalog model needs the download credential — `lynx_set_apikey` or `$LYNX_API_KEY` — except for the keyless public models above.
- Next: [`recipes/c-detection.md`](../recipes/c-detection.md) for a complete working integration.
