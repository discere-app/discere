import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The expanding "add" button: tapping it reveals labelled options for
/// creating and importing a deck. Owns its expanded state, since nothing
/// outside cares whether it is open.
class MainScreenFab extends StatefulWidget {
  final Future<void> Function() onCreateDeck;
  final Future<void> Function() onImportDeck;

  const MainScreenFab({
    required this.onCreateDeck,
    required this.onImportDeck,
    super.key,
  });

  @override
  State<MainScreenFab> createState() => _MainScreenFabState();
}

class _MainScreenFabState extends State<MainScreenFab> {
  bool _expanded = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _expanded = false);
    await action();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded) ...[
          _FabOption(
            icon: Icons.create_new_folder_outlined,
            label: context.loc.createDeckTitle,
            heroTag: 'fab-create',
            onPressed: () => _run(widget.onCreateDeck),
          ),
          AppSpacing.heightS12,
          _FabOption(
            icon: Icons.download_for_offline_outlined,
            label: context.loc.importDeckTitle,
            heroTag: 'fab-import',
            onPressed: () => _run(widget.onImportDeck),
          ),
          AppSpacing.heightS12,
        ],
        FloatingActionButton(
          key: const ValueKey('main-fab'),
          heroTag: 'main-fab',
          onPressed: () => setState(() => _expanded = !_expanded),
          child: AnimatedRotation(
            turns: _expanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

/// One revealed option: a label card beside a small action button.
class _FabOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String heroTag;
  final VoidCallback onPressed;

  const _FabOption({
    required this.icon,
    required this.label,
    required this.heroTag,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        AppSpacing.widthS12,
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ],
    );
  }
}
