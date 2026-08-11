import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class DiagnosticsLogViewerPage extends StatefulWidget {
  final DiagnosticsLogFile logFile;

  const DiagnosticsLogViewerPage({super.key, required this.logFile});

  @override
  State<DiagnosticsLogViewerPage> createState() =>
      _DiagnosticsLogViewerPageState();
}

class _DiagnosticsLogViewerPageState extends State<DiagnosticsLogViewerPage> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.logFile.readAll();
  }

  Future<void> _refresh() async {
    final next = widget.logFile.readAll();
    setState(() => _future = next);
    await next;
  }

  Future<void> _export() async {
    final file = await widget.logFile.file();
    if (!await file.exists()) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.diagnosticsLogViewerTitle),
        actions: [
          IconButton(
            tooltip: context.loc.diagnosticsExportLog,
            onPressed: _export,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final content = snapshot.data!;
            if (content.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.loc.diagnosticsLogEmpty),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
