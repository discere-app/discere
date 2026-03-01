import 'dart:async';
import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

class ImageCarousel extends StatelessWidget {
  final List<String> images;
  final BoxConstraints constraints;
  const ImageCarousel(
      {super.key, required this.images, required this.constraints});

  @override
  Widget build(BuildContext context) {
    return CarouselSlider.builder(
      itemCount: images.length,
      options: CarouselOptions(
        height: constraints.maxHeight,
        viewportFraction: 1.0,
        enlargeCenterPage: false,
        enableInfiniteScroll: images.length > 1,
      ),
      itemBuilder: (context, index, realIndex) {
        final String imageUrl = images[index];
        ImageProvider imageProvider = FileImage(File(imageUrl));

        return FutureBuilder<ImageInfo>(
          future: _getImageInfo(imageProvider),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return Container(
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                // No border radius needed when strictly covering the whole container area
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: imageProvider,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<ImageInfo> _getImageInfo(ImageProvider provider) async {
    final Completer<ImageInfo> completer = Completer();
    final ImageStream stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((ImageInfo info, bool _) {
      completer.complete(info);
    });
    stream.addListener(listener);
    return completer.future;
  }
}
