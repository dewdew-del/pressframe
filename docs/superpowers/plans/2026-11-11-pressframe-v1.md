# PressFrame v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PressFrame v1: a Flutter app for Windows and Android that edits, brands and batch-exports event photos offline.

**Architecture:** One fragment shader does all color math. One function, `paintJob`, draws shader + crop + template onto a `Canvas`; the live preview and the exporter both call it, which keeps them identical. App state is one `ChangeNotifier` (`Session`); persistence is JSON files and PNGs in the app folder.

**Tech Stack:** Flutter (SDK at `D:\flutter`), Dart, GLSL fragment shader. Packages: `file_picker`, `desktop_drop`, `image`, `archive`, `path_provider`, `gal` (Android gallery save).

**Spec:** `docs/superpowers/specs/2026-11-11-pressframe-design.md`. Read it before any task.

## Global Constraints

- Platforms: Android and Windows only. No iOS, web, macOS, Linux folders.
- Input: JPEG, PNG, RAW (`.cr3`, `.cr2`, `.arw`) via embedded JPEG. Output: JPEG only.
- Originals are never written to, moved or deleted.
- No packages beyond the six listed. No state library, no database, no network calls.
- Layout switch at 900 px width. Laptop right panel 320 px. Touch targets at least 48 px.
- Preview long edge: 2048 px on Windows, 1280 px on Android. Thumbnails: 256 px.
- Source decode cap for export: 8192 px long edge on Windows, 4096 px on Android. Output never exceeds the decoded source.
- Slider ranges: exposure −2..2 (stops); contrast, highlights, shadows, temperature, tint, saturation, vibrance −1..1; sharpen 0..1. Neutral is 0 for all.
- Builds must stay light: test on the physical phone, never the emulator.
- Commits: plain messages, authored by the user only. No AI attribution or trailers of any kind.
- After each task: tell Dewdew which files changed and why, and wait for his OK before the next task.
- Any shortcut with a known limit gets a comment: `// shortcut: <the limit>, <when to upgrade>`.

## Review Focus

1. **RAW embedded JPEG comes out sideways** (orientation is stored in the RAW container, not the embedded JPEG). Expected: portrait RAW shows upright. Pinned in Task 2.
2. **Output folder already has `Event_001.jpg`.** Expected: nothing is overwritten; the new file gets a `-2` suffix. Pinned in Task 6.
3. **Event name contains characters Windows forbids** (`\ / : * ? " < > |`) or is empty. Expected: sanitized name, export still works. Pinned in Task 6.
4. **Imported `.pfkit` has zip entries with `..` or absolute paths.** Expected: kit rejected, nothing written outside the app folder. Pinned in Task 11.
5. **Export cancelled or app closed mid-file.** Expected: no half-written JPEG in the output folder. Pinned in Task 6.

## Amendments (2026-11-12, UI review)

Dewdew reviewed drawn mock-ups and agreed the list in `docs/ui-changes.md`. Read that file. **Where a task below disagrees with this section or that file, this section wins.** The spec is already updated.

**Engine (Tasks 1 and 3).** `EditParams` gains four fields, all −1..1, neutral 0: `whites`, `blacks`, `texture`, `clarity`. Task 1 is already built, so add them there first with tests: round trip includes them, and `fromJson` of a JSON without them gives 0 (old presets stay valid). Shader additions:
```
// with sharpen, before linearizing (ring = mean of 8 taps on a circle)
c += uTexture * 0.6 * (c - ring(4.0  * uTexel))
c += uClarity * 0.5 * (c - ring(24.0 * uTexel)) * (1.0 - abs(2.0*L0 - 1.0))   // L0 = luma of c
// right after the shadows/highlights line
c += uWhites * 0.25 * pow(L, 4.0) + uBlacks * 0.25 * pow(1.0 - L, 4.0)
```
Skip a ring when its slider is 0. Mark the ring blur `// shortcut: 8-tap ring, switch to a two-pass blur if halos show`. Add `whites 0.3, blacks -0.3, texture 0.4, clarity 0.4` to the edit in the `preview equals export` test; if only texture/clarity push it over 2.0, raise the ring to 12 taps, do not raise the threshold.

**Auto fix is removed (Task 4).** Do not create `lib/engine/auto_fix.dart`, `test/auto_fix_test.dart`, the `autoFix` function or the button.

**Laptop shell (Tasks 4, 6, 7, 8, 10).**
- Top bar: Import, step bar `1 Edit › 2 Review › 3 Export` (current step highlighted, steps clickable), `⋮ More` menu holding Kit (Export kit, Import kit), Filter, Apply to all. No separate Edit/Review/Export/Kit buttons.
- Bottom bar: filmstrip, photo counter `3 / 24`, and one main button: `Next: Review →` on Edit, `Export all` on Review (opens the export sheet).
- On the photo, top right: `Before / After` button and a pill with Undo, Redo, Reset. `\` still works.
- Photo hint: "Scroll to zoom, drag to move."
- Presets: `⋮` next to Save current holds Import preset and, per saved preset, Export and Delete.
- Undo shows a toast "Undone. Redo?" whose action redoes. Every icon button has a tooltip.

**Sliders (Task 4, shared widget).** Label left, value box right, thin track with a triangle marker below. Warmth track blue→yellow, Tint green→magenta. Display value = `round(value × 100)`; Brightness shows the raw value with 2 decimals. Labels: `exposure` → "Brightness", `temperature` → "Warmth"; the rest keep their names. Order and grouping:
- Light: Brightness, Contrast, Shadows | More controls: Highlights, Whites, Blacks
- Color: Warmth, Saturation | More controls: Tint, Vibrance
- Detail: Sharpen | More controls: Texture, Clarity

"More controls ▾" is collapsed by default, at least 44 px tall. Task 4's widget test checks: the six visible labels above are found, "Highlights" is not found until "More controls" under Light is tapped, and no "Auto fix" exists.

**Text and color.** Hint text `#A8A8A8` on `#2A2A2A`. Smallest text 12 px.

