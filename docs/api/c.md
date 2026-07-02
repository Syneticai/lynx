# LYNX SDK — C API Reference

`#include "lynx.h"` and link against `liblynx` (the prebuilt keyed core ships
with `lynx.h` + `libonnxruntime`). Every public function is `LYNX_PUBLIC`.

## Quickstart

```c
#include "lynx.h"
#include <stdio.h>

int main(void) {
    lynx_error_t err = {0};
    lynx_set_apikey("lk_...");                       /* download credential, once */

    lynx_model_t* m = lynx_open(LYNX_DEFAULT_MODEL, NULL, &err);  /* "lynx-basic" */
    if (!m) { fprintf(stderr, "open: [%d] %s\n", err.code, err.message); return 1; }

    lynx_frame_t frame = {
        .kind = LYNX_FRAME_PIXELS, .pixels = rgb, .h = H, .w = W,
        .channel_order = LYNX_CHANNELS_RGB, .timestamp_ns = 0,   /* timestamp required */
    };
    lynx_infer_opts_t opts = { .max_det = 100 };     /* conf NULL -> open-time default */
    lynx_frame_result_t* r = lynx_infer(m, &frame, &opts, &err);
    if (!r) { fprintf(stderr, "infer: [%d] %s\n", err.code, err.message); lynx_close(m); return 1; }

    for (int i = 0; i < lynx_frame_result_count(r); i++) {
        const char* name = lynx_frame_result_class_name(r, i);   /* borrowed */
        float conf = lynx_frame_result_confidence(r, i);
        lynx_box_t b;
        if (lynx_frame_result_bounding_box(r, i, &b))
            printf("%s %.2f  (%.0f,%.0f)-(%.0f,%.0f)\n", name?name:"?", conf, b.x1,b.y1,b.x2,b.y2);
    }

    lynx_frame_result_free(r);   /* free owned result */
    lynx_close(m);               /* close handle (invalidates borrowed names) */
    lynx_shutdown();             /* once, after all handles closed */
    return 0;
}
```

## Error handling & ownership

- **Fallible + returns a resource:** returns a pointer (`NULL` = failure) and
  fills a nullable `lynx_error_t* err`. **Fallible, no resource:** returns
  `lynx_error_t` by value. Check `err.code` against the `LYNX_ERR_*` macros;
  `err.message` is a 256-byte inline buffer.
- **You own (must release):**

| Create | Release |
|---|---|
| `lynx_open` | `lynx_close` |
| `lynx_infer` / `lynx_stream_process*` | `lynx_frame_result_free` |
| `lynx_infer_batch` | `lynx_batch_result_free` |
| `lynx_stream_open` | `lynx_stream_close` |
| `lynx_camera_open` | `lynx_camera_close` |
| `lynx_video_writer_open` | `lynx_video_writer_close` |
| process exit | `lynx_shutdown` (once, last) |

- **Borrowed (never free), lifetime-scoped:** Never store these across the freeing call.

| Borrowed pointer | Valid until |
|---|---|
| all `const char*` (class/part names, `model_version`, `build_id`) and `lynx_class_t*`/`lynx_part_t*` handles | `lynx_close` |
| struct-out pointers (`mask.xy`, `embedding.vec`, `depth.depth`, `flow.uv`, `text.text`) and `lynx_column_view_t.base` | the result is freed |
| `lynx_camera_read` pixels | next read |

## Error codes

| Code | Value | Meaning |
|---|---|---|
| `LYNX_OK` | 0 | Success |
| `LYNX_ERR_FAILED` | -14 | Generic failure |
| `LYNX_ERR_INVALID_ARG` | -15 | Bad argument |
| `LYNX_ERR_FORMAT` | -2 | Malformed/unsupported file |
| `LYNX_ERR_UNSUPPORTED_TASK` | -12 | Task not on this model |
| `LYNX_ERR_UNKNOWN_CLASS` | -13 | Class not in model |
| `LYNX_ERR_NOT_FOUND` | -10 | Model not found |
| `LYNX_ERR_MODEL_NOT_FOUND` | -16 | Model not found |
| `LYNX_ERR_DECRYPT` | -4 | Decryption failure |
| `LYNX_ERR_DECRYPT_CERT` | -17 | Cert failure |
| `LYNX_ERR_EXPIRED` | -7 | License expired |
| `LYNX_ERR_LICENSE_EXPIRED` | -18 | License expired |
| `LYNX_ERR_UNAVAILABLE` | -8 | Accelerator unavailable |
| `LYNX_ERR_ACC_UNAVAILABLE` | -19 | Accelerator unavailable |

