# PressFrame v1 Design

Date: 2026-11-11. Source: `plan.md` plus decisions made with Dewdew in the brainstorming session. Where this file and `plan.md` disagree, this file wins.

## Goal

One Flutter app (Android + Windows) for school publication photographers. Fix color and light, add the publication's branding, export a whole event in one pass. Offline, no account, zero cost.

Success means:
- The exported photo looks the same as the preview.
- A 200-photo event exports without crashing on a mid-range Android phone or a laptop with integrated graphics.
- The laptop and phone layouts each feel made for their screen.

## Decisions

| Topic | Decision |
|---|---|
| Input formats | JPEG, PNG, and RAW (CR3, CR2, ARW) through the embedded JPEG inside the RAW file |
| Output format | JPEG only |
| Main device | Laptop first. Windows layout built and tested first, phone second, same features |
| Engine | One GPU fragment shader used for both live preview and full-size export |
| Branding | Built-in template maker (gradient + logos), or an imported transparent PNG frame |
| Output shape | Selectable per batch: Original, 1:1, 4:5, 3:2, 16:9 (and 2:3, 9:16 for portrait) |
| State | Plain Flutter `ChangeNotifier`, no state library |
| Storage | JSON files and PNGs in the app folder. No database, no backend |

## Features

### Import
- Pick many files, pick a folder, or drag and drop onto the window (Windows).
- Unreadable files are skipped and listed when import ends.
- RAW files show a small "RAW" badge. A RAW whose embedded JPEG is under 2000 px on the long edge shows a warning badge, and the export screen repeats the warning.

### Pick / reject
- Each photo has a flag: pick, none, or reject.
- Filmstrip and grid filter: All, Picks, Hide rejects (default).
- Rejected photos are never exported. Nothing is deleted from disk.
- Keys on laptop: `P` pick, `X` reject, `U` clear. Phone: swipe up on the photo to pick, down to reject, and flag buttons in the top bar.

### Editing
- Light: exposure, contrast, shadows, highlights, whites, blacks.
- Color: temperature, saturation, tint, vibrance.
- Detail: sharpen, texture, clarity.
- Every slider is always visible; there is no "More controls" row (removed 2026-11-13).
- On screen, exposure is labelled "Brightness" and temperature "Warmth". Values show as whole numbers from -100 to 100; Brightness keeps 2 decimals.
- Crop, rotate 90, straighten.
- Before/after, reset, undo/redo per photo. Undo shows no toast (removed 2026-11-13); Redo is the button or Ctrl+Y.
- Copy edit / paste edit, and Apply to all (non-rejected photos).

### Presets
- Save the current sliders as a named preset. Crop is not part of a preset.
- Built-in starters: Indoor gym, Outdoor sun, Stage lights.
- Export / import one preset as a `.pfpreset` file (JSON).

### Branding
A **template** is what gets drawn on top of every photo. Two kinds:

**1. Built template (made in the app).** Modeled on what Philippine school publications post: a color gradient band plus the school and publication logos.
- Gradient band: edge (bottom, top, or both), height (% of photo), start color, end color (runs along the band), opacity. The band always fades to transparent toward the photo.
- Logos: one or more PNGs. Each has position (drag it, snaps to corners, edges and center), size (% of photo width), and opacity.
- Because it is drawn, not a fixed image, a built template works on every output shape.

**Photo credit (optional, off by default).** A switch in the Template panel. When on: one text field (e.g. "Photo by Juan Dela Cruz"), corner, size, and white or black text. Applied to every photo in the batch, with per-photo text override in Review for events with several photographers. Works with both template kinds. The credit text is per batch and is not saved in the kit; its corner, size and color are.

**2. Imported frame.** A full-size transparent PNG made in Canva or Photoshop. Its shape is fixed; it is offered only for the matching output shape.

Either kind crops the photo to the output shape. Center crop by default, adjustable per photo. If the batch has both landscape and portrait photos, the user picks a landscape shape and a portrait shape; each photo uses the one matching its orientation, with per-photo override.

### Publication kit
- Kit = templates + logos + presets.
- Export / import as one `.pfkit` file (a zip) so the whole staff shares one look.

### Review
- Grid of every non-rejected photo with its edit and template applied.
- Tap a photo to tweak its edit, crop position, or template.

