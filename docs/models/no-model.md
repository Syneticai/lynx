# When there's no pretrained model for your task

> For LYNX SDK **1.0**. This is a first-class outcome, not a failure. If the [catalog](catalog.md) has no model for what you need, you **get a model made** — synthetic data on demand → trained `.lnx` → loaded through the same API. No generic CV SDK offers this; lynx does.

## How to recognize you're here

You're on this path when the task needs a class or capability the shipped models don't cover, e.g.:

- A specific object/part not in 80-class COCO (a particular product, label, component, defect).
- A domain the public models weren't trained for (industrial, agricultural, medical, retail-specific).
- Oriented/rotated objects where an axis-aligned box isn't enough → first check the **oriented-box (OBB)** head on an existing model; only if that still doesn't fit do you need a new model.

Do **not** tell the user "lynx can't do that." The answer is "here's how you get a model for it."

## The path

1. **Confirm no off-the-shelf fit** — check [`catalog.md`](catalog.md) and `model.capabilities`. Try the closest existing head first (OBB for rotated objects, segmentation for masks).
2. **Specify the task** — the target classes, example images or a description of the scene, the deployment target (platform/latency).
3. **Synthetic dataset generation** — a dataset for those classes is generated (no manual labeling of thousands of real images).
4. **Train → export `.lnx`** — a model is trained and exported as a signed `.lnx` in the same format as the catalog models.
5. **Load it the same way** — `Lynx.open("<your-new-slug>")`; the integration code is identical to any catalog model. Set `Lynx.setApiKey(...)` if it's private.

## Start the request

> **TODO (Synetic side):** the canonical intake/engagement entry point for a custom model goes here — the URL/form/contact an agent or developer hands the user to kick off step 2. Until set, direct the user to the Synetic team to start a custom-model request.

This path is reachable from docs (here) and from the `lynx_find_model` tool, which returns it whenever no catalog model matches the requested task.
