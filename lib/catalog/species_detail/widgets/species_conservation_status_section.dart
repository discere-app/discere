import 'package:discere/catalog/common/iucn_status_chip.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/iucn_status.dart';
import 'package:discere/catalog/service/species_inat_metadata_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the species' IUCN Red List category as a segmented status bar,
/// matching the standard IUCN/Wikipedia badge design — recreated natively
/// (no SVG asset/dependency needed) since it's fully derived from the
/// category code alone.
class SpeciesConservationStatusSection extends StatefulWidget {
  final String speciesId;

  const SpeciesConservationStatusSection({super.key, required this.speciesId});

  @override
  State<SpeciesConservationStatusSection> createState() =>
      _SpeciesConservationStatusSectionState();
}

class _SpeciesConservationStatusSectionState
    extends State<SpeciesConservationStatusSection> {
  late Future<IucnStatus?> _futureStatus;

  @override
  void initState() {
    super.initState();
    _futureStatus = _loadStatus();
  }

  @override
  void didUpdateWidget(covariant SpeciesConservationStatusSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speciesId != widget.speciesId) {
      _futureStatus = _loadStatus();
    }
  }

  Future<IucnStatus?> _loadStatus() async {
    final metadataService = Provider.of<SpeciesInatMetadataService>(
      context,
      listen: false,
    );
    final raw = await metadataService.ensureCached(
      widget.speciesId,
      ExternalIdProvider.iucnStatus,
    );
    if (raw == null || raw.isEmpty) return null;
    return IucnStatus.fromRaw(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<IucnStatus?>(
      future: _futureStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) return const SizedBox.shrink();

        return DetailSectionCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.speciesDetailConservationStatus,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                IucnStatusChip(status: status),
              ],
            ),
          ),
        );
      },
    );
  }
}
