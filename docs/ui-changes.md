# UI changes agreed with Dewdew

Source: the design canvas https://claude.ai/artifact/SRvtnEnsBY615NuqLhJiG7 (private). L = laptop, P = phone. Do not change anything else.

## Remove

| What | Screen |
|---|---|
| "Auto fix" button | L Edit (Light section), P Edit (Light tab) |
| Edit / Review / Export buttons in the top bar | L top bar (replaced by the step bar below) |
| Top-bar "Export" button | L top bar |
| "Export all" in the Edit bottom bar (becomes the Next button) | L Edit |
| Filter, Apply to all, Undo, Redo, Reset from the bottom bar | L bottom bar (moved, see Move) |
| "Import preset" button | L and P presets (moved into a ⋮ menu) |
| Presets tab and Detail tab | P bottom tabs (6 tabs become 4) |
| "Review" and "Export" items in the More menu | P More menu |

## Add

| What | Screen |
|---|---|
| Step bar "1 Edit › 2 Review › 3 Export" (shows progress, current step highlighted) | L top bar |
| One main blue button, bottom right: "Next: Review →" on Edit, "Export all" on Review | L Edit, L Review |
| "Next →" blue pill in the top bar | P Edit |
| "Before / After" button on the photo (the `\` key keeps working) | L Edit |
| New sliders: Whites, Blacks (Light), Texture, Clarity (Detail) | L and P Edit. Needs new engine parameters, check with Dewdew if the engine work is too big |
| "More controls ▾" row under Light, Color and Detail. Hidden by default: Highlights, Whites, Blacks / Tint, Vibrance / Texture, Clarity | L and P Edit |
| Preset chips (Indoor gym, Outdoor sun, Stage lights, saved ones) at the top of the Light tab | P Edit |
| "⋮ More" menu: Kit (Export kit, Import kit), Filter, Apply to all | L top bar |
| "⋮" next to Save current: Import preset, export or delete a saved preset | L and P presets |
| Empty first-run screen: big "Add photos" drop area with 3 steps | L and P (not drawn yet, wording is up to the build session) |
| Undo toast "Undone. Redo?" and tooltips on every icon | L and P |

## Move

- Undo, Redo, Reset: from the bottom bar to a small pill at the top right of the photo (L Edit).
- Photo counter "3 / 24" stays in the bottom bar next to the main button.
- Kit, Filter, Apply to all: into "⋮ More".

## Change

- Slider look: label on the left, small value box on the right, thin track with a triangle marker below. Temperature track blue to yellow, Tint green to magenta. Values shown as whole numbers (-100 to 100), Exposure keeps 2 decimals. Applies to every edit slider, L and P.
- Plain labels: Exposure shows as "Brightness", Temperature as "Warmth", under the first three sliders of Light and the first two of Color. The exact names (Highlights, Tint and the rest) stay under "More controls".
- Visible slider order. Light: Brightness, Contrast, Shadows. Color: Warmth, Saturation. Detail: Sharpen.
- Gray hint text lighter (use `#A8A8A8` on `#2A2A2A`, the old `#8A8A8A` fails contrast). Smallest text 12 px. "More controls" rows and P tabs at least 44 px tall, P tab text 14 px.
- Photo hint text becomes "Scroll to zoom, drag to move."

## Speed rules (build)

- While a slider is dragged, redraw a small preview copy; redraw full quality only on release.
- Keep thumbnails cached; build only the tiles on screen.
- Export runs in the background with Cancel; the screen never blocks.

## Not changed

Import menu, Template section (pairs, shapes, credit, editor), Crop section, Review grid and panel, Export dialog fields, keyboard shortcuts.

---

# Round 2 (agreed after round 1 was built)

Round 1 above is built. Where the app differs from it (all sliders always shown, no "More controls" row, step bar buttons, Preset options) the app wins. Boards marked "New" on the design canvas show each item below.

## Shorter text (Export dialog laptop, Export page phone)

- "24 photos will be exported" becomes "Export 24 photos".
- RAW warning becomes "2 RAW photos will export small" (one line, keep the warning icon).
- "Saves to: <full path>" becomes "Saves to Downloads" (phone: "Saves to your gallery").
- "Make a new folder named after the event" becomes "New folder for this event".

## Add (screen)

| What | Screen |
|---|---|
| "Continue where you stopped?" dialog on start, with Start new / Continue. Needs the session (photos, edits, template choices) saved to disk as it changes | L, P |
| "Compare with original" toggle at the top right of the Review grid | L (P: in the photo sheet) |
| After a successful export: "Export successful! N photos saved." plus Open folder and Export again | L, P (P: "Open gallery") |
| "Check before exporting" dialog: lists photos with no template, and credit on with empty text. Buttons Go back / Export anyway | L, P |
| Saved credit names: Credit text becomes a dropdown of saved names plus "Add a name…" | L, P (Template, and Review "Credit for this photo") |
| First-run tips: 3 short steps (Edit, Review, Export) with Skip / Next, shown once | L, P |
| Plain error text that says what to do (example: "IMG_0412.CR3 is damaged or not supported. Export it from your camera as a JPEG and add it again.") | L, P |
| Full-disk and file-already-exists messages in plain words | L, P |

## Build notes (no new screen)

- Text size setting (small, normal, large) in the help or more menu.
- Optional light theme.
- Keyboard pass on the laptop (Tab order, focus ring) and screen-reader labels on every icon button.
- Test with 300+ RAW photos on the Ryzen 7 laptop: filmstrip, Review grid, export. Report timings.
- Phone keeps the screen awake while exporting and shows progress if the app is backgrounded.
