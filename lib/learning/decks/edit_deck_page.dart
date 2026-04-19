import 'dart:async';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import '../../theme/app_spacing.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/ui/image_picker.dart';

class EditDeckPage extends StatefulWidget {
  final BaseDeck deck;
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;

  const EditDeckPage({
    required this.deck,
    required this.buildSpeciesDetailPage,
    super.key,
  });

  @override
  State<EditDeckPage> createState() => _EditDeckPageState();
}

class _EditDeckPageState extends State<EditDeckPage> {
  static const SpeciesListItemPresenter _speciesListItemPresenter =
      SpeciesListItemPresenter();
  late final DecksService _decksService;
  late final ImageService _imageService;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late Future<List<Species>> _speciesFuture;
  List<Species> _species = [];
  bool _isSaving = false;

  String? _coverImagePath;
  late Language _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _decksService = Provider.of<DecksService>(context, listen: false);
    _imageService = Provider.of<ImageService>(context, listen: false);
    _nameController = TextEditingController(text: widget.deck.name);
    _descriptionController = TextEditingController(
      text: widget.deck.description,
    );
    _coverImagePath = widget.deck.coverImagePath;
    _selectedLanguage = widget.deck.language;
    _speciesFuture = _loadSpecies();
  }

  Future<List<Species>> _loadSpecies() async {
    final list = await _decksService.getSpeciesByDeckId(widget.deck.id!);
    if (mounted) setState(() => _species = list);
    return list;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final updated = BaseDeck(
      widget.deck.id,
      _nameController.text.trim(),
      _descriptionController.text.trim(),
      coverImagePath: _coverImagePath,
      language: _selectedLanguage,
    );
    await _decksService.updateDeck(updated, _species.map((s) => s.id).toSet());
    if (mounted) Navigator.of(context).pop(true);
  }

  void _removeSpecies(Species s) => setState(() => _species.remove(s));

  Future<void> _openAddSpeciesSheet() async {
    final Species? result = await showModalBottomSheet<Species>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddSpeciesSheet(
        language: _selectedLanguage,
        alreadyAdded: _species.map((s) => s.id).toSet(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _species.add(result));
    }
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

  Future<void> _openSpeciesDetail(Species species) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            widget.buildSpeciesDetailPage(species.id, _selectedLanguage),
      ),
    );
  }

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
        title: Text(context.loc.editDeckTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.elementSpacing),
            child: FilledButton(
              key: const Key('edit_deck_save_button'),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.loc.editSaveButton),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSpeciesSheet,
        icon: const Icon(Icons.add),
        label: Text(context.loc.editAddSpeciesButton),
      ),
      body: FutureBuilder<List<Species>>(
        future: _speciesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _species.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildContent(colorScheme, theme);
        },
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
            AppSpacing.elementSpacing,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                context.loc.createDeckNameLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              TextField(
                key: const Key('edit_deck_name_field'),
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDeckNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              Text(
                context.loc.createDescriptionLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              TextField(
                key: const Key('edit_deck_description_field'),
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDescriptionHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              AppSpacing.heightS24,
              Text(
                context.loc.createCoverImageLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              ImagePicker(
                currentImagePath: _coverImagePath,
                getSearchQuery: () => _nameController.text.trim(),
                onImageSelected: _handleImageSelected,
              ),
              AppSpacing.heightS24,
              Text(
                context.loc.createDeckLanguageLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              DropdownButtonFormField<Language>(
                initialValue: _selectedLanguage,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
              AppSpacing.heightS24,
              Text(
                context.loc.editSpeciesInDeck(_species.length),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppSpacing.heightS12,
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.zero,
          sliver: SliverList.builder(
            itemCount: _species.length,
            itemBuilder: (context, index) {
              final s = _species[index];
              return SpeciesListItem(
                key: ValueKey(s.id),
                item: _speciesListItemPresenter.presentSpecies(
                  s,
                  _selectedLanguage,
                ),
                onTap: () => _openSpeciesDetail(s),
                onDelete: () => _removeSpecies(s),
                deleteTooltip: context.loc.editRemoveTooltip,
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-species bottom sheet with inline search
// ─────────────────────────────────────────────────────────────────────────────

class _AddSpeciesSheet extends StatefulWidget {
  final Language language;
  final Set<String> alreadyAdded;

  const _AddSpeciesSheet({required this.language, required this.alreadyAdded});

  @override
  State<_AddSpeciesSheet> createState() => _AddSpeciesSheetState();
}

class _AddSpeciesSheetState extends State<_AddSpeciesSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _searchController.text.trim();
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final repo = Provider.of<SearchRepository>(context, listen: false);
    final results = await repo.searchAll(q);
    if (!mounted) return;
    setState(() {
      _results = results
          .where((r) => r.type == SearchEntityType.species)
          .toList();
      _loading = false;
    });
  }

  Future<void> _selectResult(SearchResult result) async {
    final decksService = Provider.of<DecksService>(context, listen: false);
    final speciesList = await decksService.getSpeciesByIds({result.id});
    if (!mounted) return;
    if (speciesList.isNotEmpty) {
      Navigator.of(context).pop(speciesList.first);
    }
  }

  String _displayName(SearchResult r) {
    return resolvePrimaryCommonName(
      r.commonNames,
      widget.language,
      fallback: r.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    context.loc.editAddSpeciesButton,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.loc.editSearchSpeciesHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _results = [];
                              _query = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildResultsList(scrollController, colorScheme, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsList(
    ScrollController scrollController,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(
          context.loc.editTypeToSearch,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.loc.editNoSpeciesFound,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final alreadyIn = widget.alreadyAdded.contains(r.id);
        final name = _displayName(r);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(
            name,
            style: alreadyIn
                ? TextStyle(color: colorScheme.onSurfaceVariant)
                : null,
          ),
          subtitle: Text(
            r.name,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          trailing: alreadyIn
              ? Icon(Icons.check, color: colorScheme.primary)
              : const Icon(Icons.add),
          onTap: alreadyIn ? null : () => _selectResult(r),
        );
      },
    );
  }
}
