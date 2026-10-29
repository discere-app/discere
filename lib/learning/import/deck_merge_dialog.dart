import 'package:discere/learning/import/deck_merge_subdeck_selection.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks whether to carry out [plan]: names the target and the decks it
/// takes progress from, which of them go and which stay, and the species
/// whose progress is lost — and, for a target with subdecks, lets the user
/// choose the ones to have on, starting from the plan's suggestion.
/// Resolves to the chosen subdecks on confirmation (empty for a target
/// without any), and to `null` when the user declines.
Future<Set<String>?> showDeckMergeDialog(
  BuildContext context,
  DeckMergePlan plan,
) => showDialog<Set<String>>(
  context: context,
  builder: (_) => _DeckMergeDialog(plan: plan),
);

class _DeckMergeDialog extends StatefulWidget {
  final DeckMergePlan plan;

  const _DeckMergeDialog({required this.plan});

  @override
  State<_DeckMergeDialog> createState() => _DeckMergeDialogState();
}

class _DeckMergeDialogState extends State<_DeckMergeDialog> {
  late Set<String> _activeSubdeckIds = widget.plan.suggestedActiveSubdeckIds;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final loc = context.loc;
    final theme = Theme.of(context);
    final kept = [
      for (final deck in plan.superseded)
        if (!plan.deleted.contains(deck)) deck.name,
    ];

    return AlertDialog(
      icon: const Icon(Icons.merge_type, size: 32),
      title: Text(loc.deckMergeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.deckMergeDialogMessage(
                plan.superseded.length,
                plan.entry.name,
              ),
            ),
            const SizedBox(height: 4),
            for (final deck in plan.superseded)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  deck.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (plan.deleted.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                loc.deckMergeDialogRemoved(
                  plan.deleted.length,
                  plan.deleted.map((deck) => deck.name).join(', '),
                ),
              ),
            ],
            if (kept.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(loc.deckMergeDialogKept(kept.length, kept.join(', '))),
            ],
            if (plan.lostSpeciesNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                loc.deckMergeDialogLostSpecies(plan.lostSpeciesNames.length),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final name in plan.lostSpeciesNames)
                        Text(
                          name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (plan.subdecks.isNotEmpty) ...[
              const SizedBox(height: 12),
              DeckMergeSubdeckSelection(
                subdecks: plan.subdecks,
                membership: plan.subdeckMembership,
                activeSubdeckIds: _activeSubdeckIds,
                onChanged: (subdeckId, active) => setState(
                  () => _activeSubdeckIds = active
                      ? {..._activeSubdeckIds, subdeckId}
                      : _activeSubdeckIds.difference({subdeckId}),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('deck_merge_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.commonCancel),
        ),
        FilledButton(
          key: const Key('deck_merge_confirm_button'),
          onPressed: () => Navigator.of(context).pop(_activeSubdeckIds),
          child: Text(loc.deckMergeConfirmButton),
        ),
      ],
    );
  }
}
