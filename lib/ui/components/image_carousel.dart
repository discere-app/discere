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
        // aspectRatio: constraints.maxWidth / constraints.maxHeight,
        aspectRatio: 16 / 9,

        viewportFraction: 0.8,
        enlargeCenterPage: true,
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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                image: DecorationImage(
                  fit: BoxFit.contain,
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
