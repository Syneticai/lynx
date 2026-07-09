# Telemetry & privacy

> For LYNX SDK **1.0**. What the SDK sends, and how to turn it off.

## What LYNX collects

LYNX records **anonymous usage telemetry** — a minimal event per inference so we
can see which model versions are in use and roughly how much. It is **on by
default**. A small C-owned background sender batches events and POSTs them to
Synetic (`https://golynx.ai/api/telemetry`) about every 30 seconds (or sooner
under load); on failure they're retried, never written to disk.

Each event carries only:

| Field | Example | Why |
|---|---|---|
| event + timestamp | `infer`, `1720557000` | which SDK operation ran |
| model version | `2.0` | which model/version is in use |
| SDK version | `1.0.x` | which SDK build |
| device fingerprint | 16-hex | de-duplicate installs (a stable hash of machine id / MAC / CPU) |

If you've set an API key (for licensed models), the request also carries it as a
`Bearer` header so usage can be attributed to your account.

**What is never sent:** image or video data, file paths, detection results,
text/OCR output, or any other PII. The event metadata is allow-listed in the
core — only the fields above can be emitted.

## Turning telemetry off

Disable it once at startup, **before** your first `open()` — when disabled, no
telemetry thread, queue, or network socket is ever created.

**Environment variable** (no code; applies to every language):

```bash
export LYNX_TELEMETRY=0      # also accepts false / off / no
```

**In code** (an explicit call overrides the env var):

```python
import lynx
lynx.set_telemetry_enabled(False)      # Python
```
```swift
Lynx.setTelemetryEnabled(false)        // Swift
```
```kotlin
Lynx.setTelemetryEnabled(false)        // Kotlin
```
```java
Lynx.setTelemetryEnabled(false);       // Java
```
```c
lynx_set_telemetry_enabled(0);         /* C */
```

## Feedback (separate, and opt-in)

`Frame.submit_feedback(...)` sends a correction you *explicitly* submit to
improve a model — it never fires on its own. It's governed by its own switch
(`set_feedback_enabled(false)` / `Lynx.setFeedbackEnabled(false)`), also on by
default. If you never call `submit_feedback`, nothing is sent regardless.

## Self-hosted / air-gapped

The telemetry endpoint is fixed. In an air-gapped or on-prem deployment, set
`LYNX_TELEMETRY=0` (or call `set_telemetry_enabled(false)`) so the SDK makes no
telemetry egress at all. Model download + license verification are separate
network paths — see [`support.md`](support.md).
