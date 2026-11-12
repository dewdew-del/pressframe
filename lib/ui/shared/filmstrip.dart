import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/decode.dart';
import '../../models/batch_item.dart';
import '../../session.dart';
import '../theme.dart';

/// Loads a thumbnail unless the tile asking for it is already gone.
typedef ThumbnailLoader = Future<ui.Image?> Function(String path, bool Function() wanted);

const _tileExtent = 84.0;

/// Horizontal strip of the visible photos. Only the tiles on screen exist, so a batch of
/// hundreds of photos costs no more memory than a dozen.
class Filmstrip extends StatefulWidget {
  final Session session;
  final ThumbnailLoader? thumbnails; // null in widget tests: gray tiles
  const Filmstrip({super.key, required this.session, this.thumbnails});

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  final _scroll = ScrollController();
  int _lastSelected = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Keep the selected photo in view when the arrow keys walk off the edge.
  void _reveal(int position) {
    if (!_scroll.hasClients) return;
    final view = _scroll.position;
    final start = position * _tileExtent, end = start + _tileExtent;
    if (start < view.pixels) {
      _scroll.jumpTo(start);
    } else if (end > view.pixels + view.viewportDimension) {
      _scroll.jumpTo((end - view.viewportDimension).clamp(0.0, view.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final visible = session.visibleIndexes;
      if (session.selectedIndex != _lastSelected) {
        _lastSelected = session.selectedIndex;
        final position = visible.indexOf(_lastSelected);
        if (position >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(position));
        }
      }
      return SizedBox(
        height: 72,
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemExtent: _tileExtent,
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final index = visible[i];
            final item = session.items[index];
            return FilmstripTile(
              key: ValueKey('tile-${item.path}'),
              item: item,
              selected: index == session.selectedIndex,
              thumbnails: widget.thumbnails,
              onTap: () => session.select(index),
            );
          },
        ),
      );
    },
  );
}

class FilmstripTile extends StatefulWidget {
  final BatchItem item;
  final bool selected;
  final ThumbnailLoader? thumbnails;
  final VoidCallback onTap;

  const FilmstripTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.thumbnails,
  });

  @override
  State<FilmstripTile> createState() => _FilmstripTileState();
}

class _FilmstripTileState extends State<FilmstripTile> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final load = widget.thumbnails;
    if (load == null) return;
    try {
      final image = await load(widget.item.path, () => mounted);
      if (!mounted) return image?.dispose();
      setState(() => _image = image);
    } on DecodeFailure {
      // the tile stays gray; the preview explains why when the photo is selected
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final name = item.path.split(RegExp(r'[\\/]')).last;
    return Semantics(
      label: 'Photo $name${item.flag == Flag.none ? '' : ', ${item.flag.name}'}',
      selected: widget.selected,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3A),
            border: Border.all(
              color: widget.selected ? accentColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_image != null) RawImage(image: _image, fit: BoxFit.cover),
              if (item.flag != Flag.none)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.flag == Flag.pick ? Colors.greenAccent : Colors.redAccent,
                      border: Border.all(color: Colors.black54),
                    ),
                  ),
                ),
              if (item.isRaw)
                const Positioned(
                  right: 3,
                  bottom: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xB0000000)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Text('RAW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              if (item.smallPreview)
                const Positioned(
                  right: 2,
                  top: 2,
                  child: Tooltip(
                    message: 'Small preview: this RAW will export small',
                    child: Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
