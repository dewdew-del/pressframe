import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../engine/auto_fix.dart';
import '../../engine/decode.dart';
import '../../engine/renderer.dart';
import '../../export/exporter.dart';
import '../../models/template.dart';
import '../../session.dart';
import '../../storage/app_store.dart';
import '../../storage/template_library.dart';
import 'filmstrip.dart' show ThumbnailLoader;
import 'slider_group.dart';

const filterNames = {
  FlagFilter.all: 'All',
  FlagFilter.picks: 'Picks',
  FlagFilter.hideRejects: 'Hide rejects',
};

/// What both layouts do the same way: import, export, kits, auto fix, and the sizes that
/// differ between the laptop and the phone.
class AppActions {
  final Session session;
  final Renderer? renderer; // null in widget tests
  final AppStore? store; // null in widget tests
  final TemplateLibrary? library; // null in widget tests
  final bool android;

  AppActions({required this.session, this.renderer, this.store, this.library, bool? android})
    : android = android ?? Platform.isAndroid;

  int get previewEdge => android ? 1280 : 2048;
  int get maxDecodeEdge => android ? 4096 : 8192;
  ThumbnailLoader? get thumbnails => store?.thumbnailIf;
  List<Template> get templates => library?.templates ?? const [];
  Map<String, ui.Image> get assets => library?.assets ?? const {};

  List<RenderSpec> specs() => [
    for (final item in session.exportable) session.specFor(item, templates),
  ];

  /// On Android each finished file goes to the gallery album "PressFrame".
  Exporter? exporter() => renderer == null
      ? null
      : Exporter(
          renderer!,
          maxDecodeEdge: maxDecodeEdge,
          loadAssets: (_) async => assets,
          publish: android ? (path) => Gal.putImage(path, album: 'PressFrame') : null,
        );

  /// Android: the private folder exports pass through on their way to the gallery.
  Future<String> galleryStagingDir() async => '${(await getTemporaryDirectory()).path}/export';

  Future<bool> hasGalleryAccess() async =>
      await Gal.hasAccess(toAlbum: true) || await Gal.requestAccess(toAlbum: true);

  /// Opens this app's page in Android settings (handled in MainActivity.kt).
  void openAppSettings() =>
      const MethodChannel('pressframe/settings').invokeMethod<void>('open').ignore();

  /// Reads a small copy of the selected photo and moves the sliders to a sensible start.
  Future<void> autoFixSelected() async {
    final item = session.selected;
    if (item == null) return;
    final ui.Image small;
    try {
      small = await decodeImage(item.path, maxLongEdge: 256);
    } on DecodeFailure {
      return; // the preview already shows why this photo cannot be opened
    }
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    final (w, h) = (small.width, small.height);
    small.dispose();
    if (data == null || session.selected?.path != item.path) return;
    session.setEdit(autoFix(data.buffer.asUint8List(), w, h, session.selected!.edit), commit: true);
  }

  static void say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  static const _extensions = ['jpg', 'jpeg', 'png', 'cr3', 'cr2', 'arw'];

  Future<void> addPhotos(BuildContext context) async {
    // Android's picker cannot filter by RAW extensions, so it shows every file there;
    // unsupported ones are ignored on import.
    final picked = await FilePicker.pickFiles(
      type: android ? FileType.any : FileType.custom,
      allowedExtensions: android ? null : _extensions,
    );
    if (context.mounted) await importPaths(context, [for (final f in picked) ?f.path]);
  }

  Future<void> addFolder(BuildContext context) async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder of photos');
    if (dir != null && context.mounted) await importPaths(context, [dir]);
  }

  /// Imports and, when some files could not be opened, lists them.
  Future<void> importPaths(BuildContext context, List<String> paths) async {
    if (paths.isEmpty) return;
    final before = session.items.length;
    final skipped = await session.import(paths);
    if (!context.mounted) return;
    if (skipped.isEmpty) {
      if (session.items.length == before) say(context, 'No new photos were found.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${skipped.length} file${skipped.length == 1 ? '' : 's'} could not be opened'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [for (final p in skipped) Text(p.split(RegExp(r'[\\/]')).last)],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> exportKit(BuildContext context) async {
    final bytes = await store!.encodeKit('PressFrame kit', credit: session.credit);
    final saved = await FilePicker.saveFile(
      fileName: 'publication.pfkit',
      bytes: bytes,
      dialogTitle: 'Save the publication kit',
    );
    if (saved != null && context.mounted) say(context, 'Kit saved. Share the file with your staff.');
  }

  /// Returns true when a kit was added (the caller refreshes its preset list).
  Future<bool> importKit(BuildContext context) async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a .pfkit file');
    final path = file?.path;
    if (path == null) return false;
    try {
      final kit = await store!.importKit(path);
      await library?.reload();
      // The kit sets how the credit looks; whether it is on stays the user's choice.
      session.credit = kit.credit.copyWith(enabled: session.credit.enabled);
      if (!context.mounted) return true;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kit imported'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (kit.presets.isEmpty && kit.templates.isEmpty) const Text('The kit was empty.'),
                for (final p in kit.presets) Text('Preset: ${p.name}'),
                for (final t in kit.templates) Text('Template: ${t.name}'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return true;
    } on FormatException catch (e) {
      if (context.mounted) {
        say(context, 'That kit could not be imported (${e.message}). Nothing was changed.');
      }
      return false;
    }
  }
}

/// Rotate, straighten and reset, shared by both layouts. [cropping] and [onCropping] add
/// the laptop's "Adjust crop" switch; the phone shows the crop tool whenever this is open.
class CropTools extends StatelessWidget {
  final Session session;
  final bool? cropping;
  final ValueChanged<bool>? onCropping;
  const CropTools({super.key, required this.session, this.cropping, this.onCropping});

  // A turned photo has a different shape, so an old crop no longer fits: start over.
  void _rotate(int turns) => session.updateSelected(
    (i) => i.copyWith(quarterTurns: (i.quarterTurns + turns) % 4, crop: () => null),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final item = session.selected;
      final on = item != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: on ? () => _rotate(3) : null,
                  icon: const Icon(Icons.rotate_left),
                  label: const Text('Rotate left'),
                ),
                OutlinedButton.icon(
                  onPressed: on ? () => _rotate(1) : null,
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate right'),
                ),
                if (cropping != null)
                  FilterChip(
                    label: const Text('Adjust crop'),
                    selected: cropping!,
                    onSelected: on ? onCropping : null,
                  ),
                TextButton(
                  onPressed: on
                      ? () => session.updateSelected((i) => i.copyWith(crop: () => null, straighten: 0))
                      : null,
                  child: const Text('Reset crop'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LabeledSlider(
            label: 'Straighten',
            min: -15,
            max: 15,
            value: item?.straighten ?? 0,
            enabled: on,
            format: (v) => '${v.toStringAsFixed(1)}°',
            onChanged: (v) => session.updateLive((i) => i.copyWith(straighten: v), commit: false),
            onChangeEnd: (v) => session.updateLive((i) => i.copyWith(straighten: v), commit: true),
          ),
        ],
      );
    },
  );
}