**Speed (Tasks 4, 7, 6).** While a slider is dragged (`setEdit(commit: false)`), `PreviewView` renders from a copy at half the preview long edge (1024 laptop, 640 phone); on release it renders at full preview size.

**Empty state (Task 7).** With no photos: a large "Add photos" drop area and three lines: "1 Edit one photo", "2 Review the batch", "3 Export all".

**Phone shell (Task 12).** Four bottom tabs: Light, Color, Crop, Template (44 px tall minimum, 14 px text). Preset chips (built-ins then saved, with the `⋮`) at the top of the Light tab; the Detail section sits at the bottom of the Light tab. Top bar: back, `3 / 48`, flag, `⋮` (Import, Kit, Filter, Apply to all), and a `Next →` pill that goes Edit → Review → Export. Task 12's widget test expects exactly these four tabs and, on Color, "Warmth" visible and "Brightness" hidden.

**Not changed:** Import menu, Template section and editor, Crop section, Review grid and side panel, Export sheet fields, keyboard shortcuts.

## File Map

```
lib/
  main.dart                    app entry, theme, shell switch at 900 px
  session.dart                 Session (ChangeNotifier): batch, selection, undo, flags
  models/
    edit_params.dart           EditParams
    template.dart              Template, BuiltTemplate, FrameTemplate, GradientBand, LogoLayer, CreditStyle, OutputShape
    batch_item.dart            BatchItem, Flag
    preset.dart                Preset, builtInPresets
    kit.dart                   Kit
  engine/
    decode.dart                decodeImage, extractEmbeddedJpeg, isRawPath
    geometry.dart              cropForShape, orientedSize
    renderer.dart              Renderer, RenderJob, paintJob
    auto_fix.dart              autoFix
  export/
    filename.dart              sanitizeEventName, exportFileName, uniquePath
    exporter.dart              Exporter, ExportSettings, ExportProgress
  storage/app_store.dart       AppStore: presets, templates, kits, thumbnail cache
  ui/shared/                   preview_view, slider_group, filmstrip, template_editor, crop_view, review_grid, export_sheet
  ui/desktop_shell.dart
  ui/phone_shell.dart
shaders/adjust.frag
test/                          unit tests, one file per lib file
integration_test/engine_test.dart
installer/pressframe.iss
```

---

### Task 1: Project scaffold and models

**Files:**
- Create: Flutter project in repo root, `lib/models/*.dart`, `README.md`, `.gitignore`
- Test: `test/models_test.dart`

**Interfaces — Produces:**
```dart
class EditParams {            // immutable, const EditParams.neutral
  final double exposure, contrast, highlights, shadows,
      temperature, tint, saturation, vibrance, sharpen;
  EditParams copyWith({...}); Map<String, dynamic> toJson();
  factory EditParams.fromJson(Map<String, dynamic>); // missing keys -> 0, values clamped to range
  // value equality
}
enum Flag { none, pick, reject }
enum OutputShape { original, r1x1, r4x5, r3x2, r16x9, r2x3, r9x16 }  // double? get aspect (width/height)
enum BandEdge { top, bottom, both }
enum Corner { topLeft, topRight, bottomLeft, bottomRight }
class GradientBand { BandEdge edge; double heightFraction; int startColor, endColor; double opacity; }
class LogoLayer { String file; double cx, cy, widthFraction, opacity; }   // cx, cy normalized 0..1; file = name inside app folder
sealed class Template { String name; }
class BuiltTemplate extends Template { GradientBand? band; List<LogoLayer> logos; }
class FrameTemplate extends Template { String file; double aspect; }
class CreditStyle { bool enabled /*default false*/; Corner corner; double sizeFraction /*0.025*/; bool white /*true*/; }
class Preset { String name; EditParams params; }
class Kit { String name; List<Preset> presets; List<Template> templates; CreditStyle credit; }
class BatchItem {             // immutable + copyWith
  String path; bool isRaw; int width, height; Flag flag; EditParams edit;
  int quarterTurns; double straighten /*−15..15 deg*/;
  Rect? crop /*normalized, on the rotated photo; null = auto*/;
  String? templateOverride; OutputShape? shapeOverride; String? creditOverride;
}
```
All model classes have `toJson` / `fromJson`; `Template.fromJson` switches on a `"type"` field (`"built"` / `"frame"`).

- [ ] **Step 1:** `git init`. Run `D:\flutter\bin\flutter create --platforms=android,windows --org com.dewdew --project-name pressframe .` Add the six packages with `flutter pub add`. Add `flutter_test` + `integration_test` dev dependencies. Add `test/samples/` to `.gitignore`.
- [ ] **Step 2:** Write `README.md`: name, one-paragraph description from the spec, and near the top `**Live demo:** coming soon (APK and Windows installer will be on GitHub Releases)`.
- [ ] **Step 3: Failing tests** in `test/models_test.dart`:
  - `EditParams.fromJson(p.toJson()) == p` for a params with every field non-zero.
  - `EditParams.fromJson({}) == EditParams.neutral`.
  - `EditParams.fromJson({'exposure': 99}).exposure == 2.0`; `{'sharpen': -1}` gives `0.0`.
  - `OutputShape.r4x5.aspect == 0.8`, `OutputShape.original.aspect == null`.
  - Kit with one preset, one `BuiltTemplate` (band + 2 logos), one `FrameTemplate` survives `Kit.fromJson(jsonDecode(jsonEncode(kit.toJson())))` with equal `toJson`.
  - `CreditStyle().enabled == false`.
