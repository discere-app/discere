import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/language.dart';
import '../../service/common/image_service.dart';
import '../../service/common/import_export_service.dart';
import '../components/image_picker.dart';

class CreateDeckPage extends StatefulWidget {
  const CreateDeckPage({super.key});

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.loc.errorEnterDeckName)),
      );
      return;
    }

    setState(() => _isCreating = true);

    final description = _descriptionController.text.trim();
    final speciesLines = _speciesController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final importExportService =
        Provider.of<ImportExportService>(context, listen: false);

    try {
      await importExportService.importDeckFromSpeciesNames(
        name: name,
        description: description,
        scientificNames: speciesLines,
        language: _selectedLanguage,
        coverImagePath: _coverImagePath,
      );
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Deck Name ─────────────────────────────────────────
                _SectionLabel(label: context.loc.createDeckNameLabel),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('create_deck_name_field'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.loc.createDeckNameLabel,
                    hintText: context.loc.createDeckNameHint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────────
                _SectionLabel(label: context.loc.createDescriptionLabel),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('create_deck_description_field'),
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.loc.createDescriptionLabel,
                    hintText: context.loc.createDescriptionHint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Species List ──────────────────────────────────────
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.loc.createSpeciesListLabel,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
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
                const SizedBox(height: 8),
                TextField(
                  key: const Key('create_deck_species_field'),
                  controller: _speciesController,
                  minLines: 5,
                  maxLines: 10,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: context.loc.createSpeciesListLabel,
                    hintText: context.loc.createSpeciesListHint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.loc.createSpeciesInstruction,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Cover Image ───────────────────────────────────────
                _SectionLabel(label: context.loc.createCoverImageLabel),
                const SizedBox(height: 10),
                ImagePicker(
                  currentImagePath: _coverImagePath,
                  getSearchQuery: () => _nameController.text.trim(),
                  onImageSelected: _handleImageSelected,
                ),
                const SizedBox(height: 24),

                // ── Deck Language ─────────────────────────────────────
                _SectionLabel(label: context.loc.createDeckLanguageLabel),
                const SizedBox(height: 8),
                DropdownButtonFormField<Language>(
                  initialValue: _selectedLanguage,
                  decoration: InputDecoration(
                    labelText: context.loc.createDeckLanguageLabel,
                    hintText: context.loc.createDeckLanguageHint,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: Language.values.map((lang) {
                    return DropdownMenuItem<Language>(
                      value: lang,
                      child: Text(context.loc.commonLanguages(lang.name)),
                    );
                  }).toList(),
                  onChanged: (Language? newValue) {
                    if (newValue != null) {
                      setState(() => _selectedLanguage = newValue);
                    }
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton.icon(
            key: const ValueKey('create_deck_submit_button'),
            onPressed: _isCreating ? null : _create,
            icon: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_circle_outline),
            label: Text(context.loc.createButton),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label helper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
