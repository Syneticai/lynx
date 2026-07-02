# Install — Python

> **LYNX SDK 1.0** · see [Supported platforms & versions](../support.md)

<!-- HUMAN -->
```bash
pip install lynx --extra-index-url <your beta index URL>
```

Python **3.10–3.14** · `import lynx`. The beta index URL comes with onboarding.

<!-- LLM -->

The SDK ships as the `lynx` distribution: a prebuilt binary wheel (the obfuscated C core + ONNX Runtime + crypto + image codecs, all bundled — no system libraries to install) plus a thin numpy-first Python surface. `numpy` is the only Python runtime dependency and is pulled in automatically.

## pip install

> **🧪 Private beta.** The SDK is **not** on public PyPI yet — `pip install lynx`
> from PyPI gets the wrong package. The real package (`lynx`) ships from
> Synetic's own beta index; **beta participants receive the `--extra-index-url`
> value at onboarding.** Substitute it for `<your beta index URL>` below.
> (The plain `pip install lynx` commands apply once the SDK reaches general
> availability.)

```bash
pip install lynx --extra-index-url <your beta index URL>
```

The default `lynx` wheel bundles the **GPU** ONNX Runtime (CUDA / TensorRT execution providers lazy-load at runtime; on a CPU-only host it imports and runs on CPU silently). For a lean **CPU-only** wheel (Linux x86_64), install the `lynx-cpu` distribution instead:

```bash
pip install lynx-cpu --extra-index-url <your beta index URL>
```

Optional extras:

```bash
pip install "lynx[cli]" --extra-index-url <your beta index URL>   # the `lynx` CLI (adds opencv-python)
```

## Verify

```python
import lynx
print(lynx.version())          # "1.0.x"
print(lynx.providers())        # [<Provider.CPU>, <Provider.CUDA>, ...] available here
```

Or from the shell (the wheel installs a `lynx` console script):

```bash
lynx --version
```

## GPU notes

- The GPU wheel bundles ONNX Runtime's CUDA/TensorRT provider libraries but relies on the **host's** CUDA toolkit + cuDNN at runtime (NVIDIA's redistribution terms; every realistic GPU host already has them).
- If `lynx.providers()` doesn't list `Provider.CUDA`, the usual missing piece is cuDNN: `pip install nvidia-cudnn-cu12` (matches the bundled ORT's cuDNN 9 requirement).
- Select GPUs/threads once at startup before any `open`/`predict`: `lynx.set_workers(gpus=1)` (first GPU) or `lynx.set_workers(gpus=[0, 2], cpus=12)`. CPU-only: `lynx.set_workers(cpus=8)`.

## Notes

- No keys needed for public models (e.g. `lynx-basic`, `lynx-ocr-fleet`) — the SDK mints a per-device trial on first load. For a licensed model, call `lynx.set_license("lnx_…")` once at startup before the first `lynx.open`.
- First `lynx.open` does a network fetch + verify + cache (a few seconds); run it off the UI thread. Later loads are local.
- Next: [`recipes/python-detection.md`](../recipes/python-detection.md) for a complete working integration.
