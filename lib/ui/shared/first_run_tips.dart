import 'package:flutter/material.dart';

const tipSteps = [
  ('1  Edit', 'Add your photos, then adjust light, color and crop. Pick a template for the frame or caption. On a phone you can plug in your camera with a USB cable (camera set to PTP or MTP mode) and pick photos straight from it.'),
  ('2  Review', 'See every photo as it will be exported. Tap one to change its template, shape or credit.'),
  ('3  Export', 'Choose a name for the event and export. Your original photos are never changed.'),
];

/// Three short steps, shown once. Skip or finishing both count as seen.
Future<void> showFirstRunTips(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const _Tips(),
);

class _Tips extends StatefulWidget {
  const _Tips();

  @override
  State<_Tips> createState() => _TipsState();
}

class _TipsState extends State<_Tips> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final (title, body) = tipSteps[_i];
    final last = _i == tipSteps.length - 1;
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        Text('${_i + 1} of ${tipSteps.length}'),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip')),
        FilledButton(
          onPressed: last ? () => Navigator.pop(context) : () => setState(() => _i++),
          child: Text(last ? 'Done' : 'Next'),
        ),
      ],
    );
  }
}