### Export
- JPEG quality slider, filename pattern (`EventName_001.jpg`), output folder. Photos always export at their own size after the crop; the long-edge field and Full size switch were removed (2026-11-13).
- Windows: the output folder defaults to Downloads, "Change…" picks another, and "Make a new folder named after the event" (on by default) exports into a subfolder with the sanitized event name.
- Progress bar, cancel, and a list of failures. One failure does not stop the batch.
- Originals are never modified. Edit and template are applied in one render, so the photo is compressed once.

### Not in v1
Auto fix (removed in the UI review of 2026-11-12), true RAW decoding, captions or any text other than the photo credit, custom fonts, curves, HSL, masks, healing, PNG/TIFF export, accounts, cloud, iOS.

## Layout

Lightroom's layout patterns with PressFrame's own look. Dark neutral gray surfaces so photo colors read true; one accent color for the active control; no decoration around the photo. Revised on 2026-11-12 from the UI review; the agreed list is `docs/ui-changes.md` and the drawn reference is https://claude.ai/artifact/SRvtnEnsBY615NuqLhJiG7 (private).

### Laptop (width 900 px and up)

```
┌───────────────────────────────────────────────────────┐
│ PressFrame  Import   1 Edit › 2 Review › 3 Export   ⋮ │
├─────────────────────────────────────┬─────────────────┤
│              [Before/After] [↶ ↷ ⟲] │ Presets      ⋮  │
│           photo preview             │ Light           │
│                                     │ Color           │
│                                     │ Detail          │
│                                     │ Crop            │
│                                     │ Template        │
├─────────────────────────────────────┴─────────────────┤
│ ▢ ▢ ▣ ▢ ▢ ▢  filmstrip          3 / 24 [Next: Review →]│
└───────────────────────────────────────────────────────┘
```

- Step bar shows progress with the current step highlighted in bold and accent color, never underlined. One main button bottom right: "Next: Review →" on Edit, "Export all" on Review.
- "⋮ More" in the top bar: Kit (Export kit, Import kit), Filter, Apply to all.
- Undo, Redo, Reset sit in a small pill at the top right of the photo, next to a Before/After button.
- "⋮" next to Save current in Presets: Import preset, and export or delete a saved preset. That row is hidden until "Preset options" under the chips is opened (laptop and phone).
- Right panel, 320 px, collapsible sections (Presets, Crop and Template start minimized), scrolls on short screens.
- Keys: left/right = previous/next photo, `\` = before/after, Ctrl+Z / Ctrl+Y, Ctrl+C / Ctrl+V = copy/paste edit, `P` `X` `U` = flags.
- Double-click a slider resets it. Photo hint: "Scroll to zoom, drag to move."
- Every control is reachable by Tab and has a visible focus ring. Every icon has a tooltip.

### Phone (under 900 px)

```
┌──────────────────────┐
│ ←   3 / 48  ⚑ ⋮ [Next →]│
│                      │
│        photo         │
│                      │
│ ▢ ▢ ▣ ▢ ▢  filmstrip │
│ (Indoor gym)(Outdoor sun)… │
│ Brightness      0.40 │
│ ─────▲────────────── │
│ Light  Color  Crop  Template │
└──────────────────────┘
```

- Four tabs: Light, Color, Crop, Template. Preset chips sit at the top of the Light tab. The Detail sliders are a section at the bottom of the Light tab.
- "Next →" pill in the top bar moves to Review, then Export. The ⋮ menu has Import, Kit, Filter, Apply to all.
- A Before/After button sits at the top right of the photo; holding the photo also shows before. Pinch to zoom. Double-tap a slider to reset.
- Touch targets at least 48 px; tabs at least 44 px tall; tab text 14 px. Sliders have text labels and values for screen readers.
- Portrait orientation only in v1.

### Both

- Slider look: label on the left, small value box on the right, thin track with a triangle marker below it. Warmth track runs blue to yellow, Tint green to magenta.
- Hint text `#A8A8A8` on `#2A2A2A`. Smallest text 12 px.
- First run with no photos: a big "Add photos" drop area, with a one-line drop hint on the laptop and no other text.

