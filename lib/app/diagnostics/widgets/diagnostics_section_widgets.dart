/// The small repeated pieces the diagnostics sections are built from.
///
/// Grouped in one file rather than four, following `shared/ui/
/// detail_content_widgets.dart`: each is a handful of lines and they only
/// make sense as a set — a section header without an empty row is not a
/// thing this page has.
library;

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Title row at the top of a multi-tile card.
class DiagnosticsSectionHeader extends StatelessWidget {
  final String title;

  const DiagnosticsSectionHeader({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// Stands in for an expansion tile's children when there is nothing to list.
class DiagnosticsEmptyRow extends StatelessWidget {
  const DiagnosticsEmptyRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(context.loc.diagnosticsNoData),
      ),
    );
  }
}

/// One labelled number in the summary card's at-a-glance row.
class DiagnosticsMetricChip extends StatelessWidget {
  final String label;
  final String value;

  const DiagnosticsMetricChip({
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// When the snapshot on screen was last taken. The page refreshes itself as
/// the enrichment pipeline reports progress, so without this the numbers
/// would change with no indication of how current they are.
class DiagnosticsLastRefreshedRow extends StatelessWidget {
  final DateTime? lastRefreshedAt;

  const DiagnosticsLastRefreshedRow({required this.lastRefreshedAt, super.key});

  @override
  Widget build(BuildContext context) {
    final at = lastRefreshedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.sync,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            at == null
                ? '—'
                : context.loc.diagnosticsLastRefreshedAt(
                    MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(at)),
                  ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
