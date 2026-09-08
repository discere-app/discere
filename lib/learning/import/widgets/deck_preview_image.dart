import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class DeckPreviewImage extends StatelessWidget {
  final String? imageUrl;

  const DeckPreviewImage({
    super.key,required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    const size = 52.0;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.image_not_supported),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[300]),
        errorWidget: (context, url, error) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }
}