One set of shared widgets (preview, slider group, filmstrip, template editor) inside two shells chosen by a `LayoutBuilder` at 900 px.

## Architecture

```
lib/
  engine/
    adjust.frag        shader: light, color, sharpen
    renderer.dart      render(photo, edit, crop, template, size) -> ui.Image
    decode.dart        file -> ui.Image, EXIF rotation, RAW embedded JPEG
  models/              EditParams, Preset, Template, Kit, BatchItem
  export/exporter.dart queue
  storage/             presets, kits, app folder
  ui/
    shared/            preview, slider group, filmstrip, template editor
    desktop_shell.dart
    phone_shell.dart
```

| Unit | Does | Depends on |
|---|---|---|
| `adjust.frag` | Per-pixel adjustment math | nothing |
| `renderer` | Runs the shader, then draws crop, gradient and logos with `Canvas`. The source is decoded at no more than 8192 px long edge on Windows and 4096 px on Android, and the output never exceeds it, so no tiling is needed | shader, models |
| `decode` | Opens a file at a requested size. For RAW, finds the largest embedded JPEG and decodes that | `image` package for EXIF |
| `models` | Immutable data with `toJson` / `fromJson` | nothing |
| `exporter` | For each photo, one at a time: decode full size, render, encode JPEG in a background isolate, write file. Reports progress, supports cancel, collects failures | renderer, decode |
| `storage` | Reads and writes presets, templates, kits | models, `archive` |

The preview widget and the exporter both call `renderer.render`. That shared call is what keeps preview and export identical.

### Packages
`file_picker` (files and folders, both platforms), `desktop_drop` (drag and drop on Windows), `image` (JPEG encode, EXIF), `archive` (kit zip), `path_provider`, `gal` (saves exports to the Android gallery album "PressFrame"; picking an output folder is Windows only). Nothing else.

### Speed and memory
- Preview renders a downscaled copy: 2048 px long edge on laptop, 1280 px on phone.
- Thumbnails are decoded at 256 px and cached on disk in the app's cache folder.
- Filmstrip and grid build only the visible items.
- Export keeps one full-size photo in memory at a time and frees it before the next.
- Slider changes repaint only the preview, not the panel or filmstrip.
- While a slider is dragged the preview renders at half its long edge; it renders at full preview quality on release.
- Export never blocks the screen and can always be cancelled.

## Errors

| Case | Behavior |
|---|---|
| File can't be opened on import | Skipped, listed at the end of import |
| RAW has no usable embedded JPEG | Treated as unreadable |
| RAW embedded JPEG is small | Warning badge and a warning before export |
| Export of one photo fails | Recorded in the failure list, batch continues |
| Output folder not writable or disk full | Export stops with a clear message, finished files are kept |
| Imported kit or preset is malformed | Rejected with a message, existing data untouched |
| Logo file from a kit is missing | Template shown without it and flagged in Review |
| Android storage permission denied | Explanation screen with a retry button |

## Testing

- **Preview equals export** (build step 1): render the same photo and edit at preview size and at full size, downscale the full-size result, assert the mean pixel difference is under 2 out of 255. Run on the laptop and on a physical Android phone.
- **RAW check** (build step 1): extract the embedded JPEG from real CR3, CR2 and ARW samples and record its pixel size per camera model.
- Unit tests: `EditParams` JSON round trip, crop-to-shape math, filename pattern, kit zip round trip, malformed kit rejected.
- Manual: a 200-photo batch export on the phone, watching memory.

## Build order

1. Engine test: one photo, exposure slider, live preview, full-size export, preview-equals-export test, RAW sample check.
2. Single-photo editor on the laptop shell: all sliders, crop, before/after, undo, export.
3. Batch: import (picker, folder, drag and drop), filmstrip, pick/reject, copy/paste, apply to all.
4. Presets.
5. Templates: built template editor, imported frames, photo credit, output shapes, crop to shape.
6. Review grid and export queue.
7. Publication kit.
8. Phone shell.
9. Polish: empty states, messages, installer, APK, README, demo video.

## Open risk

Some Sony bodies embed only a ~1616 px JPEG in ARW. If the step 1 check shows that for the staff's cameras, those files export small. The fallback is to ask those photographers to shoot RAW+JPEG; true RAW decoding stays out of v1.
