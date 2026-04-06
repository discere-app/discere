import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../external/inaturalist/inaturalist_service.dart';

/// Small asynchronous thumbnail for species search results.
///
/// The widget fetches a single remote iNaturalist thumbnail on demand and keeps
/// a shared in-memory future cache so list rebuilds do not repeatedly trigger
/// the same network request.
class SearchResultThumbnail extends StatefulWidget {
  final String scientificName;
  final INaturalistService iNatService;
  final double size;
  final Color accentColor;
  final Color backgroundColor;
  final BorderRadius borderRadius;

  const SearchResultThumbnail({
    super.key,
    required this.scientificName,
    required this.iNatService,
    required this.size,
    required this.accentColor,
    required this.backgroundColor,
    required this.borderRadius,
  });

  @override
  State<SearchResultThumbnail> createState() => _SearchResultThumbnailState();
}

class _SearchResultThumbnailState extends State<SearchResultThumbnail> {
  static final Map<String, Future<String?>> _thumbnailCache = {};
  static const bool _enableThumbnailDebugLogging = true;

  late Future<String?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _resolveThumbnailFuture();
  }

  @override
  void didUpdateWidget(covariant SearchResultThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scientificName != widget.scientificName) {
      _thumbnailFuture = _resolveThumbnailFuture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<String?>(
          future: _thumbnailFuture,
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return _ThumbnailPlaceholder(
                backgroundColor: widget.backgroundColor,
                accentColor: widget.accentColor,
              );
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: widget.backgroundColor),
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                  errorBuilder: (context, error, stackTrace) {
                    return _ThumbnailPlaceholder(
                      backgroundColor: widget.backgroundColor,
                      accentColor: widget.accentColor,
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _ThumbnailPlaceholder(
                      backgroundColor: widget.backgroundColor,
                      accentColor: widget.accentColor,
                      showLoader: true,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<String?> _resolveThumbnailFuture() {
    final normalizedName = widget.scientificName.trim().toLowerCase();
    return _thumbnailCache.putIfAbsent(normalizedName, () async {
      _logDebug(
        'Search thumbnail: fetching remote image for "${widget.scientificName}"',
      );
      final url = await widget.iNatService.fetchThumbnailUrl(
        widget.scientificName,
      );
      _logDebug(
        url == null || url.isEmpty
            ? 'Search thumbnail: no image for "${widget.scientificName}"'
            : 'Search thumbnail: resolved image for "${widget.scientificName}"',
      );
      return url;
    });
  }

  void _logDebug(String message) {
    if (_enableThumbnailDebugLogging && kDebugMode) {
      debugPrint(message);
    }
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final bool showLoader;

  const _ThumbnailPlaceholder({
    required this.backgroundColor,
    required this.accentColor,
    this.showLoader = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(10),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.image_search_rounded,
              size: 22,
              color: accentColor.withValues(alpha: 0.85),
            ),
          ),
          if (showLoader)
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
