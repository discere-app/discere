import 'package:discere/catalog/search/search_online_button.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// What the search screen shows when the local search has settled on a
/// query and found nothing.
///
/// The online search is offered right here rather than as a separate empty
/// screen: the query is still the one the user typed, so the next step is
/// widening the search, not starting over.
class SearchEmptyState extends StatelessWidget {
  final bool showOnlineSearchAction;
  final bool isSearchingOnline;
  final VoidCallback onSearchOnline;

  const SearchEmptyState({
    super.key,
    required this.showOnlineSearchAction,
    required this.isSearchingOnline,
    required this.onSearchOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.loc.speciesSearchNoResult),
            if (showOnlineSearchAction) ...[
              const SizedBox(height: AppSpacing.s16),
              SearchOnlineButton(
                isSearchingOnline: isSearchingOnline,
                onSearchOnline: onSearchOnline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
