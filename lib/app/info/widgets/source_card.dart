import 'package:discere/app/info/sources_hero_palette.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final _log = Logger.forType(SourceCard);

/// One upstream data source with its citation and a link to its site.
class SourceCard extends StatelessWidget {
  final Source source;
  final AppLocalizations loc;

  const SourceCard({required this.source, required this.loc, super.key});

  Future<void> _openWebsite() async {
    final uri = Uri.parse(source.url);
    _log.debug('Opening source website: $uri');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      key: Key('source_card_${source.id}'),
      padding: const EdgeInsets.all(AppSpacing.s32),
      decoration: BoxDecoration(
        color: SourcesHeroPalette.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  source.category.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: SourcesHeroPalette.accent,
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: SourcesHeroPalette.chipBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  source.licenseKey,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: SourcesHeroPalette.mutedText,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.heightS24,
          Text(
            source.name,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.heightS16,
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                source.citation,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: onSurface.withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          AppSpacing.heightS24,
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SourcesHeroPalette.accent,
                    SourcesHeroPalette.accentContainer,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: SourcesHeroPalette.accent.withValues(alpha: 0.2),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _openWebsite,
                  child: Padding(
                    padding: AppSpacing.buttonPaddingVertical,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          loc.sourcesVisitWebsite,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: SourcesHeroPalette.onAccent,
                          ),
                        ),
                        AppSpacing.widthS8,
                        const Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: SourcesHeroPalette.onAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
