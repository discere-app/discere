import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks for a comparison list's name, starting from [initialName]. Resolves to
/// the trimmed name, or null when cancelled. An empty name cannot be
/// confirmed.
Future<String?> showComparisonNameDialog(
  BuildContext context, {
  required String title,
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => ComparisonNameDialog(title: title, initialName: initialName),
);

class ComparisonNameDialog extends StatefulWidget {
  final String title;
  final String initialName;

  const ComparisonNameDialog({
    required this.title,
    required this.initialName,
    super.key,
  });

  @override
  State<ComparisonNameDialog> createState() => _ComparisonNameDialogState();
}

class _ComparisonNameDialogState extends State<ComparisonNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  void _confirm() {
    if (_name.isNotEmpty) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('comparison_name_field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: loc.commonName),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.commonCancel),
        ),
        TextButton(
          key: const Key('comparison_name_confirm_button'),
          onPressed: _name.isEmpty ? null : _confirm,
          child: Text(loc.commonOk),
        ),
      ],
    );
  }
}
