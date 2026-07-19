class CarouselImage {
  final String? localPath;
  final String? remoteUrl;
  final String attributionText;

  const CarouselImage({
    this.localPath,
    this.remoteUrl,
    required this.attributionText,
  }) : assert(
         localPath != null || remoteUrl != null,
         'CarouselImage requires either a localPath or a remoteUrl',
       );
}
