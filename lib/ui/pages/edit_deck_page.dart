import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species.dart';
import '../../model/language.dart';
import '../../model/learning/base_deck.dart';
import '../../model/search/search_result.dart';
import '../../persistence/search_repository.dart';
import '../../service/common/language_service.dart';
import '../../service/common/image_service.dart';
import '../../service/learning/decks_service.dart';
import '../components/cover_image_picker.dart';
import '../components/image_search_sheet.dart';
import 'package:image_picker/image_picker.dart';

class EditDeckPage extends StatefulWidget {
  final BaseDeck deck;

  const EditDeckPage({required this.deck, super.key});

  @override
  State<EditDeckPage> createState() => _EditDeckPageState();
}

class _EditDeckPageState extends State<EditDeckPage> {
  late final DecksService _decksService;
  late final LanguageService _languageService;
  late final ImageService _imageService;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late Future<List<Species>> _speciesFuture;
  List<Species> _species = [];
  bool _isSaving = false;

  String? _coverImagePath;
  bool _imageLoading = false;

  @override
  void initState() {
    super.initState();
    _decksService = Provider.of<DecksService>(context, listen: false);
    _languageService = Provider.of<LanguageService>(context, listen: false);
    _imageService = Provider.of<ImageService>(context, listen: false);
    _nameController = TextEditingController(text: widget.deck.name);
    _descriptionController =
        TextEditingController(text: widget.deck.description);
    _coverImagePath = widget.deck.coverImagePath;
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
        languageService: _languageService,
        alreadyAdded: _species.map((s) => s.id).toSet(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _species.add(result));
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _imageLoading = true);
    try {
      final savedPath =
          await _imageService.saveCoverImageFromGallery(file.path);
      if (mounted) setState(() => _coverImagePath = savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.errorSaveImage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  Future<void> _searchImages() async {
    final String? localPath = await showImageSearchSheet(
      context,
      initialQuery: _nameController.text.trim(),
    );
    if (localPath != null && mounted) {
      setState(() => _coverImagePath = localPath);
    }
  }

  void _clearCoverImage() => setState(() => _coverImagePath = null);

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
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(context.loc.createDeckNameLabel,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDeckNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(context.loc.createDescriptionLabel,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDescriptionHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text(context.loc.createCoverImageLabel,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              CoverImagePicker(
                imagePath: _coverImagePath,
                isLoading: _imageLoading,
                onGallery: _pickFromGallery,
                onSearch: _searchImages,
                onClear: _clearCoverImage,
              ),
              const SizedBox(height: 24),
              Text(
                context.loc.editSpeciesInDeck(_species.length),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: _species.length,
            itemBuilder: (context, index) {
              final s = _species[index];
              return _SpeciesRow(
                key: ValueKey(s.id),
                species: s,
                languageService: _languageService,
                onDelete: () => _removeSpecies(s),
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
// Individual species row
// ─────────────────────────────────────────────────────────────────────────────

class _SpeciesRow extends StatelessWidget {
  final Species species;
  final LanguageService languageService;
  final VoidCallback onDelete;

  const _SpeciesRow({
    super.key,
    required this.species,
    required this.languageService,
    required this.onDelete,
  });

  String _commonName(BuildContext context) {
    final lang = languageService.getLanguage();
    return species.commonNames[lang] ??
        species.commonNames[Language.en] ??
        species.getBinomialName();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = species.images.isNotEmpty ? species.images.first : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                      memCacheWidth: 104,
                      memCacheHeight: 104,
                      maxWidthDiskCache: 104,
                      maxHeightDiskCache: 104,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => _placeholder(colorScheme),
                      errorWidget: (_, __, ___) => _placeholder(colorScheme),
                    )
                  : _placeholder(colorScheme),
            ),
            title: Text(
              _commonName(context),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              species.getBinomialName(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              color: colorScheme.onSurfaceVariant,
              onPressed: onDelete,
              tooltip: context.loc.editRemoveTooltip,
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    const size = 52.0;
    return Container(
      width: size,
      height: size,
      color: cs.secondaryContainer,
      child: Icon(Icons.image_not_supported_outlined,
          size: size * 0.45, color: cs.onSecondaryContainer),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-species bottom sheet with inline search
// ─────────────────────────────────────────────────────────────────────────────

class _AddSpeciesSheet extends StatefulWidget {
  final LanguageService languageService;
  final Set<String> alreadyAdded;

  const _AddSpeciesSheet({
    required this.languageService,
    required this.alreadyAdded,
  });

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
      _results =
          results.where((r) => r.type == SearchEntityType.species).toList();
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
    final lang = widget.languageService.getLanguage();
    final name = r.commonNames[lang] ?? r.commonNames[Language.en];
    return (name != null && name.isNotEmpty) ? name : r.name;
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
                  Text(context.loc.editAddSpeciesButton,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
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

  Widget _buildResultsList(ScrollController scrollController,
      ColorScheme colorScheme, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(context.loc.editTypeToSearch,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(context.loc.editNoSpeciesFound,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant)),
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
          title: Text(name,
              style: alreadyIn
                  ? TextStyle(color: colorScheme.onSurfaceVariant)
                  : null),
          subtitle: Text(r.name,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic)),
          trailing: alreadyIn
              ? Icon(Icons.check, color: colorScheme.primary)
              : const Icon(Icons.add),
          onTap: alreadyIn ? null : () => _selectResult(r),
        );
      },
    );
  }
}
