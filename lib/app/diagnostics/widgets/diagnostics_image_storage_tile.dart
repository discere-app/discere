import 'package:discere/app/diagnostics/diagnostics_formatting.dart';
import 'package:discere/app/util/byte_format.dart';
import 'package:discere/enrichment/media/model/species_image_storage_sweep.dart';
import 'package:discere/enrichment/media/model/species_image_sweep_trigger.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:material_ui/material_ui.dart';

/// The last sweep of the species image storage: when, why and how long, how
/// many species it kept and let go, and what it deleted from each
/// directory.
class DiagnosticsImageStorageTile extends StatelessWidget {
  final SpeciesImageStorageSweep? sweep;

  const DiagnosticsImageStorageTile({required this.sweep, super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(context.loc.diagnosticsImageStorageTitle),
      subtitle: Text(_subtitle(context)),
    );
  }

  String _subtitle(BuildContext context) {
    final sweep = this.sweep;
    if (sweep == null) return context.loc.diagnosticsImageStorageNotSwept;
    final loc = context.loc;
    return [
      loc.diagnosticsImageStorageLastSweep(
        formatDiagnosticsDateTime(context, sweep.sweptAt).replaceAll('\n', ' '),
        switch (sweep.trigger) {
          SpeciesImageSweepTrigger.automatic =>
            loc.diagnosticsImageStorageTriggerAutomatic,
          SpeciesImageSweepTrigger.manual =>
            loc.diagnosticsImageStorageTriggerManual,
        },
        sweep.duration.inMilliseconds,
        sweep.neededSpeciesCount,
        sweep.releasedSpeciesCount,
      ),
      for (final MapEntry(key: directory, value: swept)
          in sweep.directories.entries)
        loc.diagnosticsImageStorageDirectory(
          directory,
          swept.deletedFiles,
          formatBytes(swept.freedBytes),
        ),
    ].join('\n');
  }
}