## Lifecycle

| Function | Notes |
|---|---|
| `const char* lynx_version(void)` | Borrowed static. |
| `lynx_model_t* lynx_open(const char* slug, const lynx_model_opts_t* opts, lynx_error_t* err)` | Load one model. NULL slug → `"lynx-basic"`. NULL opts = all defaults. Owned. |
| `void lynx_close(lynx_model_t* h)` | NULL-safe; wipes weights. |
| `void lynx_shutdown(void)` | Once at exit, after all handles closed. |
| `lynx_error_t lynx_prepare(lynx_model_t* h, const int* batch_sizes, int n)` | Pre-build engines (size 1 = warm-up). |
| `const int* lynx_available_batch_sizes(const lynx_model_t* h, int* n)` | Borrowed; valid until next prepare/close. |

## Setup / license / workers

| Function | Notes |
|---|---|
| `lynx_error_t lynx_set_apikey(const char* key)` | Per-account download credential (not a license). |
| `lynx_error_t lynx_set_workers(const lynx_worker_opts_t* opts)` | CPU threads / GPU ids; call once before `lynx_open`. gpu list is copied. |
| `int lynx_cuda_device_count(void)` | Visible CUDA devices. |
| `void lynx_set_diagnostic_callback(lynx_diagnostic_cb cb, void* user)` | Structured log notices. |
| `void lynx_set_telemetry_enabled(int)` / `lynx_set_feedback_enabled(int)` | Deployment hard-off switches (default on). |
| `int lynx_get_license(const lynx_model_t* h, lynx_license_info_t* out)` | Reads the loaded cert; never re-decrypts. |
| `lynx_error_t lynx_available_providers(lynx_provider_t* out, int cap, int* n)` | Probe host without loading a model. |

## Inference

| Function | Notes |
|---|---|
| `lynx_frame_result_t* lynx_infer(h, frame, opts, err)` | Stateless. Owned result. |
| `lynx_batch_result_t* lynx_infer_batch(h, frames, n, opts, err)` | Owned container; inner results borrowed; one `lynx_batch_result_free`. |
| `int lynx_batch_result_count(b)` / `const lynx_frame_result_t* lynx_batch_result_at(b, k)` | Borrowed inner result. |
| `lynx_error_t lynx_result_run(r, tasks)` | Realize frame-global (DEPTH/CLASSIFICATION) or all-ROI heads. Needs `retain_features=1`. Mutates result. |
| `lynx_error_t lynx_result_run_for(r, det, tasks)` | Realize ROI heads (POSE/SEG/OBB/TEXT/REID) for one detection. |

`lynx_infer_opts_t`: `{ const lynx_conf_t* conf; int max_det; uint32_t tasks; int retain_features; lynx_nms_mode_t nms; }` (`max_det` 0 = no cap; `tasks` 0 = open-time set; non-zero must be a subset).

## Result accessors

Per-detection (`i` in survivor order): `lynx_frame_result_count`,
`_class(r,i)`, `_class_name(r,i)` (borrowed), `_confidence(r,i)`.

Geometry / per-task (return 1/count, 0 if absent — always check):

| Accessor | Out type |
|---|---|
| `_bounding_box` | `lynx_box_t` |
| `_oriented_bounding_box` | `lynx_obox_t` |
| `_segmentation` | `lynx_mask_t` |
| `_pose(r,i,out,cap)` | keypoint count |
| `_text_recognition` | `lynx_text_t` |
| `_reid` | `lynx_embedding_t` |

Whole-frame:

| Accessor | Out type |
|---|---|
| `_classification(r,&id,&conf)` | — |
| `_depth_map` | `lynx_depth_t` |
| `lynx_depth_at(r, pt, &ok)` | — |
| `_optical_flow` | `lynx_flow_t` |

Size plausibility: `_metric_size`, `_size_plausibility`, `_size_verdict`,
`_adjusted_score`. 3D: `_position_3d(r,i,cam,out)`, `_box_3d(r,i,cam,out)`
(`cam` = `lynx_intrinsics_t{fx,fy,cx,cy}`).

Zero-copy columns: `lynx_frame_result_column(r, which, &view)` →
`lynx_column_view_t` (read-only, valid until free).

In-place post-process: `lynx_frame_result_suppress_overlaps(r, iou)`,
`lynx_frame_result_apply_ocr_nms(r, depth, iou, ios, min_enclosed)`.

Pose geometry: `lynx_pose_angle_at`, plus point builders
(`lynx_pt_kp/_root/_near/_xy`, track variants `lynx_pt_t*`) feeding
`lynx_distance(r,a,b,&ok)` / `lynx_angle(r,vertex,a,b,&ok)`.

