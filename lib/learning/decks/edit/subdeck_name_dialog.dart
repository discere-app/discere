import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks for a subdeck's name, starting from [initialName]. Resolves to the
/// trimmed name, or null when cancelled. An empty name or one [isTaken] says
/// another subdeck has cannot be confirmed.
Future<String?> showSubdeckNameDialog(
  BuildContext context, {
  required String title,
  required bool Function(String name) isTaken,
  String initialName = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _SubdeckNameDialog(
    title: title,
    isTaken: isTaken,
    initialName: initialName,
  ),
);

class _SubdeckNameDialog extends StatefulWidget {
  final String title;
  final bool Function(String name) isTaken;
  final String initialName;

  const _SubdeckNameDialog({
    required this.title,
    required this.isTaken,
    required this.initialName,
  });

  @override
  State<_SubdeckNameDialog> createState() => _SubdeckNameDialogState();
}

class _SubdeckNameDialogState extends State<_SubdeckNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  bool get _isTaken => widget.isTaken(_name);

  bool get _canConfirm => _name.isNotEmpty && !_isTaken;

  void _confirm() {
    if (_canConfirm) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('edit_deck_subdeck_name_field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: loc.editDeckSubdeckNameLabel,
          errorText: _isTaken ? loc.editDeckSubdeckNameTaken : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.commonCancel),
        ),
        TextButton(
          key: const Key('edit_deck_subdeck_name_confirm_button'),
          onPressed: _canConfirm ? _confirm : null,
          child: Text(loc.commonOk),
        ),
      ],
    );
  }
}
