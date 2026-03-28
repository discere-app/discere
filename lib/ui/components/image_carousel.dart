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
              children: () {
                const maxVisibleDots = 7;
                final totalDots = widget.images.length;
                
                if (totalDots <= maxVisibleDots) {
                  return List.generate(totalDots, (index) => _buildDot(index));
                }

                // Sliding window calculation
                int start = _currentIndex - (maxVisibleDots ~/ 2);
                int end = start + maxVisibleDots - 1;

                if (start < 0) {
                  start = 0;
                  end = maxVisibleDots - 1;
                } else if (end >= totalDots) {
                  end = totalDots - 1;
                  start = end - maxVisibleDots + 1;
                }

                return List.generate(maxVisibleDots, (i) {
                  final index = start + i;
                  return _buildDot(index);
                });
              }(),
            ),
          ),
      ],
    );
  }

  Widget _buildDot(int index) {
    final isActive = index == _currentIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: isActive ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
