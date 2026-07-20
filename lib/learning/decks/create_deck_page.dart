import 'dart:async';

import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CreateDeckPage extends StatefulWidget {
  final Set<String>? initialSpeciesNames;

  const CreateDeckPage({super.key, this.initialSpeciesNames});

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  late final ImageService _imageService;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _speciesController = TextEditingController();

  String? _coverImagePath; // always a local file path once set
  Language _selectedLanguage = Language.getSystemLanguage();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _imageService = Provider.of<ImageService>(context, listen: false);
    final initialSpeciesNames = widget.initialSpeciesNames;
    if (initialSpeciesNames != null && initialSpeciesNames.isNotEmpty) {
      _speciesController.text = initialSpeciesNames.join('\n');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _speciesController.dispose();
    super.dispose();
  }

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
          SnackBar(content: Text(context.loc.errorSaveImage(e.toString()))),
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
    final speciesLines = _speciesController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final deckImportService = Provider.of<DeckImportService>(
      context,
      listen: false,
    );

    try {
      final deckId = await deckImportService.importDeckFromSpeciesNames(
        name: name,
        description: description,
        scientificNames: speciesLines,
        language: _selectedLanguage,
        coverImagePath: _coverImagePath,
      );
      if (mounted && speciesLines.isNotEmpty) {
        final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
          context,
          listen: false,
        );
        unawaited(
          enrichmentQueue.scheduleDeckEnrichment(
            [deckId],
            includeINatPhotos: false,
            includeCommonNames: false,
          ),
        );
        final includeINat = await showINatDownloadDialog(context, [deckId]);
        if (includeINat && mounted) {
          await ensureNotificationPermission(context);
          unawaited(
            enrichmentQueue.scheduleDeckEnrichment(
              [deckId],
              includeINatPhotos: true,
              includeCommonNames: true,
            ),
          );
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.errorCreateDeck(e.toString()))),
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
          onPressed: () => Navigator.of(context).pop(false),
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
                DeckNameSection(
                  key: const Key('create_deck_name_field'),
                  controller: _nameController,
                ),

                const SizedBox(height: AppSpacing.s20),

                // ── Description ───────────────────────────────────────
                DeckDescriptionSection(
                  key: const Key('create_deck_description_field'),
                  controller: _descriptionController,
                ),

                const SizedBox(height: AppSpacing.s20),

                // ── Species List ──────────────────────────────────────
                Row(
                  children: [
                    Flexible(
                      child: DeckFormSectionLabel(
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
                  ),
                  decoration: InputDecoration(
                    labelText: context.loc.createSpeciesListLabel,
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

                AppSpacing.heightS24,

                // ── Cover Image ───────────────────────────────────────
                DeckCoverImageSection(
                  currentImagePath: _coverImagePath,
                  onImageSelected: _handleImageSelected,
                ),
                AppSpacing.heightS24,

                // ── Deck Language ─────────────────────────────────────
                DeckLanguageSection(
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