## Introspection

| Function | Notes |
|---|---|
| `lynx_get_capabilities` | → `lynx_capabilities_t{tasks,temporal,nms_free}` |
| `lynx_model_version` / `lynx_model_build_id` | borrowed, handle life |
| `lynx_get_num_classes`, `lynx_get_class_name` | |
| `lynx_class` / `lynx_class_by_id` | → `lynx_class_t*` (borrowed) + `lynx_class_id/_name/_has_pose` |
| `lynx_get_size` | → `lynx_model_size_t` |
| `lynx_get_active_providers` | borrowed |
| `lynx_provider_name` | |

Pose schema (by `lynx_class_t*`): `lynx_pose_keypoint_count/_by_name/_at`,
`lynx_pose_group_count/_at`, `lynx_pose_edge_count/_edges`,
`lynx_part(c, name, err)`→`lynx_part_t*` (borrowed).

## Streaming & tracking

`lynx_stream_open(h, opts, err)`→owned `lynx_stream_t*`;
`lynx_stream_process(s, frame, err)` / `lynx_stream_submit(s, frame)` /
`lynx_stream_process_next(s, err)`; `lynx_stream_close`; `lynx_plan_opts`.

Track accessors (stream results):

| Accessor | Notes |
|---|---|
| `_track_id(r,i)` | 0 = untracked |
| `_track_state` | |
| `_track_age` | |
| `_track_count` | |
| `_track_at(r,k,out)` | → `lynx_track_t` |
| `_detection_track(r,i,out)` | |

Temporal: `_behavior`/`_respiration`/`_pulse`, and
`lynx_track_value(s, track_id, part, attr, when, &ok)` (`part` NULL = detection root).

## Camera / video / overlay

| Function | Notes |
|---|---|
| `lynx_camera_open/_read/_actual_format/_close` | read pixels borrowed until next read |
| `lynx_video_writer_open/_write/_frames/_finish/_close` | MJPEG/AVI, quality 1..100 |
| `lynx_overlay_render(frame, r, opts, out_pixels)` | |
| `lynx_depth_normalize_size` / `lynx_depth_normalize_u8` | displayable depth, closer = brighter |
| `lynx_submit_feedback(h, fb)` | |

## Depth decimation

`lynx_depth_gate_create(opts)/_free/_reset/_stats` — opt-in temporal depth reuse
for depth-emitting models on ONE camera/stream. Pass the gate per call via
`lynx_infer_opts_t.depth_gate` (NULL = off). While the model's native depth grid
matches the gate's keyframe (per-cell relative threshold + changed-cell fraction,
`lynx_depth_gate_opts_t`), results share the keyframe's depth payload, so the
dense source-resolution map behind `lynx_frame_result_depth_map` is realized once
per scene change instead of once per frame. Detection is never decimated;
`max_age` (default 30) bounds staleness.

## Enums (selected)

- **Tasks** (`uint32_t` bits):

| Task | Value |
|---|---|
| `LYNX_TASK_BOUNDING_BOX` | `1<<0` |
| `ORIENTED_BOUNDING_BOX` | `1<<1` |
| `SEGMENTATION` | `1<<2` |
| `DEPTH` | `1<<3` |
| `POSE` | `1<<4` |
| `CLASSIFICATION` | `1<<5` |
| `REID` | `1<<6` |
| `TEXT_RECOGNITION` | `1<<7` |

- `lynx_conf_mode_t`:

| Value | Int |
|---|---|
| `CALIBRATED_BALANCED` | 0 |
| `CALIBRATED_MAX_RECALL` | 1 |
| `CALIBRATED_MAX_PRECISION` | 2 |
| `NON_CALIBRATED` | 3 |

- `lynx_nms_mode_t`: `AUTO/ON/OFF`. `lynx_provider_t`: `CPU/CUDA/TENSORRT/COREML`.
- `lynx_size_category_t`: `AUTO/PICO/NANO/MEDIUM/LARGE`. `lynx_goal_t`: `BALANCED/LATENCY/THROUGHPUT`.
- `lynx_track_state_t`: `NEW/TENTATIVE/CONFIRMED/LOST`. `lynx_license_status_t`: `VALID/EXPIRED/UNKNOWN`.
- `lynx_frame_kind_t`: `PATH/BYTES/PIXELS`. `lynx_channel_order_t`: `AUTO/RGB/BGR`.

See `lynx/core/include/lynx.h` for the full set (28 enums, 30+ structs, 101 functions) and exact field-level docs.
