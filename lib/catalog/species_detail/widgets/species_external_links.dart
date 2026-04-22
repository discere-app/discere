import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SpeciesExternalLinks extends StatefulWidget {
  final Species species;

  const SpeciesExternalLinks({super.key, required this.species});

  @override
  State<SpeciesExternalLinks> createState() => _SpeciesExternalLinksState();
}

class _SpeciesExternalLinksState extends State<SpeciesExternalLinks> {
  static final _log = Logger.forType(_SpeciesExternalLinksState);
  final ExternalIdRepository _externalIdRepository = ExternalIdRepository();
  final ExternalIdCacheRepository _externalIdCacheRepository =
      ExternalIdCacheRepository();
  late Future<List<_ExternalSpeciesLink>> _futureLinks;

  @override
  void initState() {
    super.initState();
    _futureLinks = _loadLinks();
  }

  @override
  void didUpdateWidget(covariant SpeciesExternalLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.species != widget.species) {
      _futureLinks = _loadLinks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<_ExternalSpeciesLink>>(
      future: _futureLinks,
      builder: (context, snapshot) {
        final links = snapshot.data ?? const <_ExternalSpeciesLink>[];
        if (links.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.speciesDetailExternalLinks,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s10,
              runSpacing: AppSpacing.s10,
              children: links
                  .map(
                    (link) => _ExternalLinkChip(
                      link: link,
                      onTap: () => _openLink(link.url),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Future<List<_ExternalSpeciesLink>> _loadLinks() async {
    final sourceService = Provider.of<SourceService>(context, listen: false);
    final sources = await sourceService.getAllSources();
    final sourcesById = {for (final source in sources) source.id: source};
    final links = <_ExternalSpeciesLink>[];
    final species = widget.species;

    final primarySource = sourcesById[species.externalSource];
    if (primarySource != null) {
      final primaryUrl = _buildPrimarySourceUrl(primarySource, species);
      if (primaryUrl != null) {
        links.add(_ExternalSpeciesLink(source: primarySource, url: primaryUrl));
      }
    }

    final iNatSource = sourcesById['inaturalist'];
    if (iNatSource != null) {
      final iNatId = await _resolveINaturalistId(species.id);
      final iNatUrl = iNatId != null
          ? Uri.parse('${iNatSource.url}/taxa/$iNatId')
          : Uri.parse(
              '${iNatSource.url}/taxa/search?q=${Uri.encodeComponent(species.getBinomialName())}',
            );
      links.add(_ExternalSpeciesLink(source: iNatSource, url: iNatUrl));
    }

    return links;
  }

  Uri? _buildPrimarySourceUrl(Source source, Species species) {
    return source.buildSpeciesUrl(species);
  }

  Future<String?> _resolveINaturalistId(String speciesId) async {
    final referenceId = await _externalIdRepository.getExternalId(
      speciesId,
      'inaturalist',
    );
    if (referenceId != null && referenceId.isNotEmpty) return referenceId;

    final cachedId = await _externalIdCacheRepository.getExternalId(
      speciesId,
      'inaturalist',
    );
    if (cachedId != null && cachedId.isNotEmpty) return cachedId;

    return null;
  }

  Future<void> _openLink(Uri url) async {
    _log.debug('Opening species external link: $url');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

class _ExternalLinkChip extends StatelessWidget {
  final _ExternalSpeciesLink link;
  final VoidCallback onTap;

  const _ExternalLinkChip({required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                link.source.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalSpeciesLink {
  final Source source;
  final Uri url;

  const _ExternalSpeciesLink({required this.source, required this.url});
}
