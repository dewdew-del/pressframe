import 'package:flutter/material.dart';

import 'engine/renderer.dart';
import 'session.dart';
import 'storage/app_store.dart';
import 'storage/template_library.dart';
import 'ui/desktop_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderer = await Renderer.load();
  final store = await AppStore.open();
  final library = TemplateLibrary(store);
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
    home: DesktopShell(session: session, renderer: renderer, store: store, library: library),
  );
}