- [ ] **Step 4:** Run `flutter test test/models_test.dart`. Expected: FAIL (classes missing).
- [ ] **Step 5:** Implement the models. Run again. Expected: PASS.
- [ ] **Step 6:** Commit: `chore: scaffold project and data models`.

---

### Task 2: Decode and RAW embedded JPEG

**Files:**
- Create: `lib/engine/decode.dart`
- Test: `test/decode_test.dart`

**Interfaces — Produces:**
```dart
bool isRawPath(String path);                         // .cr3 .cr2 .arw, case-insensitive
class DecodeFailure implements Exception { final String path, reason; }
class EmbeddedJpeg { final Uint8List bytes; final int width, height; }
EmbeddedJpeg? extractEmbeddedJpeg(Uint8List raw);    // pure Dart, no dart:ui
int? rawOrientation(Uint8List raw);                  // EXIF orientation 1..8 from the RAW container, null if not found
Future<ui.Image> decodeImage(String path, {required int maxLongEdge}); // upright, long edge <= maxLongEdge, throws DecodeFailure
Future<({int width, int height, bool isRaw, bool smallPreview})> probe(String path); // smallPreview: RAW with long edge < 2000
```

Algorithm for `extractEmbeddedJpeg` (not determined by the signature): scan the bytes for every `FF D8 FF`. From each hit, walk JPEG segments until the first SOF marker. Accept only SOF0 (`FFC0`) and SOF2 (`FFC2`); reject SOF3 (`FFC3`, lossless — that is the RAW sensor data in CR2). Read width and height from the SOF. Keep the candidate with the most pixels. Its bytes run from the SOI to the next `FF D9` that is followed by end of file or a non-JPEG region; passing a slice that runs to end of file is acceptable because decoders stop at EOI.

`rawOrientation`: CR2 and ARW are TIFF containers — read tag `0x0112` from IFD0. CR3: find the `CMT1` box, which holds a TIFF block, and read the same tag.

`decodeImage`: for RAW, extract then decode the JPEG bytes and rotate by `rawOrientation`. For JPEG/PNG use `ui.instantiateImageCodecFromBuffer` with `targetWidth`/`targetHeight`, which already applies EXIF rotation.

- [ ] **Step 1: Failing tests** in `test/decode_test.dart`:
  - `isRawPath('a.CR3')`, `isRawPath('b.arw')` true; `isRawPath('c.jpg')` false.
  - Build synthetic bytes: 100 junk bytes + a small 16×8 JPEG (encode with `package:image`) + junk + a 64×48 JPEG + junk. `extractEmbeddedJpeg` returns width 64, height 48, and `img.decodeJpg(result.bytes)` succeeds.
  - Bytes containing only a fake stream `FF D8 FF C3 ...` (SOF3) return `null`.
  - Empty bytes and 3 random kilobytes return `null`.
  - `decodeImage` on a file holding the first half of a valid JPEG throws `DecodeFailure` (use `testWidgets` + `tester.runAsync`).
  - **Review Focus 1:** for each file in `test/samples/*.{cr3,cr2,arw}` (skip the test with a printed note when the folder is empty): print `name, embedded width×height, rawOrientation`; assert `extractEmbeddedJpeg` is non-null; when `rawOrientation` is 6 or 8, assert decoded `height > width`.
- [ ] **Step 2:** Run `flutter test test/decode_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. Run again. Expected: PASS (sample test skipped or passing).
- [ ] **Step 4:** Ask Dewdew for 2–3 real CR3 and ARW files, put them in `test/samples/`, re-run, and record the printed sizes in the spec's "Open risk" section.
- [ ] **Step 5:** Commit: `feat: image decode with RAW embedded JPEG`.

---

### Task 3: Shader and renderer (engine gate)

**Files:**
- Create: `shaders/adjust.frag`, `lib/engine/renderer.dart`, `lib/engine/geometry.dart`
- Modify: `pubspec.yaml` (`flutter: shaders: [shaders/adjust.frag]`)
- Test: `test/geometry_test.dart`, `integration_test/engine_test.dart`

**Interfaces:**
- Consumes: `EditParams`, `Template`, `CreditStyle` (Task 1).
- Produces:
```dart
Size orientedSize(int width, int height, int quarterTurns);
Rect cropForShape(Size oriented, double? aspect, Rect? userCrop);
  // normalized Rect. aspect null -> userCrop ?? full. Otherwise the largest rect of that aspect
  // that fits inside (userCrop ?? full), centered on its center, clamped to 0..1.
