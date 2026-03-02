import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

class ImageCarousel extends StatefulWidget {
  final List<String> images;
  final BoxConstraints constraints;

  const ImageCarousel({
    super.key,
    required this.images,
    required this.constraints,
  });

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.images.length > 1;

    return Stack(
      children: [
        // Dark background for letterboxing
        Container(color: Colors.black),

        // Carousel
        CarouselSlider.builder(
          itemCount: widget.images.length,
          options: CarouselOptions(
            height: widget.constraints.maxHeight,
            viewportFraction: 1.0,
            enlargeCenterPage: false,
            enableInfiniteScroll: hasMultiple,
            onPageChanged: (index, _) {
              if (hasMultiple) setState(() => _currentIndex = index);
            },
          ),
          itemBuilder: (context, index, realIndex) {
            return Image.file(
              File(widget.images[index]),
              fit: BoxFit.contain,
              width: widget.constraints.maxWidth,
              height: widget.constraints.maxHeight,
            );
          },
        ),

        // Dot indicators (only if multiple images)
        if (hasMultiple)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (index) {
                final isActive = index == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
