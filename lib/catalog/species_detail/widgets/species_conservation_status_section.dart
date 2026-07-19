import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/iucn_status.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

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
  final ExternalIdCacheRepository _externalIdCacheRepository =
      ExternalIdCacheRepository();
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
    final raw = await _externalIdCacheRepository.getExternalId(
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
                _IucnStatusBadge(status: status),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IucnStatusBadge extends StatelessWidget {
  final IucnStatus status;

  const _IucnStatusBadge({required this.status});

  static const Map<IucnStatus, Color> _spectrumColors = {
    IucnStatus.extinct: Color(0xFF000000),
    IucnStatus.extinctInTheWild: Color(0xFF3F3F3F),
    IucnStatus.criticallyEndangered: Color(0xFFD81E05),
    IucnStatus.endangered: Color(0xFFFC7F3F),
    IucnStatus.vulnerable: Color(0xFFF9E814),
    IucnStatus.nearThreatened: Color(0xFFCCE226),
    IucnStatus.leastConcern: Color(0xFF60C659),
  };
  static const Color _neutralColor = Color(0xFFB5B5B5);

  Color get _chipColor => _spectrumColors[status] ?? _neutralColor;

  Color _onColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.isOnThreatSpectrum) ...[
          Row(
            children: IucnStatus.threatSpectrum
                .map((step) {
                  final isCurrent = step == status;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: isCurrent ? 22 : 12,
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          color: _spectrumColors[step],
                          borderRadius: BorderRadius.circular(3),
                          border: isCurrent
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 1.5,
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: AppSpacing.s10),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: _chipColor,
                borderRadius: BorderRadius.circular(6),
                border: status.isOnThreatSpectrum
                    ? null
                    : Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                status.code,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _onColor(_chipColor),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              _label(context.loc, status),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _label(AppLocalizations loc, IucnStatus status) {
    switch (status) {
      case IucnStatus.extinct:
        return loc.speciesIucnExtinct;
      case IucnStatus.extinctInTheWild:
        return loc.speciesIucnExtinctInTheWild;
      case IucnStatus.criticallyEndangered:
        return loc.speciesIucnCriticallyEndangered;
      case IucnStatus.endangered:
        return loc.speciesIucnEndangered;
      case IucnStatus.vulnerable:
        return loc.speciesIucnVulnerable;
      case IucnStatus.nearThreatened:
        return loc.speciesIucnNearThreatened;
      case IucnStatus.leastConcern:
        return loc.speciesIucnLeastConcern;
      case IucnStatus.dataDeficient:
        return loc.speciesIucnDataDeficient;
      case IucnStatus.notEvaluated:
        return loc.speciesIucnNotEvaluated;
    }
  }
}