class RenderJob {
  final ui.Image source; final EditParams edit;
  final int quarterTurns; final double straighten;
  final Rect crop;                       // normalized, from cropForShape
  final Size outputSize;                 // pixels
  final Template? template; final Map<String, ui.Image> assets;  // keyed by LogoLayer.file / FrameTemplate.file
  final String? creditText; final CreditStyle credit;
}
class Renderer {
  static Future<Renderer> load();        // loads the FragmentProgram once
  void paintJob(Canvas canvas, RenderJob job);          // draws into (0,0)-(outputSize)
  Future<ui.Image> render(RenderJob job);               // PictureRecorder -> toImage(outputSize)
  Future<Uint8List> renderRgba(RenderJob job);          // render -> toByteData(rawRgba), disposes the image
}
```
In this task `paintJob` draws rotation, straighten, crop and the shader only; template and credit are added in Task 9 and are ignored when null.

Shader math, in this exact order (uniforms: `uSize`, `uTexel`, the nine sliders, `sampler2D uTex`):
```
c  = texture(uTex, uv).rgb
c += uSharpen * (4.0*c - n - s - e - w)            // neighbors at +-uTexel
lin = pow(max(c,0.0), vec3(2.2)) * exp2(uExposure)
lin.r *= 1.0 + 0.25*uTemp;  lin.b *= 1.0 - 0.25*uTemp;  lin.g *= 1.0 - 0.25*uTint
c  = pow(lin, vec3(1.0/2.2))
L  = dot(c, vec3(0.2126, 0.7152, 0.0722))
c += uShadows * 0.35 * (1.0-L)*(1.0-L) + uHighlights * 0.35 * L*L
c  = (c - 0.5) * (1.0 + uContrast) + 0.5
L  = dot(c, vec3(0.2126, 0.7152, 0.0722))
c  = mix(vec3(L), c, 1.0 + uSaturation)
sat = max(c.r,max(c.g,c.b)) - min(c.r,min(c.g,c.b))
c  = mix(vec3(L), c, 1.0 + uVibrance * (1.0 - sat))
out = clamp(c, 0.0, 1.0), alpha 1
```
`uTexel` = `(outputLongEdge / 2048.0) / sourceSizeInPixels`, so sharpening looks the same at preview and export size.

- [ ] **Step 1: Failing tests** in `test/geometry_test.dart`:
  - `orientedSize(6000, 4000, 1) == Size(4000, 6000)`.
  - `cropForShape(Size(6000,4000), null, null) == Rect.fromLTWH(0,0,1,1)`.
  - `cropForShape(Size(6000,4000), 1.0, null)` is `LTWH(1/6, 0, 2/3, 1)` within 1e-9.
  - `cropForShape(Size(4000,6000), 0.8, null)` has full width and height fraction `5000/6000`, centered.
  - With `userCrop = LTWH(0.5, 0.5, 0.5, 0.5)` and aspect 16/9 on 6000×4000, the result lies inside the user crop and its pixel aspect is 16/9 within 1e-6.
- [ ] **Step 2:** Run `flutter test test/geometry_test.dart`. Expected: FAIL. Implement `geometry.dart`. Expected: PASS.
- [ ] **Step 3: Failing integration test** in `integration_test/engine_test.dart`. Build a synthetic 3000×2000 `ui.Image` (smooth RGB gradients plus a few hard-edged blocks, drawn with `Canvas`).
  - `neutral edit is identity`: render at 3000×2000 with `EditParams.neutral`; mean absolute difference from the source is under 1.0 (0–255 scale).
  - `preview equals export`: edit = exposure 0.7, contrast 0.3, highlights −0.4, shadows 0.4, temperature 0.3, tint −0.2, saturation 0.2, vibrance 0.3, sharpen 0.5. Render A at 768×512 from the source downscaled to 768×512. Render B at 3000×2000 from the full source, then downscale B to 768×512 with `FilterQuality.medium`. Mean absolute difference A vs B is under 2.0.
  - `exposure brightens`: exposure 1.0 raises mean luma versus neutral.
- [ ] **Step 4:** Run `flutter test integration_test/engine_test.dart -d windows`. Expected: FAIL. Write the shader and `Renderer`. Expected: PASS.
- [ ] **Step 5:** Run the same test on the physical phone: `flutter test integration_test/engine_test.dart -d <device id from flutter devices>`. Expected: PASS.
- [ ] **Step 6: Gate.** If Step 5 fails or the phone cannot run the shader, stop and report to Dewdew with the output. Do not start Task 4.
- [ ] **Step 7:** Commit: `feat: adjustment shader and renderer`.

---

### Task 4: Session, laptop shell, single-photo editor, auto fix

**Files:**
- Create: `lib/session.dart`, `lib/engine/auto_fix.dart`, `lib/ui/shared/preview_view.dart`, `lib/ui/shared/slider_group.dart`, `lib/ui/desktop_shell.dart`
- Modify: `lib/main.dart`
- Test: `test/session_test.dart`, `test/auto_fix_test.dart`, `test/desktop_shell_test.dart`

**Interfaces:**
- Consumes: `decodeImage`, `probe`, `Renderer`, `RenderJob`, `cropForShape`, models.
- Produces:
```dart
EditParams autoFix(Uint8List rgba, int width, int height, EditParams current);
  // sets exposure, contrast, temperature, tint; other fields copied from current
