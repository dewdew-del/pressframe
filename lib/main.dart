import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/renderer.dart';
import 'session.dart';
import 'storage/app_store.dart';
import 'storage/template_library.dart';
import 'ui/desktop_shell.dart';
import 'ui/phone_shell.dart';
import 'ui/shared/first_run_tips.dart';
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

class PressFrameApp extends StatefulWidget {
  final Session session;
  final Renderer? renderer;
  final AppStore? store;
  final TemplateLibrary? library;
  const PressFrameApp({super.key, required this.session, this.renderer, this.store, this.library});

  @override
  State<PressFrameApp> createState() => _PressFrameAppState();
}

class _PressFrameAppState extends State<PressFrameApp> {
  final _nav = GlobalKey<NavigatorState>();
  Timer? _save;
  List<String> _savedNames = [];

  @override
  void initState() {
    super.initState();
    if (widget.store == null) return;
    textScaleSetting.value = widget.store!.loadTextScale();
    textScaleSetting.addListener(_saveScale);
    // Autosave starts only after the "Continue?" question, so it cannot erase the old session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRestore());
  }

  void _saveScale() => widget.store?.saveTextScale(textScaleSetting.value).ignore();

  Future<void> _offerRestore() async {
    final store = widget.store!;
    Map<String, dynamic>? saved;
    try {
      saved = await store.loadSession();
    } on Object {
      // an unreadable file is the same as no session
    }
    final count = saved == null ? 0 : (saved['items'] as List? ?? const []).length;
    final ctx = _nav.currentContext;
    if (count > 0 && ctx != null && ctx.mounted) {
      final cont = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Continue where you stopped?'),
          content: Text('$count photo${count == 1 ? '' : 's'} with your edits are saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start new')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (cont == true) widget.session.restore(saved!);
    }
    final tipsCtx = _nav.currentContext;
    if (!store.tipsSeen && tipsCtx != null && tipsCtx.mounted) {
      await showFirstRunTips(tipsCtx);
      store.markTipsSeen().ignore();
    }
    try {
      widget.session.setCreditNames(await store.loadCreditNames());
    } on Object {
      // no saved names yet
    }
    if (!mounted) return;
    _savedNames = widget.session.creditNames;
    widget.session.addListener(_scheduleSave);
    _scheduleSave(); // "Start new" clears the old file
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () {
      final s = widget.session;
      if (!listEquals(_savedNames, s.creditNames)) {
        _savedNames = s.creditNames;
        widget.store!.saveCreditNames(_savedNames).ignore();
      }
      widget.store!.saveSession(s.items.isEmpty ? null : s.toJson()).catchError((Object _) {
        // shortcut: a failed autosave (full disk) is silent, upgrade if users lose work to it.
      });
    });
  }

  @override
  void dispose() {
    _save?.cancel();
    textScaleSetting.removeListener(_saveScale);
    widget.session.removeListener(_scheduleSave);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _nav,
    title: 'PressFrame',
    debugShowCheckedModeBanner: false,
    theme: pressFrameTheme,
    builder: (context, child) => ValueListenableBuilder<double>(
      valueListenable: textScaleSetting,
      builder: (context, scale, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * scale),
        ),
        child: child!,
      ),
    ),
    // One set of shared widgets inside two shells, switched at 900 px.
    home: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 900
          ? PhoneShell(session: widget.session, renderer: widget.renderer, store: widget.store, library: widget.library)
          : DesktopShell(session: widget.session, renderer: widget.renderer, store: widget.store, library: widget.library),
    ),
  );
}
