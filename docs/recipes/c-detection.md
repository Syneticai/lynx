# Recipe — object detection (C)

> For LYNX SDK **1.0**. Complete, end-to-end. Install: [`install/c.md`](../install/c.md). API: [`api/c.md`](../api/c.md). Conventions: [`api/conventions.md`](../api/conventions.md).

Goal: load a model, run detection on an image, print each detection's class name + score + box. Model: `lynx-basic` (keyless, 80 COCO classes — see [`models/catalog.md`](../models/catalog.md)).

C has **no exceptions** — every fallible call returns a value you check by hand. The two shapes you'll use here:

- `lynx_open` / `lynx_infer` produce a heap resource → they return a **pointer** (`NULL` = failure) with a `lynx_error_t* err` out-param.
- The per-detection accessors return an **`int` ok flag** + fill an out-struct (`0` = that head wasn't run, not a hard error).

You free what you opened, in order: the result, then the model handle, then the one-time process shutdown.

## The whole thing

`detect.c` — compiles and runs as-is:

```c
/* detect.c — LYNX object detection in C.
 * Build: cc detect.c -I./lynx_sdk/include -L./lynx_sdk/lib -llynx -o detect
 * Run:   LD_LIBRARY_PATH=./lynx_sdk/lib ./detect image.jpg
 */
#include <stdio.h>
#include "lynx.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <image>\n", argv[0]);
        return 2;
    }

    /* lynx-basic is keyless — no lynx_set_apikey() needed. NULL opts = defaults. */
    lynx_error_t err = {0};
    lynx_model_t* model = lynx_open("lynx-basic", NULL, &err);
    if (!model) {
        fprintf(stderr, "lynx_open failed: %d %s\n", err.code, err.message);
        return 1;
    }

    /* Describe the input frame: an image file on disk. */
    lynx_frame_t frame = {
        .kind         = LYNX_FRAME_PATH,
        .path         = argv[1],
        .timestamp_ns = 0,            /* matters for streams; ignored for a still */
    };

    /* Per-call options: raw 0.40 confidence threshold, no detection cap. */
    lynx_conf_t conf = { .mode = LYNX_NON_CALIBRATED, .value = 0.40f };
    lynx_infer_opts_t opts = { .conf = &conf, .max_det = 0 };

    /* Run detection. NULL return => failure, read err. */
    lynx_frame_result_t* result = lynx_infer(model, &frame, &opts, &err);
    if (!result) {
        fprintf(stderr, "lynx_infer failed: %d %s\n", err.code, err.message);
        lynx_close(model);
        lynx_shutdown();
        return 1;
    }

    /* Loop the detections: class name + score + box (input-frame pixels). */
    int n = lynx_frame_result_count(result);
    printf("%d detection(s)\n", n);
    for (int i = 0; i < n; i++) {
        const char* name  = lynx_frame_result_class_name(result, i);  /* borrowed, may be NULL */
        float       score = lynx_frame_result_confidence(result, i);

        lynx_box_t box;
        if (lynx_frame_result_bounding_box(result, i, &box)) {        /* 1 = box present */
            printf("  %-16s  conf=%.2f  box=[%.1f, %.1f, %.1f, %.1f]\n",
                   name ? name : "?", score, box.x1, box.y1, box.x2, box.y2);
        } else {
            printf("  %-16s  conf=%.2f  (no box)\n", name ? name : "?", score);
        }
    }

    /* Free in order: result, then handle, then process-global runtime (once, last). */
    lynx_frame_result_free(result);
    lynx_close(model);
    lynx_shutdown();
    return 0;
}
```

## Build & run

```sh
cc detect.c -I./lynx_sdk/include -L./lynx_sdk/lib -llynx -o detect
LD_LIBRARY_PATH=./lynx_sdk/lib ./detect image.jpg
```

(`./lynx_sdk` is the bundle from [`install/c.md`](../install/c.md): `include/lynx.h` + `lib/liblynx.so` + `libonnxruntime.so`.) Expected output:

```
4 detection(s)
  person            conf=0.94  box=[48.0, 20.5, 210.2, 460.9]
  dog               conf=0.88  box=[260.1, 300.4, 520.7, 470.0]
  ...
```

## Running on raw pixels instead of a file path

If you already have decoded **RGB** bytes (`width*height*3`, row-major, top-left origin), point the frame at them instead of a path — everything else is identical:

```c
lynx_frame_t frame = {
    .kind          = LYNX_FRAME_PIXELS,
    .pixels        = rgb,                  /* const uint8_t*, width*height*3 */
    .w             = width,
    .h             = height,
    .channel_order = LYNX_CHANNELS_RGB,    /* or LYNX_CHANNELS_BGR / _AUTO */
    .timestamp_ns  = 0,
};
```

`LYNX_FRAME_BYTES` (set `.bytes` + `.bytes_len`) takes an **encoded** image (JPEG/PNG/…) in memory and lets the SDK decode it.

## Notes

- **Error checking is the contract.** `lynx_open` and `lynx_infer` return `NULL` on failure with `err.code` set to one of the public codes (`LYNX_ERR_MODEL_NOT_FOUND`, `LYNX_ERR_INVALID_ARG`, …) — switch on `err.code`, never on `err.message`. Full table in [`api/c.md`](../api/c.md).
- **`box` is `{x1, y1, x2, y2}`** in the input image's pixels. `lynx_frame_result_bounding_box` returns `1` when the box is present (the detection spine — box + class + confidence — always runs).
- **Confidence:** `{ LYNX_NON_CALIBRATED, 0.40f }` is a raw threshold. For the model's calibrated operating points use `{ LYNX_CALIBRATED_BALANCED, 0 }` (also `MAX_RECALL` / `MAX_PRECISION`), or pass `opts.conf = NULL` for the model's default.
- **Other heads** (segmentation, pose, depth) live on the **same** result. `lynx-basic` exposes them; realize them with `lynx_result_run(result, LYNX_TASK_DEPTH)` (frame-global) or `lynx_result_run_for(result, i, LYNX_TASK_POSE | LYNX_TASK_SEGMENTATION)` (per detection, requires `opts.retain_features = 1` at infer time), then read `lynx_frame_result_pose` / `_segmentation` / `_depth_map`. Confirm what a model has with `lynx_get_capabilities` first.
- **Reuse one handle** across images — open once, infer many, free each result, then `lynx_close` + `lynx_shutdown` at exit. Don't reopen per image.
- **Free once.** Each `lynx_infer` result is caller-owned; free it with `lynx_frame_result_free`. (A batch from `lynx_infer_batch` is one `lynx_batch_result_free` for the whole batch — the results inside are borrowed.)