enum FlagFilter { all, picks, hideRejects }
class Session extends ChangeNotifier {
  List<BatchItem> get items; int get selectedIndex; BatchItem? get selected;
  FlagFilter filter = FlagFilter.hideRejects;
  List<int> get visibleIndexes; List<BatchItem> get exportable;        // flag != reject
  String? landscapeTemplate, portraitTemplate;                          // Template.name
  OutputShape landscapeShape = OutputShape.original, portraitShape = OutputShape.original;
  String creditText = ''; CreditStyle credit;
  void addItems(List<BatchItem> items);  void select(int index);
  void setEdit(EditParams e, {required bool commit});   // commit=false while dragging, true on release
  void updateSelected(BatchItem Function(BatchItem) change);  // commits one undo step
  void undo(); void redo(); bool get canUndo, canRedo;         // per photo
  void resetEdit(); void setFlag(Flag f);
  void copyEdit(); void pasteEdit(); void applyEditToAll();    // exportable items only; crop is not copied
}
```
`autoFix` values: compute mean R, G, B and gamma luma, and the 1st and 99th luma percentiles. `exposure = clamp(log2(0.45 / meanLuma), −1.5, 1.5)`. `contrast = clamp(0.9 − (p99 − p1), 0, 0.5)`. `temperature = clamp(2·(meanB − meanR)/(meanB + meanR), −0.5, 0.5)`. `tint = clamp(2·(meanG − (meanR+meanB)/2)/meanG, −0.5, 0.5)`.

UI: dark theme (surface `#1E1E1E`, panel `#2A2A2A`, text `#E6E6E6`, accent `#4C9FFF`). Top bar with Import · Edit · Review · Export and a Kit menu (Review, Export and Kit are disabled placeholders until their tasks). Right panel 320 px with collapsible sections Presets, Light, Color, Detail, Crop, Template; this task fills Light, Color, Detail and an Auto fix button. `PreviewView` holds the source decoded at the preview long edge and repaints with `Renderer.paintJob` inside a `CustomPainter` wrapped in a `RepaintBoundary`; it listens to `Session` so a slider drag repaints only the preview. Keys: `\` held = before, Ctrl+Z, Ctrl+Y, Ctrl+C, Ctrl+V, left/right. Double-click a slider resets it. Wheel zooms, drag pans. Every slider has a text label, a numeric value and a `Semantics` label.

- [ ] **Step 1: Failing tests** `test/auto_fix_test.dart` (solid-color RGBA buffers):
  - all pixels (30,30,30): `exposure > 0.5`.
  - all pixels (230,230,230): `exposure < −0.3`.
  - all pixels (125,125,125): `|temperature| < 0.01` and `|tint| < 0.01`.
  - all pixels (90,110,160): `temperature > 0.2`.
  - `current.saturation = 0.4` is preserved in the result.
- [ ] **Step 2: Failing tests** `test/session_test.dart`:
  - three `setEdit(commit:false)` then one `commit:true` produce exactly one undo step; `undo()` restores the edit before the drag.
  - `undo` on photo 0 does not change photo 1.
  - `redo` after `undo` restores; a new commit clears redo.
  - `applyEditToAll` copies `edit` to non-rejected items and leaves `crop` and rejected items unchanged.
  - with `hideRejects`, `visibleIndexes` omits rejected items; `exportable` omits them under every filter.
  - `pasteEdit` with nothing copied is a no-op.
