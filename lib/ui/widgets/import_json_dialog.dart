
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../service/common/import_export_service.dart';
import '../../../extensions/localization_extension.dart';

class ImportJsonDialog extends StatefulWidget {
  const ImportJsonDialog({super.key});

  @override
  State<ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends State<ImportJsonDialog> {
  final _controller = TextEditingController();
  bool _isImporting = false;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        setState(() {
          _controller.text = content;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _import() async {
    final jsonText = _controller.text.trim();
    if (jsonText.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final importService = Provider.of<ImportExportService>(context, listen: false);
      await importService.importDeckFromJson(jsonText);
      
      if (mounted) {
        Navigator.of(context).pop(true); // Return true on success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.importJsonInvalid(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.importJsonTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _pickFile,
              icon: const Icon(Icons.file_upload),
              label: Text(context.loc.importJsonFileButton),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: context.loc.importJsonPasteLabel,
                hintText: '{"name": "...", "description": "...", "speciesNames": [...]}',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              enabled: !_isImporting,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: Text(context.loc.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isImporting ? null : _import,
          child: _isImporting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.loc.importJsonButton),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
