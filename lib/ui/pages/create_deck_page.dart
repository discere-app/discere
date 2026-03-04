import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../service/common/image_service.dart';
import '../../service/learning/decks_service.dart';
import '../components/image_search_sheet.dart';

class CreateDeckPage extends StatefulWidget {
  const CreateDeckPage({super.key});

  @override
  State<CreateDeckPage> createState() => _CreateDeckPageState();
}

class _CreateDeckPageState extends State<CreateDeckPage> {
  late final DecksService _decksService;
  late final ImageService _imageService;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _speciesController = TextEditingController();

  String? _coverImagePath; // always a local file path once set
  bool _isCreating = false;
  bool _imageLoading = false;

  @override
  void initState() {
    super.initState();
    _decksService = Provider.of<DecksService>(context, listen: false);
    _imageService = Provider.of<ImageService>(context, listen: false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _speciesController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _imageLoading = true);
    try {
      final savedPath = await _imageService.saveCoverImageFromGallery(file.path);
      if (mounted) setState(() => _coverImagePath = savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _imageLoading = false);
    }
  }

  Future<void> _searchImages() async {
    // Pre-populate search with the deck name the user has typed so far.
    final String? localPath = await showImageSearchSheet(
      context,
      initialQuery: _nameController.text.trim(),
    );
    if (localPath != null && mounted) {
      setState(() => _coverImagePath = localPath);
    }
  }

  void _clearCoverImage() => setState(() => _coverImagePath = null);

  // ── Create deck ───────────────────────────────────────────────────────────

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a deck name.')),
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

    try {
      await _decksService.createDeckBySpeciesScientificNames(
        name,
        description,
        speciesLines,
        coverImagePath: _coverImagePath,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create deck: $e')),
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
        title: const Text('Create New Deck'),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Deck Name ─────────────────────────────────────────
                _SectionLabel(label: 'Deck Name'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Deck Name',
                    hintText: 'e.g. Coral Reef Invertebrates',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────────
                _SectionLabel(label: 'Description'),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText:
                        "What's the goal of this deck? (e.g. Identification training for the Indo-Pacific)",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Species List ──────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'Species List',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
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
                        'SCIENTIFIC NAMES',
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
                  controller: _speciesController,
                  minLines: 5,
                  maxLines: 10,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'Species List',
                    hintText:
                        'Chelonia mydas\nCarcharodon carcharias\nTursiops truncatus',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter one binomial name per line for automatic image fetching.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Cover Image ───────────────────────────────────────
                _SectionLabel(label: 'Cover Image'),
                const SizedBox(height: 10),
                _CoverImagePicker(
                  imagePath: _coverImagePath,
                  isLoading: _imageLoading,
                  onGallery: _pickFromGallery,
                  onSearch: _searchImages,
                  onClear: _clearCoverImage,
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
            onPressed: _isCreating ? null : _create,
            icon: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_circle_outline),
            label: const Text('Create Deck'),
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
// Cover image picker widget
// ─────────────────────────────────────────────────────────────────────────────

class _CoverImagePicker extends StatelessWidget {
  final String? imagePath;
  final bool isLoading;
  final VoidCallback onGallery;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  const _CoverImagePicker({
    required this.imagePath,
    required this.isLoading,
    required this.onGallery,
    required this.onSearch,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Preview area (16:9) ─────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image or placeholder
                if (imagePath != null)
                  Image.file(File(imagePath!), fit: BoxFit.cover)
                else
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        style: BorderStyle.solid,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined,
                            size: 40, color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(
                          'No cover image selected',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),

                // Loading overlay
                if (isLoading)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(color: Colors.white),
                  ),

                // Clear button (top-right) when image is set
                if (imagePath != null && !isLoading)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onClear,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Action buttons ─────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('From Gallery'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onSearch,
                icon: const Icon(Icons.image_search_outlined),
                label: const Text('Search Images'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
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