- [ ] **Step 3:** Run both. Expected: FAIL. Implement `auto_fix.dart` and `session.dart`. Expected: PASS.
- [ ] **Step 4: Failing widget test** `test/desktop_shell_test.dart` at 1280×800 with a `Session` holding one item and a stub preview: finds sliders labelled Exposure, Contrast, Highlights, Shadows, Temperature, Tint, Saturation, Vibrance, Sharpen; dragging Exposure changes `session.selected.edit.exposure`; double-tap on it returns it to 0; Ctrl+Z undoes.
- [ ] **Step 5:** Build the shell and widgets. Run `flutter test`. Expected: PASS.
- [ ] **Step 6:** Manual check: `flutter run -d windows`, open one JPEG through a temporary single-file picker on Import, drag every slider, hold `\`, Auto fix, undo. Sliders must feel instant on the Ryzen laptop.
- [ ] **Step 7:** Commit: `feat: laptop editor with sliders, undo and auto fix`.

---

### Task 5: Crop, rotate, straighten

**Files:**
- Create: `lib/ui/shared/crop_view.dart`
- Modify: `lib/ui/desktop_shell.dart` (Crop section), `lib/engine/renderer.dart` if straighten needs inset
- Test: `test/geometry_test.dart` (extend), `test/crop_view_test.dart`

**Interfaces:**
- Consumes: `Session.updateSelected`, `cropForShape`.
- Produces: `Rect insetForStraighten(Size oriented, double degrees)` in `geometry.dart` — the largest centered normalized rect with the photo's aspect that contains no empty corners after rotating by `degrees`.

Crop section: Rotate left, Rotate right, Straighten slider (−15..15), Reset crop. `CropView` shows the whole rotated photo with a draggable, resizable rect; when the active output shape has an aspect, the rect is locked to it.

- [ ] **Step 1: Failing tests:** `insetForStraighten(size, 0)` is the full rect; at 10° on 6000×4000 the rect is centered, has aspect 1.5, and every corner rotated back by −10° lies inside the photo; the area at 15° is smaller than at 5°.
- [ ] **Step 2: Failing widget test:** tapping Rotate right changes `quarterTurns` from 0 to 1 and resets `crop` to null; dragging the crop rect by (40, 0) moves `crop.left` right; one undo restores the previous crop.
- [ ] **Step 3:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 4:** Commit: `feat: crop, rotate and straighten`.

---

### Task 6: Exporter

**Files:**
- Create: `lib/export/filename.dart`, `lib/export/exporter.dart`, `lib/ui/shared/export_sheet.dart`
- Modify: `lib/ui/desktop_shell.dart` (enable Export)
- Test: `test/filename_test.dart`, `integration_test/export_test.dart`

**Interfaces:**
- Consumes: `decodeImage`, `Renderer.renderRgba`, `cropForShape`, `Session.exportable`.
- Produces:
```dart
String sanitizeEventName(String name);   // strips \ / : * ? " < > | and control chars, trims dots/spaces, empty -> 'Event'
String exportFileName(String eventName, int index /*1-based*/, int total); // 'Name_001.jpg', pad = max(3, digits of total)
String uniquePath(String dir, String fileName, bool Function(String) exists); // 'a.jpg' -> 'a-2.jpg' -> 'a-3.jpg'
class ExportSettings { String eventName; int quality /*90, 60..100*/; int? longEdge /*2048; null = full*/; String outDir; }
class ExportProgress { final int done, total; final List<({String path, String reason})> failures; final bool finished, cancelled; }
class Exporter {
  Exporter(this.renderer, {required this.maxDecodeEdge});
  Stream<ExportProgress> run(List<RenderSpec> items, ExportSettings s);
  void cancel();
}
typedef RenderSpec = ({BatchItem item, OutputShape shape, Template? template, String? creditText, CreditStyle credit});
```
Per photo, one at a time: decode at `min(maxDecodeEdge, needed)` where `needed = longEdge / min(crop.width, crop.height)` rounded up (or the cap when `longEdge` is null); render; `Isolate.run(() => img.encodeJpg(...))`; write to `<final>.part`; rename to the final name; dispose images before the next photo. A failure is recorded and the loop continues. If the output folder is not writable or the disk is full, stop and emit `finished` with a failure whose reason says so. On Android, write into the app's temp folder and hand each finished file to `Gal.putImage(path, album: 'PressFrame')` (check the `gal` README for the current call); `outDir` and the folder picker are Windows only.

- [ ] **Step 1: Failing tests** `test/filename_test.dart`:
  - `exportFileName('Intrams', 1, 48) == 'Intrams_001.jpg'`; `exportFileName('Intrams', 12, 1500) == 'Intrams_0012.jpg'`.
  - **Review Focus 3:** `sanitizeEventName('Intrams: Day 1/2?') == 'Intrams Day 12'`; `sanitizeEventName('  ..  ') == 'Event'`; `sanitizeEventName('') == 'Event'`.
  - **Review Focus 2:** with `exists` true for `a.jpg` and `a-2.jpg`, `uniquePath(dir, 'a.jpg', exists)` ends with `a-3.jpg`.
- [ ] **Step 2: Failing integration test** `integration_test/export_test.dart` (temp dirs, synthetic 1200×800 JPEGs written with `package:image`):
  - 3 good files + 1 file of random bytes, `longEdge: 600`: 3 JPEGs exist, each decodes with long edge 600; `failures.length == 1`; the last event has `finished == true`.
  - source files' bytes are identical before and after.
  - **Review Focus 2:** running the same export twice into one folder leaves 6 files, none overwritten.
  - **Review Focus 5:** call `cancel()` on the first progress event of a 5-file run: last event has `cancelled == true`, the folder holds no `.part` file, and every `.jpg` present decodes.
  - `outDir` pointing at a path that is a file, not a folder: the stream finishes with a failure and does not throw.
- [ ] **Step 3:** Run `flutter test test/filename_test.dart` and `flutter test integration_test/export_test.dart -d windows`. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 4:** Build `ExportSheet`: event name, quality slider, long-edge field with a "Full size" switch, folder picker (Windows), progress bar, Cancel, failure list, warning line when any exportable RAW has `smallPreview`.
- [ ] **Step 5:** Commit: `feat: export queue`.

---

### Task 7: Batch import, filmstrip, flags

**Files:**
- Create: `lib/ui/shared/filmstrip.dart`, `lib/storage/app_store.dart` (thumbnail cache part)
- Modify: `lib/ui/desktop_shell.dart`, `lib/session.dart` (import helper)
- Test: `test/import_test.dart`, `test/filmstrip_test.dart`

**Interfaces:**
- Consumes: `probe`, `decodeImage`, `Session`.
- Produces:
```dart
bool isSupportedPath(String path);   // jpg jpeg png cr3 cr2 arw
Future<({List<BatchItem> items, List<String> skipped})> importPaths(List<String> paths);
  // expands folders one level, ignores unsupported extensions, drops paths already in the batch,
  // probes each file; unreadable ones go to skipped
