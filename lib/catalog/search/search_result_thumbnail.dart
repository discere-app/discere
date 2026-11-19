import 'dart:async';
import 'dart:collection';

import 'package:discere/catalog/search/search_result_thumbnail_placeholder.dart';
import 'package:discere/shared/extensions/image_request_headers_extension.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:material_ui/material_ui.dart';

/// Small asynchronous thumbnail for a row of a species or taxon list.
///
/// The widget fetches a single remote iNaturalist thumbnail on demand and keeps
/// a shared in-memory future cache so list rebuilds do not repeatedly trigger
/// the same network request. Both go by [thumbnailKey], not the displayed
/// name: two species can show the same name (homonyms, a species shown by
/// its epithet alone) and must not share a picture.
class SearchResultThumbnail extends StatefulWidget {
  /// What [resolveThumbnailUrl] looks the picture up by: a species' id, or
  /// a higher taxon's name key (`genus:massaria`). A name key starts with
  /// its rank, which no species id does, so both share the one cache.
  final String thumbnailKey;
  final Future<String?> Function(String thumbnailKey) resolveThumbnailUrl;
  final double size;
  final Color accentColor;
  final Color backgroundColor;
  final BorderRadius borderRadius;

  const SearchResultThumbnail({
    super.key,
    required this.thumbnailKey,
    required this.resolveThumbnailUrl,
    required this.size,
    required this.accentColor,
    required this.backgroundColor,
    required this.borderRadius,
  });

  /// Clears the process-wide thumbnail cache and fetch bookkeeping.
  ///
  /// That state is `static`, so it outlives a widget test and is shared by
  /// every test in the same `flutter test` shard: a test that resolves an id
  /// to `null` leaves that answer behind, and a later test resolving the same
  /// id to a real URL silently gets the `null` and renders the placeholder —
  /// failing at the second test, which is not where the cause is.
  @visibleForTesting
  static void resetCacheForTesting() {
    _SearchResultThumbnailState._thumbnailCache.clear();
    _SearchResultThumbnailState._activeThumbnailFetches = 0;
    _SearchResultThumbnailState._thumbnailWaitQueue.clear();
  }

  @override
  State<SearchResultThumbnail> createState() => _SearchResultThumbnailState();
}

class _SearchResultThumbnailState extends State<SearchResultThumbnail> {
  static final _log = Logger.forType(_SearchResultThumbnailState);
  // LRU-ish cache: a search session can touch far more distinct taxa
  // than are ever shown again, so this is capped instead of growing
  // unbounded for the process lifetime.
  static const int _maxCachedThumbnails = 300;
  static final LinkedHashMap<String, Future<String?>> _thumbnailCache =
      LinkedHashMap();
  static const int _maxConcurrentThumbnailFetches = 2;
  static int _activeThumbnailFetches = 0;
  static final Queue<Completer<void>> _thumbnailWaitQueue = Queue();

  late Future<String?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _resolveThumbnailFuture();
  }

  @override
  void didUpdateWidget(covariant SearchResultThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailKey != widget.thumbnailKey) {
      _thumbnailFuture = _resolveThumbnailFuture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final decodeSize = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 192);

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<String?>(
          future: _thumbnailFuture,
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) {
              return SearchResultThumbnailPlaceholder(
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
                  headers: context.imageRequestHeaders,
                  fit: BoxFit.cover,
                  cacheWidth: decodeSize,
                  cacheHeight: decodeSize,
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
                    return SearchResultThumbnailPlaceholder(
                      backgroundColor: widget.backgroundColor,
                      accentColor: widget.accentColor,
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return SearchResultThumbnailPlaceholder(
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
    final thumbnailKey = widget.thumbnailKey;

    final cached = _thumbnailCache.remove(thumbnailKey);
    if (cached != null) {
      // Re-insert so it's ordered as most-recently-used and survives
      // eviction longer.
      _thumbnailCache[thumbnailKey] = cached;
      return cached;
    }

    final future = _fetchThumbnail();
    _thumbnailCache[thumbnailKey] = future;
    while (_thumbnailCache.length > _maxCachedThumbnails) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
    return future;
  }

  Future<String?> _fetchThumbnail() async {
    final waitStopwatch = Stopwatch()..start();
    await _acquireThumbnailSlot();
    waitStopwatch.stop();
    _log.debug(
      'Search thumbnail: fetching remote image for ${widget.thumbnailKey} '
      '(queueWait=${waitStopwatch.elapsedMilliseconds}ms, '
      'active=$_activeThumbnailFetches)',
    );
    try {
      final url = await widget.resolveThumbnailUrl(widget.thumbnailKey);
      _log.debug(
        url == null || url.isEmpty
            ? 'Search thumbnail: no image for ${widget.thumbnailKey}'
            : 'Search thumbnail: resolved image for ${widget.thumbnailKey}',
      );
      return url;
    } finally {
      _releaseThumbnailSlot();
    }
  }

  Future<void> _acquireThumbnailSlot() {
    if (_activeThumbnailFetches < _maxConcurrentThumbnailFetches) {
      _activeThumbnailFetches++;
      return Future.value();
    }

    final completer = Completer<void>();
    _thumbnailWaitQueue.addLast(completer);
    return completer.future;
  }

  void _releaseThumbnailSlot() {
    final next = _thumbnailWaitQueue.isNotEmpty
        ? _thumbnailWaitQueue.removeFirst()
        : null;
    if (next != null) {
      next.complete();
      return;
    }

    if (_activeThumbnailFetches > 0) {
      _activeThumbnailFetches--;
    }
  }
}
