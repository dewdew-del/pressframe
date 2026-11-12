import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/renderer.dart';
import 'session.dart';
import 'storage/app_store.dart';
import 'storage/template_library.dart';
import 'ui/desktop_shell.dart';
import 'ui/phone_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Portrait only in v1.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final renderer = await Renderer.load();
  final store = await AppStore.open();
  // Frames and logos are decoded smaller on the phone to keep memory in check.
  final library = TemplateLibrary(store, maxAssetEdge: Platform.isAndroid ? 2048 : 4096);
  await library.reload();
  runApp(PressFrameApp(session: Session(), renderer: renderer, store: store, library: library));
}

class PressFrameApp extends StatelessWidget {
  final Session session;
  final Renderer? renderer;
  final AppStore? store;
  final TemplateLibrary? library;
  const PressFrameApp({super.key, required this.session, this.renderer, this.store, this.library});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PressFrame',
    debugShowCheckedModeBanner: false,
    theme: pressFrameTheme,
    // One set of shared widgets inside two shells, switched at 900 px.
    home: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 900
          ? PhoneShell(session: session, renderer: renderer, store: store, library: library)
          : DesktopShell(session: session, renderer: renderer, store: store, library: library),
    ),
  );
}