class AppStore {
  static Future<AppStore> open();            // path_provider app support + cache dirs
  Future<ui.Image> thumbnail(String path);   // 256 px, cached on disk keyed by path + size + modified time
}
```
Import replaces Task 4's temporary picker: Add photos (multi-pick), Add folder, and a `DropTarget` over the whole window. After import, show a dialog listing skipped files when there are any. Filmstrip: horizontal `ListView.builder`, thumbnail, selected ring, flag dot, RAW badge, warning badge for `smallPreview`. Filter menu: All, Picks, Hide rejects. Keys `P`, `X`, `U`. Buttons Apply to all and Export all in the bottom bar. Empty state: "Drop photos here or click Add photos".

- [ ] **Step 1: Failing tests** `test/import_test.dart`: a temp folder with 2 JPEGs, 1 PNG, 1 `.txt`, 1 corrupt `.jpg` gives 3 items and `skipped` containing only the corrupt file; passing the same path twice gives one item; `isSupportedPath('x.ARW')` is true.
- [ ] **Step 2: Failing widget test** `test/filmstrip_test.dart`: with 3 items and item 1 rejected under `hideRejects`, 2 tiles are shown; pressing `X` on the selected item hides it and selects the next visible one; pressing right arrow moves selection.
- [ ] **Step 3:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 4:** Manual check on the laptop: drop a folder of 200 photos; scrolling the filmstrip stays smooth and memory stays flat.
- [ ] **Step 5:** Commit: `feat: batch import, filmstrip and pick/reject`.

---

### Task 8: Presets

**Files:**
- Modify: `lib/storage/app_store.dart`, `lib/models/preset.dart`, `lib/ui/desktop_shell.dart` (Presets section)
- Test: `test/presets_test.dart`

**Interfaces — Produces:**
```dart
const List<Preset> builtInPresets;   // 'Indoor gym', 'Outdoor sun', 'Stage lights'
// AppStore additions:
Future<List<Preset>> loadPresets();             // user presets from presets.json
Future<void> savePreset(Preset p);              // replaces one with the same name
Future<void> deletePreset(String name);
Future<void> exportPreset(Preset p, String filePath);   // .pfpreset JSON: {"pressframe":"preset","version":1,"name":..,"params":{..}}
Future<Preset> importPreset(String filePath);   // throws FormatException on bad file
```
Built-in values: Indoor gym — exposure 0.5, shadows 0.3, temperature −0.15, tint 0.05, vibrance 0.2, sharpen 0.3. Outdoor sun — exposure −0.2, highlights −0.5, shadows 0.3, contrast 0.1, vibrance 0.15. Stage lights — exposure 0.3, highlights −0.6, shadows 0.4, contrast 0.15, saturation −0.1, sharpen 0.2. Tune by eye in the manual check and update this list.

Presets section: grid of preset names (built-ins first), tap applies as one undo step, Save current, and a menu per user preset with Export and Delete. Built-ins cannot be deleted.

- [ ] **Step 1: Failing tests** (AppStore opened on a temp dir): save then load returns the preset; saving the same name twice keeps one; export then import round-trips; importing `{"foo":1}`, a non-JSON file, or a file over 1 MB throws `FormatException` and leaves `loadPresets()` unchanged; `builtInPresets.length == 3`.
- [ ] **Step 2:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 3:** Commit: `feat: presets`.

---

### Task 9: Templates, output shapes, photo credit

**Files:**
- Create: `lib/ui/shared/template_editor.dart`
- Modify: `lib/engine/renderer.dart` (overlay), `lib/storage/app_store.dart`, `lib/session.dart`, `lib/ui/desktop_shell.dart` (Template section)
- Test: `test/template_store_test.dart`, `integration_test/template_test.dart`, `test/session_test.dart` (extend)

**Interfaces:**
- Consumes: `Template` models, `RenderJob`, `cropForShape`.
- Produces:
```dart
// AppStore additions:
Future<List<Template>> loadTemplates();  Future<void> saveTemplate(Template t);  Future<void> deleteTemplate(String name);
Future<String> importAsset(String pngPath);   // copies into assets/ under a content-hash name, returns that name; throws FormatException if not a PNG
Future<ui.Image> asset(String file);
// Session additions:
OutputShape shapeFor(BatchItem item);      // shapeOverride ?? (landscape or portrait shape by oriented size; square counts as landscape)
String? templateFor(BatchItem item);       // templateOverride ?? landscape/portrait template
RenderSpec specFor(BatchItem item, List<Template> templates);
```
`paintJob` overlay order after the photo: gradient band(s), then logos in list order, or the frame PNG stretched to `outputSize`; then credit text. Band: a rect of `heightFraction × height` on the chosen edge; fill is a horizontal `LinearGradient` from `startColor` to `endColor`, masked by a vertical alpha ramp from `opacity` at the photo edge to 0 at the band's inner side. Logo: width = `widthFraction × output width`, aspect kept, centered at `(cx, cy)`. Credit: only when `credit.enabled` and the text is non-empty; font size `sizeFraction × output short edge`; white or black with a soft shadow of the opposite color; inset `0.02 × short edge` from the chosen corner. A `FrameTemplate` is listed only for a shape whose aspect matches its own within 0.01.

Template section: template picker for landscape and for portrait, shape picker for each, New template, Import frame PNG, credit switch (off by default) with text field, corner, size, white/black. `TemplateEditor`: live preview on the selected photo; band controls (edge, height, two color pickers built from hue/saturation/value sliders plus a hex field, opacity); Add logo; drag a logo to move, with snapping within 2% to corners, edge centers and center; size and opacity sliders; delete logo.

- [ ] **Step 1: Failing tests** `test/template_store_test.dart`: save/load round-trips a `BuiltTemplate` and a `FrameTemplate`; `importAsset` of the same PNG twice returns the same name; `importAsset` of a JPEG renamed `.png` throws `FormatException`.
- [ ] **Step 2: Failing tests** in `test/session_test.dart`: a 6000×4000 item uses `landscapeShape`, a 4000×6000 item uses `portraitShape`, and `quarterTurns: 1` flips which one applies; `shapeOverride` wins; `specFor` returns a null template when the chosen `FrameTemplate` does not match the shape.
- [ ] **Step 3: Failing integration test** `integration_test/template_test.dart` on a solid mid-gray 1000×800 source:
  - band bottom, height 0.25, start red, end blue, opacity 1: pixel at (50, 795) is mostly red, (950, 795) mostly blue, (500, 100) still gray, and (500, 610) is closer to gray than (500, 790) is.
  - a solid green 100×50 logo at `cx 0.9, cy 0.1, widthFraction 0.1`: pixel (900, 80) is green, (500, 400) is gray.
  - credit disabled with text set: output equals the no-credit render exactly. Credit enabled, white, bottomRight: the bottom-right 200×60 region has pixels brighter than 240; the top-left region does not.
  - shape `r1x1` on a 1500×1000 source with `longEdge 500`: output is 500×500.
  - a 400×400 frame PNG with an opaque red 20 px border: output corner pixel is red, center is gray.
- [ ] **Step 4:** Run all three. Expected: FAIL. Implement store, session, renderer overlay. Expected: PASS. Re-run `integration_test/engine_test.dart`. Expected: still PASS.
- [ ] **Step 5:** Build the Template section and `TemplateEditor`. Widget test: the credit switch starts off; turning it on reveals the text field.
- [ ] **Step 6:** Commit: `feat: templates, output shapes and photo credit`.

---

### Task 10: Review grid

**Files:**
- Create: `lib/ui/shared/review_grid.dart`
- Modify: `lib/ui/desktop_shell.dart` (enable Review)
- Test: `test/review_grid_test.dart`

**Interfaces — Consumes:** `Session.exportable`, `Session.specFor`, `Renderer.render`, `AppStore.thumbnail`.

`GridView.builder` of exportable photos, each rendered through `Renderer` at 320 px long edge with its edit, crop, template and credit; a rendered tile is cached until its item or the batch template settings change. Tapping a tile selects the photo and opens a side panel: template override, shape override, credit text override, crop position (reuses `CropView`), and Open in Edit. A tile whose template references a missing asset shows a warning badge.

- [ ] **Step 1: Failing widget test** (stub renderer): 5 items with 1 rejected show 4 tiles; tapping tile 2 and entering a credit override sets `creditOverride` on that item only; a template with a missing logo file shows the warning badge.
- [ ] **Step 2:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 3:** Commit: `feat: review grid`.

---

### Task 11: Publication kit

**Files:**
- Modify: `lib/storage/app_store.dart`, `lib/ui/desktop_shell.dart` (Kit menu)
- Test: `test/kit_test.dart`

**Interfaces — Produces:**
```dart
Future<void> exportKit(String name, String filePath);   // zip: kit.json + assets/<file> for every referenced asset
Future<Kit> importKit(String filePath);                  // validates fully, then merges; throws FormatException
```
`kit.json`: `{"pressframe":"kit","version":1, ...Kit.toJson()}`. Credit text is not included; `CreditStyle` is. Import validates everything in memory before writing anything: the archive is under 200 MB unpacked, has `kit.json`, every other entry is `assets/<name>.png` with no `..`, no leading `/` or `\`, no drive letter, and decodes as PNG. Merge rule: an incoming preset or template whose name already exists is imported as `Name (2)`.

Kit menu: Export kit, Import kit, with a confirmation that lists what was added.

- [ ] **Step 1: Failing tests** (two AppStores on separate temp dirs): export from A, import into B, and B then has the same presets, templates and asset bytes; importing twice yields `Name (2)` entries and no overwrite; a zip without `kit.json` throws; a kit with a text file named `assets/x.png` throws; **Review Focus 4:** zips with entries `../evil.png`, `assets/../../evil.png`, `C:\evil.png` and `/evil.png` each throw `FormatException`, and after each attempt B's folder tree and the temp parent are byte-for-byte unchanged.
- [ ] **Step 2:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 3:** Commit: `feat: publication kit export and import`.

---

### Task 12: Phone shell and Android

**Files:**
- Create: `lib/ui/phone_shell.dart`
- Modify: `lib/main.dart` (`LayoutBuilder`: width < 900 uses `PhoneShell`), `android/app/src/main/AndroidManifest.xml`
- Test: `test/phone_shell_test.dart`

**Interfaces — Consumes:** every shared widget and `Session`; no new logic.

Layout per the spec: top bar (back, `3 / 48`, flag button, overflow with Import, Review, Export, Kit); photo; filmstrip; one slider group; bottom tabs Presets, Light, Color, Detail, Crop, Template. Hold photo = before, pinch zoom, double-tap slider resets, swipe up = pick, swipe down = reject. Review and the template editor open as full-screen pages. Portrait only (`SystemChrome.setPreferredOrientations`). Preview long edge 1280 and `maxDecodeEdge` 4096 on Android. If gallery permission is denied on export, show a page explaining why it is needed with Retry and Open settings.

- [ ] **Step 1: Failing widget test** at 390×844: bottom tabs Presets, Light, Color, Detail, Crop, Template exist; selecting Color shows Temperature and hides Exposure; every tappable widget has a hit area of at least 48×48; at 1280×800 the app shows `DesktopShell` and at 390×844 `PhoneShell`.
- [ ] **Step 2:** Run. Expected: FAIL. Implement. Expected: PASS.
- [ ] **Step 3:** Manual check on the physical phone (USB debugging; walk Dewdew through enabling it if needed): import 200 photos, edit one, Apply to all, add a built template, export. Watch memory in `flutter run --profile`; the app must not be killed. Confirm exported files appear in the gallery album `PressFrame` and are upright.
- [ ] **Step 4:** Run all three integration tests on the phone. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: phone layout`.

