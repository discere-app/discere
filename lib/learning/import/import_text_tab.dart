import 'dart:convert';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Takes a deck as pasted text or from a file; which format the text is in
/// is for the caller to recognize.
class ImportTextTab extends StatefulWidget {
  /// [sourceFileName] is the picked file's name without extension, until the
  /// field is cleared; null for pasted text.
  final Future<void> Function(String text, String? sourceFileName) onImportText;

  const ImportTextTab({required this.onImportText, super.key});

  @override
  State<ImportTextTab> createState() => _ImportTextTabState();
}

class _ImportTextTabState extends State<ImportTextTab> {
  final TextEditingController _textController = TextEditingController();
  String? _sourceFileName;
  bool _isImporting = false;

  Future<void> _importText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await widget.onImportText(text, _sourceFileName);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (file == null) return;

    // Read through the picker's file rather than a `File` on its path: a
    // picked file need not have a local path, depending on platform and
    // where it was picked from.
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    // A file in some other encoding then fails recognition with the usual
    // message instead of throwing here.
    _textController.text = utf8.decode(bytes, allowMalformed: true);
    _sourceFileName = p.basenameWithoutExtension(file.name);
  }

  void _onTextChanged(String text) {
    // Clearing the field ends its tie to the picked file; a list pasted in
    // afterwards must not be named after it.
    if (text.isEmpty) _sourceFileName = null;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: SingleChildScrollView(
        padding: AppSpacing.screenPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.loc.importTextTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            AppSpacing.heightS16,
            TextField(
              key: const ValueKey('import_text_field'),
              controller: _textController,
              onChanged: _onTextChanged,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: context.loc.importTextPasteHint,
                hintMaxLines: 3,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const ValueKey('import_text_file_button'),
                  icon: const Icon(Icons.file_open),
                  tooltip: context.loc.importTextFileButton,
                  onPressed: _isImporting ? null : _importFile,
                ),
              ),
            ),
            AppSpacing.heightS24,
            ElevatedButton(
              key: const ValueKey('import_text_button'),
              onPressed: _isImporting ? null : _importText,
              child: _isImporting
                  ? const CircularProgressIndicator()
                  : Text(context.loc.importTextButton),
            ),
          ],
        ),
      ),
    );
  }
}
