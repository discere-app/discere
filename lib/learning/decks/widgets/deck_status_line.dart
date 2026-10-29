import 'package:flutter/material.dart';

/// An icon-plus-text status line on a deck card, shared by the enrichment,
/// update and replacement hints so all three read as one kind of line.
///
/// The text wraps instead of being cut off: it carries information (how
/// long ago a deck was enriched, which deck replaces this one) that an
/// ellipsis would hide entirely at a large system font size or with a long
/// deck name. The icons align with the first line, so a wrapped text keeps
/// them next to where it starts rather than floating between its lines; at
/// the default text scale a 14px icon matches the height of a `bodySmall`
/// line.
class DeckStatusLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  /// Shown after the text, e.g. a hint that the line can be tapped.
  final Widget? trailing;

  const DeckStatusLine({
    required this.icon,
    required this.text,
    required this.color,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing],
        ],
      ),
    );
  }
}
