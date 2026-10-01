import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The line that says the online round ran and added nothing, shown under
/// the results it did not widen.
///
/// Without it the round is invisible from the results screen: the action
/// leaves the tree once it is behind, the list looks exactly as before, and
/// nothing distinguishes "searched online, nothing more out there" from
/// "never tapped it". The empty-results screen says this already, through
/// `speciesSearchNoResultAfterOnline`; this is the same statement for the
/// screen that does have results.
class SearchOnlineExhaustedNotice extends StatelessWidget {
  const SearchOnlineExhaustedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        context.loc.speciesSearchOnlineFoundNothingMore,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
