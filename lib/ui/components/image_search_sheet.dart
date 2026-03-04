import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../service/common/image_service.dart';

/// A bottom sheet that lets the user search Wikimedia Commons for images.
/// Returns the local file path of the downloaded image, or null if cancelled.
Future<String?> showImageSearchSheet(BuildContext context,
    {String initialQuery = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImageSearchSheet(initialQuery: initialQuery),
  );
}

class _ImageSearchSheet extends StatefulWidget {
  final String initialQuery;
  const _ImageSearchSheet({required this.initialQuery});

  @override
  State<_ImageSearchSheet> createState() => _ImageSearchSheetState();
}

class _ImageSearchSheetState extends State<_ImageSearchSheet> {
  late final ImageService _imageService;
  final _searchController = TextEditingController();
  List<WikiImage> _results = [];
  bool _searching = false;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _imageService = Provider.of<ImageService>(context, listen: false);
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      // Auto-search if query provided
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });

    try {
      final images = await _imageService.searchWikiImages(query);
      if (mounted) {
        setState(() {
          _results = images;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = 'Search failed: $e';
        });
      }
    }
  }

  Future<void> _pick(WikiImage image) async {
    setState(() => _downloading = true);
    try {
      final localPath = await _imageService.downloadWikiThumbnail(image.title, image.fullUrl);
      if (mounted) Navigator.of(context).pop(localPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download image: $e')),
        );
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Stack(
          children: [
            Column(
              children: [
                // Header
                _buildHeader(context, colorScheme),

                // Search Bar
                _buildSearchBar(colorScheme),

                // Results
                Expanded(
                  child: _buildResultsGrid(scrollController, colorScheme, theme),
                ),
              ],
            ),
            if (_downloading)
              Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Search Wikimedia',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search for marine life…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _search(_searchController.text),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSubmitted: _search,
      ),
    );
  }

  Widget _buildResultsGrid(ScrollController scrollController,
      ColorScheme colorScheme, ThemeData theme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
          child:
              Text(_error!, style: TextStyle(color: colorScheme.error)));
    }

    if (_results.isEmpty) {
      return Center(
        child: Text('Search for something to see results.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant)),
      );
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final img = _results[index];
        return GestureDetector(
          onTap: () => _pick(img),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              img.thumbUrl,
              fit: BoxFit.cover,
              headers: const {
                'User-Agent': 'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)'
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: colorScheme.secondaryContainer,
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: colorScheme.secondaryContainer,
                child: const Icon(Icons.error_outline),
              ),
            ),
          ),
        );
      },
    );
  }
}
