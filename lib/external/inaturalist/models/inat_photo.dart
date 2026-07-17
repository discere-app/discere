/// A photo from iNaturalist's taxon_photos endpoint.
class INatPhoto {
  final String url;
  final String? attribution;
  final String? licenseCode;

  const INatPhoto({required this.url, this.attribution, this.licenseCode});

  /// Returns the medium-resolution URL (max ~500px wide).
  /// iNat photo URLs contain a size segment like /square.jpeg that can be swapped.
  String get mediumUrl => _swapSize('medium');

  /// Returns the original (full resolution) URL.
  String get originalUrl => _swapSize('original');

  String _swapSize(String size) {
    // iNat URLs look like: .../photos/12345/square.jpeg
    // We replace the size segment (square|thumb|small|medium|large|original).
    return url.replaceFirst(
      RegExp(r'/(square|thumb|small|medium|large|original)\.'),
      '/$size.',
    );
  }
}
