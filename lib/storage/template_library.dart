import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../engine/decode.dart';
import '../models/template.dart';
import 'app_store.dart';

/// The saved templates and their decoded logo / frame images, kept in memory so the
/// preview, the review grid and the exporter all draw from the same pictures.
class TemplateLibrary extends ChangeNotifier {
  final AppStore store;
  final int maxAssetEdge; // 4096 on Windows, 2048 on Android

  TemplateLibrary(this.store, {this.maxAssetEdge = 4096});

  List<Template> _templates = const [];
  List<Template> get templates => _templates;

  /// Decoded assets by file name. A file that is missing or damaged has no entry.
  final Map<String, ui.Image> assets = {};

  Template? byName(String? name) {
    for (final t in _templates) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// True when the template refers to a logo or frame file that could not be loaded.
  bool hasMissingAssets(Template t) => assetFiles(t).any((f) => !assets.containsKey(f));

  Future<void> reload() async {
    _templates = await store.loadTemplates();
    for (final t in _templates) {
      await ensureAssets(t);
    }
    notifyListeners();
  }

  /// Loads whatever images [t] needs and are not in memory yet.
  Future<void> ensureAssets(Template t) async {
    for (final file in assetFiles(t)) {
      if (assets.containsKey(file)) continue;
      try {
        assets[file] = await store.asset(file, maxLongEdge: maxAssetEdge);
      } on DecodeFailure {
        // stays missing; the UI flags the template
      }
    }
  }

  Future<void> save(Template t) async {
    await store.saveTemplate(t);
    await reload();
  }

  Future<void> delete(String name) async {
    await store.deleteTemplate(name);
    await reload();
  }

  /// Copies a PNG into the app folder and returns its stored name.
  /// Throws [FormatException] if the file is not a PNG.
  Future<String> importAsset(String pngPath) async {
    final name = await store.importAsset(pngPath);
    if (!assets.containsKey(name)) {
      try {
        assets[name] = await store.asset(name, maxLongEdge: maxAssetEdge);
      } on DecodeFailure catch (e) {
        throw FormatException(e.reason);
      }
      notifyListeners();
    }
    return name;
  }
}
