# PressFrame: Edit + Brand Event Photos in One Pass
*(Press = the campus press; Frame = the publication's logo and frames.)*

## What it is
A mobile app + desktop app for school publication photographers. Fix the color and lighting, put the publication's logo or frame on top, and export a whole event's photos in one go. Works offline, no account.

## Problem it solves
After covering an event, a photojournalist edits each raw image in Lightroom (color, lighting), then moves to Canva to add the publication logo or frame, one photo at a time. Two apps, repeated for every photo. This app does both steps in one place and in batch.

## Flow
1. **Import** photos from the event (pick many at once).
2. **Edit** one photo with sliders, or tap a **preset**.
3. **Apply to all**: copy that edit to the rest of the batch.
4. **Pick a frame or logo** from the publication kit.
5. **Review grid**: see every photo with its edit + frame; tap any photo to tweak it or move its crop.
6. **Export** all to a folder. Originals are never changed.

## Features (v1)

### Editing (color and lighting)
- Light: exposure, contrast, highlights, shadows
- Color: temperature, tint, saturation, vibrance
- Detail: sharpen
- Crop, rotate, straighten
- Before/after toggle, reset, undo

### Presets
- Save the current slider values as a named preset
- A few built-in starter presets (e.g. indoor gym, outdoor sun, stage lights)
- Export / import a preset as a small file so staff can share one look

### Logo and frames (publication kit)
- **Logo mode:** import a PNG logo; choose the corner, size, margin and opacity
- **Frame mode:** import a full-size transparent PNG frame made in Canva/Photoshop; one frame per shape (square 1:1, portrait 4:5, landscape 3:2 or 16:9)
- The photo is cropped to match the frame's shape (center crop by default, adjustable per photo)
- A **publication kit** = logo + frames + presets saved together, exportable as one file so every staff member has the same look

### Batch
- Select many photos, apply one preset + one frame to all
- Per-photo overrides stay possible in the review grid
- Export queue with a progress bar, cancel, and a list of any photos that failed

### Export
- JPEG with a quality slider
- Resize option (e.g. long edge 2048 px for Facebook)
- Filename pattern (e.g. `EventName_001.jpg`)
- Pick the output folder

## Not in v1
- RAW files (JPEG/PNG only; see Open questions)
- Curves, HSL per color, masks or brush edits, healing
- Text on photos (captions, "Photo by" credit) — good v2 feature
- Accounts, cloud sync, team sharing over the internet
- iOS

## Stack (all free)
- **Flutter, one codebase** for Android + Windows (already used for Alkansya and Cat-On, so no new framework)
- **Live preview:** adjustments run as a GPU fragment shader on a downscaled copy of the photo, so sliders feel instant (integrated graphics is enough)
- **Export:** the same adjustment math at full resolution, one photo at a time in the background so the UI doesn't freeze
- **Storage:** presets and kit settings as JSON files; logos/frames as PNGs in the app folder. No database, no backend, no hosting
- **Distribution:** APK + Windows installer via GitHub Releases
- **Cost: P0.** Skip iOS, Play Store and Windows code signing, same as Pasa.

## Things to handle
- **Preview and export must match.** The shader preview and the full-size export need the same math, or the exported photo looks different from what was edited. Test this first.
- **Full-size photos are heavy.** A 24 MP photo is ~100 MB uncompressed in memory. Process one at a time, never load the whole batch.
- **Texture size limits on phones.** Some phone GPUs can't handle a full camera photo as one texture; export may need to run in tiles or on the CPU.
- **Photo rotation (EXIF).** Phone and camera photos store rotation as metadata; read it or portrait photos come out sideways.
- **Mixed shapes in one batch.** Portrait and landscape photos in the same batch each need the right frame; auto-pick by orientation.
- **Android storage permissions** for reading the gallery and saving to a folder.
- **Don't re-compress twice.** Edit + frame should be applied in one export, not saved and re-saved.

## Build order
1. **Engine test (do this first):** load one photo, one exposure slider with live preview, export at full size, confirm preview = export on both phone and laptop. This is the riskiest part; everything else depends on it.
2. **Single-photo editor:** all sliders, crop/rotate, before/after, export.
3. **Presets:** save, apply, built-ins, import/export.
4. **Logo and frames:** logo mode, frame mode, crop-to-frame.
5. **Batch:** multi-select, apply to all, review grid, export queue.
6. **Publication kit:** bundle and share logo + frames + presets.
7. **Polish:** phone and desktop layouts, empty states, error messages, demo video.

## Existing apps (for reference, not copying)
- **Lightroom (mobile/desktop):** strong editing, presets, copy-paste edits; can add a watermark on export, but no shaped frames, and full features need a subscription.
- **Canva:** frames and logos, bulk create, but weak photo editing and needs internet.
- **Snapseed, Polarr, Photoscape X, darktable:** editing, little or no branding/batch-frame workflow.
- **The gap:** edit + frame + batch in one free offline app built around how a school publication works.

## Open questions
**Closed on 2026-11-11.** Decisions are in `docs/superpowers/specs/2026-11-11-pressframe-design.md`, which wins where it differs from this file (RAW via embedded JPEG is in v1, laptop-first, selectable shapes, built-in template maker, pick/reject, auto fix, drag and drop).
- **RAW or JPEG?** Plan assumes JPEG only for v1. If the staff shoots RAW, that needs a RAW decoder and changes the engine.
- **Name:** PressFrame chosen (Nov 2026; "Photo Desk" was already taken). A quick web search found no app with this exact name, but it is not a full app store or trademark check.
- **Phone-first or laptop-first?** Decides which layout gets designed first.
- **Facebook sizes:** which frame shapes the publication actually posts (1:1, 4:5, landscape).

## Done checklist
- [ ] Installable builds (APK + Windows installer)
- [ ] README with screenshots
- [ ] 30-second demo video (short looping MP4 + full YouTube demo)
- [ ] "Problem I solved" note for the portfolio
