import 'package:discere/catalog/search/search_online_button.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// What the search screen shows when the local search has settled on a
/// query and found nothing.
///
/// The online search is offered right here rather than as a separate empty
/// screen: the query is still the one the user typed, so the next step is
/// widening the search, not starting over. [onlineSearch] decides whether
/// that step is still ahead, running, or already behind — once it is behind
/// and nothing came back, the message says so instead of inviting another
/// tap that would repeat the same request.
class SearchEmptyState extends StatelessWidget {
  final OnlineSearchStage onlineSearch;
  final VoidCallback onSearchOnline;

  const SearchEmptyState({
    super.key,
    required this.onlineSearch,
    required this.onSearchOnline,
  });

  @override
  Widget build(BuildContext context) {
    final hasOnlineSearchFinished = onlineSearch == OnlineSearchStage.finished;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasOnlineSearchFinished
                  ? context.loc.speciesSearchNoResultAfterOnline
                  : context.loc.speciesSearchNoResult,
              textAlign: TextAlign.center,
            ),
            if (onlineSearch.offersAction) ...[
              const SizedBox(height: AppSpacing.s16),
              SearchOnlineButton(
                isSearchingOnline: onlineSearch.isRunning,
                onSearchOnline: onSearchOnline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
