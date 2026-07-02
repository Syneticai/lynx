# OCR — reading text from a frame

## The one thing to know

LYNX does OCR as **detection**: each character is a normal detection whose *class is
the glyph*. `predict(ocr=...)` then groups those glyphs into readable strings and
attaches a typed **`Document`** to the frame. You read text off `frame.document` —
**not** off the raw detections.

```python
import lynx
from lynx import Ocr

m = lynx.open("lynx-ocr-fleet")
frame = m.predict("image.png", ocr=Ocr.AUTO)   # AUTO reads both orientations

doc = frame.document          # a Document, or None if OCR didn't run
print(doc.text)               # the recognized text (horizontal reading)
```

## What you get back — `Document`

`frame.document` is typed (autocompletes; a typo raises instead of silently missing):

| attribute | type | what it is |
|---|---|---|
| `.text` | `str` | the horizontal reading, one string |
| `.vertical_text` | `list[VerticalText]` | vertical (top-to-bottom) columns read left-to-right — e.g. an ID painted **down** the side of a trailer |
| `.blocks` | `list[OcrBlock]` | structured detail: `block.lines[].words[].char` / `.box` / `.score` |
| `.text_all` | `str` | `.text` + all `.vertical_text`, joined — the "just give me every string" shortcut |

```python
print(doc.text)                       # horizontal
for v in doc.vertical_text:           # vertical IDs
    print(v.text, f"({v.score:.2f})")
print(doc.text_all)                   # everything

for block in doc.blocks:              # per-glyph detail
    for line in block.lines:
        print(line.text, [w.char for w in line.words])
```

## Orientation — the common gotcha

A number painted **vertically** (one digit above the next) is *not* in `.text` — the
horizontal reader would turn it into one-character-per-line junk (`"3\n1\n0\n9…"`).
It's in **`.vertical_text`**. `Ocr.AUTO` (the default) reads *both* orientations and
keeps them separate — the vertical glyphs are claimed by the vertical pass and never
pollute `.text`. So for a vertical ID:

```python
frame = m.predict(img, ocr=Ocr.AUTO)
for v in frame.document.vertical_text:
    print("ID:", v.text)              # e.g. "3109044"
```

## `Ocr` modes

| mode | behaviour |
|---|---|
| `Ocr.OFF` (or `False`) | no OCR post-processing; `frame.document` is `None` |
| `Ocr.AUTO` (or `None`, the default) | on **iff** the model declares TEXT; reads both orientations |
| `Ocr.ON` (or `True`) | force on; reads both orientations |
| `Ocr.HORIZONTAL` | force on; horizontal text only |
| `Ocr.VERTICAL` | force on; vertical columns only |

Reading both is cheap: **one** inference, then two groupings over the *same*
detections — there's no second forward pass.

## If you get nothing / garbage

OCR quality is the *model's* recognition, not the SDK grouping. If `.text` and
`.vertical_text` are empty or wrong:

- **Lower the confidence.** Glyph detections are often low-score; try
  `predict(..., conf=0.05)` and inspect `len(frame.detections)`.
- **Check the model actually reads it.** `[m.classes(d.class_id).name for d in
  frame.detections]` — are those real characters at plausible boxes? If every
  detection is sub-0.1 confidence, the model isn't recognizing the input (wrong
  model, or text too small — OCR models are often trained on tight crops, so a
  full frame may need cropping/upscaling first).
- `frame.document` is `None`? OCR didn't run — pass `ocr=Ocr.ON` (the model may not
  declare TEXT, so `AUTO` stayed off).

## Streaming

`track()` / `tracker()` take the same `ocr=` and attach a `Document` to every frame:

```python
for frame in m.track(camera_frames, ocr=Ocr.AUTO):
    if frame.document:
        print(frame.document.text)
```
