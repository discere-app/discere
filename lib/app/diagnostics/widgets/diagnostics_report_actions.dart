import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/diagnostics_report_text.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// The app bar's share and copy buttons, which hand out the page's data as
/// the plain-text report once it has loaded.
class DiagnosticsReportActions extends StatelessWidget {
  final Future<DiagnosticsPageData>? data;

  const DiagnosticsReportActions({required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.loc.diagnosticsShareReport,
          onPressed: _share,
          icon: const Icon(Icons.ios_share_outlined),
        ),
        IconButton(
          tooltip: context.loc.diagnosticsCopyReport,
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_all_outlined),
        ),
      ],
    );
  }

  Future<void> _share() async {
    final loaded = await data;
    if (loaded == null) return;
    await SharePlus.instance.share(
      ShareParams(text: buildDiagnosticsReportText(loaded)),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final loaded = await data;
    if (loaded == null || !context.mounted) return;
    await Clipboard.setData(
      ClipboardData(text: buildDiagnosticsReportText(loaded)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.diagnosticsReportCopied)),
    );
  }
}
