import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// The "keep looking online" action offered once the local search has
/// settled without answering the query.
///
/// The [isSearchingOnline] branch — disabled button, spinner in place of the
/// icon — is currently unreachable, and the button is not in fact the progress
/// indicator for the search it starts. Both call sites gate it on
/// `shouldOfferOnlineSearch`, which requires `!isSearchingOnline &&
/// !hasPerformedOnlineSearch`, and `SpeciesSearchController.searchOnline` sets
/// both before it awaits — so the button leaves the tree on the same frame it
/// is tapped and never comes back for that query. Issue #261 decides which way
/// to resolve that: drop the branch, or stop gating on those two flags so the
/// spinner actually shows.
class SearchOnlineButton extends StatelessWidget {
  final bool isSearchingOnline;
  final VoidCallback onSearchOnline;

  const SearchOnlineButton({
    super.key,
    required this.isSearchingOnline,
    required this.onSearchOnline,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isSearchingOnline ? null : onSearchOnline,
        icon: isSearchingOnline
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_outlined),
        label: Text(
          isSearchingOnline
              ? context.loc.speciesSearchSearchingOnline
              : context.loc.speciesSearchSearchOnline,
        ),
      ),
    );
  }
}
