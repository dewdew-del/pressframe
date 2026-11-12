# PressFrame

**Live demo:** coming soon (APK and Windows installer will be on GitHub Releases)

PressFrame is one Flutter app for Android and Windows, made for school publication photographers. Fix color and light, add the publication's branding (a gradient band with logos, or an imported PNG frame), and export a whole event in one pass. It works offline, needs no account and costs nothing.

## Screenshots

Coming soon: the laptop layout and the phone layout.

## Problem I solved

After every school event, our publication's photographers edit each photo in one app, add the logo and color band in another, then export them one by one. The same look gets rebuilt by hand every time, and it never comes out quite the same between staff members.

PressFrame puts the whole job in one place. You import the event, fix light and color once and apply it to every photo, pick a branding template, and export everything in one pass. The template, logos and presets travel as a single "kit" file, so the whole staff posts with the same look.

## Features

- **Import** JPEG, PNG and RAW (`.cr3`, `.cr2`, `.arw`) by file picker, folder, or drag and drop on Windows. RAW files open through the preview JPEG stored inside them.
- **Pick and reject.** Rejected photos are hidden and never exported. Nothing is deleted from disk.
- **Edit** exposure, contrast, highlights, shadows, temperature, tint, saturation, vibrance and sharpen. Crop, rotate and straighten. Undo and redo per photo, before/after, copy and paste an edit, apply to all.
- **Auto fix** sets exposure, contrast, temperature and tint from the photo. It only moves the sliders, so you can fine-tune or undo it.
- **Presets**: three built in (Indoor gym, Outdoor sun, Stage lights), plus your own. Share one as a `.pfpreset` file.
- **Branding templates**: build one in the app (gradient band on the top, bottom or both, plus logos you drag into place), or import a transparent PNG frame made in Canva or Photoshop.
- **Output shapes**: Original, 1:1, 4:5, 3:2, 16:9, 2:3 and 9:16, chosen separately for landscape and portrait photos, with per-photo override.
- **Photo credit** (optional, off by default): one line of text in a corner, with per-photo override for events with several photographers.
- **Review** every photo with its edit and branding applied before exporting.
- **Export** to JPEG with a quality slider, a long-edge size, and names like `EventName_001.jpg`. One bad file does not stop the batch, and existing files are never overwritten.
- **Publication kit**: export templates, logos and presets as one `.pfkit` file for the rest of the staff.
- What you see in the preview is what gets exported: both are drawn by the same code.
- Your original photos are never changed.

## Download

Coming soon on GitHub Releases:

- **Android:** `PressFrame.apk`. Exported photos are saved to the gallery album "PressFrame".
- **Windows:** `PressFrame-Setup-1.0.0.exe`. It installs for the current user, so no administrator password is needed.

## Good to know

- RAW files are not developed from sensor data. PressFrame uses the JPEG preview the camera stores inside the RAW file. Canon files normally store a full-size preview. Some Sony bodies store only a small one (about 1616 px); those files show a warning, and shooting RAW+JPEG avoids the problem.
- Not in this version: curves, HSL, masks, healing, captions, custom fonts, PNG or TIFF export, accounts, cloud, iOS.

## Keyboard shortcuts (Windows)

| Key | Action |
|---|---|
| Left / Right | Previous / next photo |
| P, X, U | Pick, reject, clear flag |
| `\` (hold) | Show the photo before editing |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+C / Ctrl+V | Copy / paste the edit |
| Double-click a slider | Reset it |
| Mouse wheel on the photo | Zoom |
| F1 | Show this list in the app |

## Build from source

Needs the Flutter SDK. Then:

```
flutter pub get
flutter run -d windows
```

Tests:

```
flutter test
flutter test integration_test/engine_test.dart -d windows
flutter test integration_test/export_test.dart -d windows
flutter test integration_test/template_test.dart -d windows
```

Release builds:

```
flutter build apk --release
flutter build windows --release
```

The Windows installer is made with [Inno Setup](https://jrsoftware.org/isinfo.php) (free) from `installer/pressframe.iss`.

## Built with

Flutter and Dart, one GLSL fragment shader for the color math, and six packages: `file_picker`, `desktop_drop`, `image`, `archive`, `path_provider`, `gal`.

The design is in `docs/superpowers/specs/2026-11-11-pressframe-design.md`.
