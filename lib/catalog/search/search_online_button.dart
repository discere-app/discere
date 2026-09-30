import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// The "keep looking online" action offered once the local search has
/// settled without answering the query.
///
/// It is also the progress indicator for the round it starts: while
/// [isSearchingOnline] holds, the icon becomes a spinner and the button
/// takes no taps, so the wait is visible on screen and a second request
/// cannot land.
/// Both call sites take the button out of the tree once the round is over,
/// so the disabled state is the only thing that has to hold back a repeat
/// request.
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
