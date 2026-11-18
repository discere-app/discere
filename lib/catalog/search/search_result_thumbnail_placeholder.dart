import 'package:material_ui/material_ui.dart';

/// What a `SearchResultThumbnail` shows while it has no picture: the
/// row's accent color on its background. Also the whole leading picture of
/// a row with nothing to look a picture up for.
class SearchResultThumbnailPlaceholder extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final bool showLoader;

  const SearchResultThumbnailPlaceholder({
    super.key,
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
