import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The line that says a search round ended on an error, shown alongside the
/// results that survived it.
///
/// Deliberately silent about which round failed. The state carries one
/// error, set by the quick search, the widening full search and the online
/// round alike, and naming one of them would be a guess — the same guess
/// the retry offered below this line does not have to make, since it starts
/// the only round the user can start again anyway.
class SearchFailureNotice extends StatelessWidget {
  final Object error;

  const SearchFailureNotice({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          AppSpacing.widthS8,
          Expanded(
            child: Text(
              context.loc.speciesSearchFailed(context.loc.describeError(error)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
