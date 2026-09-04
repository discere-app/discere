import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Bookmark toggle shown on both faces of a flashcard (front image header,
/// no-photo placeholder, and back content) — a single shared widget so the
/// three call sites don't each carry their own copy of this logic.
class WatchlistButton extends StatelessWidget {
  final String speciesId;
  final GlobalKey? buttonKey;

  /// Glass-effect variant for use over an image; plain icon color otherwise.
  final bool glass;

  const WatchlistButton({
    required this.speciesId,
    this.buttonKey,
    this.glass = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<WatchlistService>(
      builder: (context, watchlistService, _) {
        final isWatchlisted = watchlistService.getSpecies().contains(
          speciesId,
        );
        final icon = IconButton(
          key: buttonKey,
          icon: Icon(
            isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
            color: isWatchlisted
                ? Colors.amber.shade400
                : (glass
                      ? Colors.white.withValues(alpha: 0.85)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          onPressed: () {
            if (isWatchlisted) {
              watchlistService.removeSpecies(speciesId);
            } else {
              watchlistService.addSpecies(speciesId);
            }
          },
        );
        return glass ? _GlassButton(child: icon) : icon;
      },
    );
  }
}

class _GlassButton extends StatelessWidget {
  final Widget child;

  const _GlassButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}
