import 'dart:async';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/edit/inat_enrichment_offer.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_update_diff.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the species-level diff between [deckId]'s current state and its
/// online catalog entry [remote], and lets the user pick whether to apply the
/// additions, the removals (which drops FSRS progress for those species),
/// both, or neither. Returns once the dialog is dismissed; the caller doesn't
/// need the result — [DeckUpdateService] is refreshed internally.
Future<void> showDeckUpdateDialog(
  BuildContext context,
  String deckId,
  CreateDeck remote,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DeckUpdateDialog(deckId: deckId, remote: remote),
  );
}

class _DeckUpdateDialog extends StatefulWidget {
  final String deckId;
  final CreateDeck remote;

  const _DeckUpdateDialog({required this.deckId, required this.remote});

  @override
  State<_DeckUpdateDialog> createState() => _DeckUpdateDialogState();
}

class _DeckUpdateDialogState extends State<_DeckUpdateDialog> {
  late final Future<DeckUpdateDiff> _diffFuture;
  DeckUpdateDiff? _diff;
  bool _includeAdditions = true;
  bool _includeRemovals = false;
  bool _isApplying = false;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _diffFuture = context.read<DeckImportService>().diffForUpdate(
      widget.deckId,
      widget.remote,
    );
    // FutureBuilder rebuilding when _diffFuture completes only rebuilds its
    // own subtree (the dialog content) — the "Apply" button lives in
    // AlertDialog.actions, built by this State directly, so it needs its
    // own setState to notice _diff went from null to non-null. Without
    // this, the button stayed disabled until some unrelated interaction
    // (e.g. toggling a checkbox) happened to trigger a rebuild here.
    unawaited(
      _diffFuture.then((diff) {
        if (mounted) setState(() => _diff = diff);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return AlertDialog(
      icon: const Icon(Icons.system_update_alt, size: 32),
      title: Text(loc.deckUpdateDialogTitle),
      content: SingleChildScrollView(
        child: FutureBuilder<DeckUpdateDiff>(
          future: _diffFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('${loc.error}: ${snapshot.error}');
            }
            return _buildDiffContent(context, snapshot.data!);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(loc.commonCancel),
        ),
        FilledButton(
          key: const Key('deck_update_apply_button'),
          onPressed: _diff == null || _isApplying ? null : _apply,
          child: _isApplying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(loc.deckUpdateApplyButton),
        ),
      ],
    );
  }

  Widget _buildDiffContent(BuildContext context, DeckUpdateDiff diff) {
    final loc = context.loc;
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    if (!diff.hasChanges) {
      return Text(loc.deckUpdateNoChanges);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (diff.addedSpecies.isNotEmpty)
          CheckboxListTile(
            key: const Key('deck_update_add_checkbox'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeAdditions,
            onChanged: (value) =>
                setState(() => _includeAdditions = value ?? false),
            title: Text(
              loc.deckUpdateAddSpeciesLabel(diff.addedSpecies.length),
            ),
            subtitle: _SpeciesNameList(species: diff.addedSpecies),
          ),
        if (diff.removedSpecies.isNotEmpty)
          CheckboxListTile(
            key: const Key('deck_update_remove_checkbox'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: errorColor,
            value: _includeRemovals,
            onChanged: (value) =>
                setState(() => _includeRemovals = value ?? false),
            title: Text(
              loc.deckUpdateRemoveSpeciesLabel(diff.removedSpecies.length),
              style: TextStyle(color: errorColor),
            ),
            subtitle: _SpeciesNameList(species: diff.removedSpecies),
          ),
        if (_applyError != null) ...[
          const SizedBox(height: 12),
          Text(
            loc.deckUpdateApplyError(_applyError!),
            style: TextStyle(color: errorColor),
          ),
        ],
      ],
    );
  }

  Future<void> _apply() async {
    final diff = _diff;
    if (diff == null) return;
    setState(() {
      _isApplying = true;
      _applyError = null;
    });
    try {
      final deckImportService = context.read<DeckImportService>();
      final unresolvedNames = await deckImportService.applyDeckUpdate(
        deckId: widget.deckId,
        remote: widget.remote,
        diff: diff,
        includeAdditions: _includeAdditions,
        includeRemovals: _includeRemovals,
      );
      if (!mounted) return;
      context.read<DeckUpdateService>().clearUpdate(widget.deckId);

      final addedAnything =
          _includeAdditions &&
          (diff.addedSpecies.isNotEmpty || diff.unresolvedAddedNames.isNotEmpty);
      // Keep this dialog mounted through the enrichment offer — it drives
      // its own follow-up dialog and (if accepted) a second
      // scheduleDeckEnrichment call gated on the same context still being
      // mounted, same as EditDeckPage's save flow. Popping first would tear
      // this context down before the user even answers the offer, silently
      // skipping that second call.
      if (addedAnything) {
        await offerINatEnrichmentForNewSpecies(
          context,
          widget.deckId,
          unresolvedNames: unresolvedNames,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
          _applyError = e.toString();
        });
      }
    }
  }
}

class _SpeciesNameList extends StatelessWidget {
  final List<Species> species;

  const _SpeciesNameList({required this.species});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 120),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: species
              .map(
                (s) => Text(
                  s.getBinomialName(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}
