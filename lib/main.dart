import 'package:flutter/material.dart';

import 'engine/renderer.dart';
import 'session.dart';
import 'ui/desktop_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderer = await Renderer.load();
  runApp(PressFrameApp(session: Session(), renderer: renderer));
}

class PressFrameApp extends StatelessWidget {
  final Session session;
  final Renderer? renderer;
  const PressFrameApp({super.key, required this.session, this.renderer});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PressFrame',
    debugShowCheckedModeBanner: false,
    theme: pressFrameTheme,
    home: DesktopShell(session: session, renderer: renderer),
  );
}
