import 'dart:io';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ImportJsonTab extends StatefulWidget {
  final Future<void> Function(String jsonText) onImportJson;

  const ImportJsonTab({required this.onImportJson, super.key});

  @override
  State<ImportJsonTab> createState() => _ImportJsonTabState();
}

class _ImportJsonTabState extends State<ImportJsonTab> {
  final TextEditingController _jsonController = TextEditingController();
  bool _isImporting = false;

  Future<void> _importJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await widget.onImportJson(text);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.path != null) {
      final file = File(result.path!);
      final content = await file.readAsString();
      _jsonController.text = content;
    }
  }

  @override
  void dispose() {
    _jsonController.dispose();
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
              context.loc.importJsonTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            AppSpacing.heightS16,
            TextField(
              controller: _jsonController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: context.loc.importJsonPasteLabel,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.file_open),
                  onPressed: _isImporting ? null : _importFile,
                ),
              ),
            ),
            AppSpacing.heightS24,
            ElevatedButton(
              key: const ValueKey('import-json-button'),
              onPressed: _isImporting ? null : _importJson,
              child: _isImporting
                  ? const CircularProgressIndicator()
                  : Text(context.loc.importJsonButton),
            ),
          ],
        ),
      ),
    );
  }
}
