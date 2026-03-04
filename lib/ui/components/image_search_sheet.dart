import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A bottom sheet that lets the user search Wikimedia Commons for images.
/// Returns the local file path of the downloaded image, or null if cancelled.
const _wikiHeaders = {
  'User-Agent': 'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)',
  'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  'Accept-Encoding': 'gzip, deflate, br',
};

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
  final _searchController = TextEditingController();
  List<_WikiImage> _results = [];
  bool _searching = false;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _search(widget.initialQuery));
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
      final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrnamespace': '6', // File namespace
        'gsrsearch': query.trim(),
        'gsrlimit': '24',
        'prop': 'imageinfo',
        'iiprop': 'url|thumburl|thumbmime',
        'iiurlwidth': '320',
        'format': 'json',
        'origin': '*',
      });

      final response = await http.get(uri, headers: _wikiHeaders);
      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() => _error = 'Search failed (${response.statusCode})');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages =
          (data['query']?['pages'] as Map<String, dynamic>?)?.values ?? [];

      final images = <_WikiImage>[];
      for (final page in pages) {
        final info = (page['imageinfo'] as List?)?.firstOrNull;
        if (info == null) continue;
        final thumbUrl = info['thumburl'] as String?;
        final fullUrl = info['url'] as String?;
        final title = page['title'] as String?;
        final mime = info['thumbmime'] as String? ?? '';
        if (thumbUrl == null ||
            fullUrl == null ||
            title == null ||
            !mime.startsWith('image/')) {
          continue;
        }
        images.add(_WikiImage(
          thumbUrl: thumbUrl,
          fullUrl: fullUrl,
          title: title,
        ));
      }

      setState(() => _results = images);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search error: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(_WikiImage image) async {
    setState(() => _downloading = true);
    try {
      // 1. Fetch high-res thumbnail (1200px) instead of original to ensure JPG/PNG compatibility
      final infoUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'titles': image.title,
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '1200',
        'format': 'json',
        'origin': '*',
      });

      final infoRes = await http.get(infoUri, headers: _wikiHeaders);
      final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
      final page = (infoData['query']?['pages'] as Map<String, dynamic>?)
          ?.values
          .firstOrNull;
      final info = (page?['imageinfo'] as List?)?.firstOrNull;

      // Use the 1200px thumbnail URL if available, otherwise fallback to fullUrl
      final downloadUrl = info?['thumburl'] as String? ?? image.fullUrl;

      // 2. Download the image
      final response =
          await http.get(Uri.parse(downloadUrl), headers: _wikiHeaders);
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'deck_covers'));
      if (!dir.existsSync()) await dir.create(recursive: true);

      final ext = p.extension(Uri.parse(downloadUrl).path);
      final suffix = ext.isNotEmpty ? ext : '.jpg';
      final dest = File(
          p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$suffix'));
      await dest.writeAsBytes(response.bodyBytes);

      if (mounted) Navigator.of(context).pop(dest.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download image: $e')),
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
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ── Handle ────────────────────────────────────────────────
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Search Images',
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

            // ── Search bar ────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: widget.initialQuery.isEmpty,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'e.g. coral reef, blue whale…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _results = []);
                              },
                            )
                          : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const Divider(height: 1),

            // ── Results ───────────────────────────────────────────────
            Expanded(
              child: _downloading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant)))
                      : _results.isEmpty && !_searching
                          ? Center(
                              child: Text(
                                'Type a search term and press Enter',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : GridView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 16 / 9,
                              ),
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final img = _results[index];
                                return _ResultTile(
                                  image: img,
                                  onTap: () => _pick(img),
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final _WikiImage image;
  final VoidCallback onTap;

  const _ResultTile({required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {

    return Material(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink.image(
          image: NetworkImage(image.thumbUrl, headers: _wikiHeaders),
          fit: BoxFit.cover,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WikiImage {
  final String thumbUrl;
  final String fullUrl;
  final String title;
  const _WikiImage({
    required this.thumbUrl,
    required this.fullUrl,
    required this.title,
  });
}
