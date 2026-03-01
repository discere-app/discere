import 'dart:io';

import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import 'image_carousel.dart';

class FlashCardFront extends StatefulWidget {
  final List<String> images;

  const FlashCardFront({
    required this.images,
    super.key,
  });

  @override
  FlashCardFrontState createState() => FlashCardFrontState();
}

class FlashCardFrontState extends State<FlashCardFront> {
  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        alignment: Alignment.center,
        child: Text(context.loc.commonNoPictureAvailable),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hero Image Background
        Image.file(
          File(widget.images.first),
          fit: BoxFit.cover,
        ),
        // Deep Gradient Overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surface.withOpacity(0.7),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Tap to flip UI hint
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Tap to reveal',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
