import 'package:discere/catalog/search/search_failure_notice.dart';
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
///
/// With an [error] the round ended on a failure rather than on an answer, so
/// the failure takes the place of the message: "no results found" would claim
/// something this screen does not know. The action stays either way — a
/// failure is the one case where trying again is the obvious next step, and
/// replacing the whole screen with the error text would take it away.
class SearchEmptyState extends StatelessWidget {
  final OnlineSearchStage onlineSearch;
  final VoidCallback onSearchOnline;
  final Object? error;

  const SearchEmptyState({
    super.key,
    required this.onlineSearch,
    required this.onSearchOnline,
    this.error,
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
            if (error != null)
              SearchFailureNotice(error: error!)
            else
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
