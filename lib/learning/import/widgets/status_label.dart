import 'package:discere/learning/import/import_online_deck_presenter.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

class StatusLabel extends StatelessWidget {
  final ImportOnlineDeckStatus status;

  /// Named for [ImportOnlineDeckStatus.supersedesLocal].
  final List<String> supersededDeckNames;

  const StatusLabel({
    super.key,
    required this.status,
    this.supersededDeckNames = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (status) {
      ImportOnlineDeckStatus.notImported => (null, null, null),
      ImportOnlineDeckStatus.upToDate => (
        Icons.check_circle_outline,
        theme.colorScheme.outline,
        context.loc.importOnlineAlreadyImported,
      ),
      ImportOnlineDeckStatus.updateAvailable => (
        Icons.system_update_alt,
        OceanColors.success,
        context.loc.importOnlineUpdateAvailable,
      ),
      ImportOnlineDeckStatus.supersedesLocal => (
        Icons.merge_type,
        OceanColors.primaryBlue,
        context.loc.importOnlineSupersedesLocal(
          supersededDeckNames.length,
          supersededDeckNames.join(', '),
        ),
      ),
    };
    if (icon == null || color == null || text == null) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        // Flexible: a supersession names decks, and can run long.
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
