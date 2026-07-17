import 'package:flutter/widgets.dart';

/// How an enrichment status is rendered in the UI: a short text plus icon
/// and color. Produced by the status/style presenters and consumed by the
/// deck-card hint and the manual-enrichment section.
class EnrichmentStatusVisual {
  final String text;
  final IconData icon;
  final Color color;

  const EnrichmentStatusVisual({
    required this.text,
    required this.icon,
    required this.color,
  });
}
