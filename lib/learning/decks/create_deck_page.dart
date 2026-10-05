import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/learning/decks/species_field_presenter.dart';
import 'package:discere/learning/decks/species_field_summary.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CreateDeckPage extends StatefulWidget {
  final Set<String>? initialSpeciesNames;
  final String? initialName;
  final String? initialDescription;
  final Language? initialLanguage;

  /// Remote cover-image URL carried over from a QR/JSON import — there's no
  /// local file to preview, so it isn't shown in [DeckCoverImageField];
  /// instead it's handed to the enrichment queue on create, same as the
  /// direct-import flow does for the decks it creates.
  final String? initialImageUrl;

  const CreateDeckPage({
    super.key,
    this.initialSpeciesNames,
    this.initialName,
    this.initialDescription,
    this.initialLanguage,
    this.initialImageUrl,
  });

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  static final _log = Logger.forType(_CreateDeckPageState);

  /// How long typing has to pause before the species field is checked, so a
  /// name is not looked up once per keystroke.
  static const _speciesCheckDelay = Duration(milliseconds: 400);
  static const _speciesFieldPresenter = SpeciesFieldPresenter();

  late final ImageService _imageService;
  late final DeckImportService _deckImportService;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _speciesController = TextEditingController();

  String? _coverImagePath; // always a local file path once set
  Language _selectedLanguage = Language.getSystemLanguage();
  bool _isCreating = false;

  Timer? _speciesCheckTimer;
  String _scheduledSpeciesText = '';
  int _speciesCheckGeneration = 0;
  SpeciesFieldCheck? _speciesCheck;

  @override
  void initState() {
    super.initState();
    _imageService = Provider.of<ImageService>(context, listen: false);
    _deckImportService = Provider.of<DeckImportService>(context, listen: false);
    final initialSpeciesNames = widget.initialSpeciesNames;
    if (initialSpeciesNames != null && initialSpeciesNames.isNotEmpty) {
      _speciesController.text = initialSpeciesNames.join('\n');
    }
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.initialDescription != null) {
      _descriptionController.text = widget.initialDescription!;
    }
    if (widget.initialLanguage != null) {
      _selectedLanguage = widget.initialLanguage!;
    }
    _scheduledSpeciesText = _speciesController.text;
    _speciesController.addListener(_onSpeciesTextChanged);
    // A pre-filled list is checked right away: it arrives whole, there is
    // no typing to wait out.
    if (_scheduledSpeciesText.isNotEmpty) unawaited(_checkSpecies());
  }

  @override
  void dispose() {
    _speciesCheckTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _speciesController.dispose();
    super.dispose();
  }

  void _onSpeciesTextChanged() {
    // The controller also notifies on cursor moves; only an edit needs a
    // new check.
    final text = _speciesController.text;
    if (text == _scheduledSpeciesText) return;
    _scheduledSpeciesText = text;
    _speciesCheckTimer?.cancel();
    _speciesCheckTimer = Timer(
      _speciesCheckDelay,
      () => unawaited(_checkSpecies()),
    );
  }

  /// Looks the field's lines up with the same resolution deck creation uses,
  /// so the summary says exactly what creating the deck will find.
  Future<void> _checkSpecies() async {
    final generation = ++_speciesCheckGeneration;
    final lines = _speciesFieldPresenter.lines(_speciesController.text);
    final speciesNames = _speciesFieldPresenter.speciesNames(lines);
    try {
      final resolved = speciesNames.isEmpty
          ? const <String, String>{}
          : await _deckImportService.resolveSpeciesNames(speciesNames);
      if (!_isCurrentSpeciesCheck(generation)) return;
      setState(() {
        _speciesCheck = lines.isEmpty
            ? null
            : _speciesFieldPresenter.check(lines, resolved);
      });
    } catch (error) {
      // The summary is a preview; creating the deck resolves the names again
      // and reports its own failure.
      _log.warn('Checking the species field failed: $error');
    }
  }

  /// Whether a check that just answered is still the latest one started. A
  /// lookup for a long list can outlast the next edit's lookup; applying it
  /// then would show the verdict on text that is no longer in the field.
  bool _isCurrentSpeciesCheck(int generation) =>
      mounted && generation == _speciesCheckGeneration;

  Future<void> _handleImageSelected(String? path) async {
    if (path == null) {
      if (mounted) setState(() => _coverImagePath = null);
      return;
    }

    try {
      final savedPath = await _imageService.saveCoverImage(path);
      if (mounted) setState(() => _coverImagePath = savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc.errorSaveImage(context.loc.describeError(e)),
            ),
          ),
        );
      }
    }
  }

  // ── Create deck ───────────────────────────────────────────────────────────

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.loc.errorEnterDeckName)));
      return;
    }

    setState(() => _isCreating = true);

    final description = _descriptionController.text.trim();
    // Lines that cannot name a species are left out: no lookup, local or on
    // iNaturalist, could ever match them.
    final speciesNames = _speciesFieldPresenter.speciesNames(
      _speciesFieldPresenter.lines(_speciesController.text),
    );

    try {
      final (:deckId, :unresolvedNames) = await _deckImportService
          .importDeckFromSpeciesNames(
            name: name,
            description: description,
            scientificNames: speciesNames,
            language: _selectedLanguage,
            coverImagePath: _coverImagePath,
          );
      final coverImageUrl = _coverImagePath == null
          ? widget.initialImageUrl?.trim()
          : null;
      final hasCoverImageUrl =
          coverImageUrl != null && coverImageUrl.isNotEmpty;
      if (mounted && (speciesNames.isNotEmpty || hasCoverImageUrl)) {
        final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
          context,
          listen: false,
        );
        // Asked before anything is scheduled, as the online import does: an
        // unresolved name is queued with the consent given at that moment,
        // and the species it later resolves to keeps it. Queued before the
        // answer, it would miss the iNaturalist data the user then asks for.
        final includeINat = await showINatDownloadDialog(context, [deckId]);
        if (includeINat && mounted) {
          await ensureNotificationPermission(context);
        }
        unawaited(
          enrichmentQueue.scheduleDeckEnrichment(
            [deckId],
            includeINatPhotos: includeINat,
            includeCommonNames: includeINat,
            coverImageUrlsByDeckId: {
              if (hasCoverImageUrl) deckId: coverImageUrl,
            },
            unresolvedNamesByDeckId: {
              if (unresolvedNames.isNotEmpty) deckId: unresolvedNames,
            },
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc.errorCreateDeck(context.loc.describeError(e)),
            ),
          ),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.loc.createDeckTitle),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(
              left: AppSpacing.screenPadding,
              top: AppSpacing.groupSpacing,
              right: AppSpacing.screenPadding,
              bottom: AppSpacing.screenPadding,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Deck Name ─────────────────────────────────────────
                DeckNameField(
                  key: const Key('create_deck_name_field'),
                  controller: _nameController,
                ),

                const SizedBox(height: AppSpacing.s20),

                // ── Description ───────────────────────────────────────
                DeckDescriptionField(
                  key: const Key('create_deck_description_field'),
                  controller: _descriptionController,
                ),

                const SizedBox(height: AppSpacing.s20),

                // ── Species List ──────────────────────────────────────
                Row(
                  children: [
                    Flexible(
                      child: DeckFormFieldLabel(
                        label: context.loc.createSpeciesListLabel,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: AppSpacing.s4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.loc.createSpeciesScientificNamesTag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.heightS8,
                TextField(
                  key: const Key('create_deck_species_field'),
                  controller: _speciesController,
                  minLines: 5,
                  maxLines: 10,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onPrimaryContainer,
                  ),
                  decoration: InputDecoration(
                    hintText: context.loc.createSpeciesListHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                AppSpacing.heightS4,
                Text(
                  context.loc.createSpeciesInstruction,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_speciesCheck case final check?)
                  SpeciesFieldSummary(check: check),

                AppSpacing.heightS24,

                // ── Cover Image ───────────────────────────────────────
                DeckCoverImageField(
                  currentImagePath: _coverImagePath,
                  onImageSelected: _handleImageSelected,
                ),
                AppSpacing.heightS24,

                // ── Deck Language ─────────────────────────────────────
                DeckLanguageField(
                  value: _selectedLanguage,
                  onChanged: (newValue) {
                    setState(() => _selectedLanguage = newValue);
                  },
                ),

                // Spacer so content clears the fixed footer
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.screenPadding,
            top: AppSpacing.s12,
            right: AppSpacing.screenPadding,
            bottom: AppSpacing.screenPadding,
          ),
          child: FilledButton.icon(
            key: const ValueKey('create_deck_submit_button'),
            onPressed: _isCreating ? null : _create,
            icon: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_circle_outline),
            label: Text(context.loc.createButton),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
