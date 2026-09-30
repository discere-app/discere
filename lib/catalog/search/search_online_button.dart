import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// The "keep looking online" action offered once the local search has
/// settled without answering the query.
///
/// It doubles as the progress indicator for the online search it starts:
/// while that runs the button is disabled and shows a spinner in place of
/// its icon, so the wait is visible where the action was taken rather than
/// somewhere else on the screen.
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