---

### Task 13: Polish and release builds

**Files:**
- Create: `installer/pressframe.iss`
- Modify: `README.md`, UI files for messages, `docs/superpowers/specs/2026-11-11-pressframe-design.md` only if behavior changed

- [ ] **Step 1:** Walk every row of the spec's Errors table on both devices and fix any message that is missing or unclear. Check empty states: no photos, no presets, no templates, nothing exportable.
- [ ] **Step 2:** Keyboard pass on Windows: every control reachable with Tab, visible focus ring, all shortcuts listed in a Help dialog.
- [ ] **Step 3:** `flutter build apk --release` and `flutter build windows --release`. Write `installer/pressframe.iss` (Inno Setup, free): install `build\windows\x64\runner\Release\*` to `{autopf}\PressFrame`, Start menu shortcut, uninstaller. Build the installer and install it on the laptop to confirm it launches.
- [ ] **Step 4:** Run `flutter test` and all integration tests on Windows and the phone. Expected: all PASS.
- [ ] **Step 5:** README: screenshots of both layouts, feature list, download section, "Problem I solved" note, and the `**Live demo:**` line updated to the GitHub Releases link once it exists.
- [ ] **Step 6:** Commit: `chore: release polish`. Pushing to GitHub, creating the release and recording the demo video are done with Dewdew step by step, not automatically.
