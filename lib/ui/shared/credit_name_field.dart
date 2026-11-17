import 'package:flutter/material.dart';

import '../../session.dart';

const _addName = '\u0000add';

/// Credit text as a dropdown of saved names plus "Add a name…". [value] null or '' means
/// no name; that choice is shown as [emptyLabel] and reported as ''.
class CreditNameField extends StatelessWidget {
  final Session session;
  final String? value;
  final String label, emptyLabel;
  final String? helper;
  final ValueChanged<String> onChanged;

  const CreditNameField({
    super.key,
    required this.session,
    required this.value,
    required this.label,
    required this.emptyLabel,
    required this.onChanged,
    this.helper,
  });

  Future<void> _add(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Add a name'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(hintText: 'Photo by Juan Dela Cruz'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Add')),
          ],
        );
      },
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) return;
    session.addCreditName(clean);
    onChanged(clean);
  }

  @override
  Widget build(BuildContext context) {
    final current = value ?? '';
    final names = session.creditNames;
    return DropdownButtonFormField<String>(
      // A new key per value, so the field follows changes made elsewhere.
      key: ValueKey('$label|$current|${names.length}'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helper),
      items: [
        DropdownMenuItem(value: '', child: Text(emptyLabel)),
        for (final n in {...names, if (current.isNotEmpty) current})
          DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: _addName, child: Text('Add a name…')),
      ],
      onChanged: (v) => v == _addName ? _add(context) : onChanged(v ?? ''),
    );
  }
}
