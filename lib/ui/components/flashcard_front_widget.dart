
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.images.isEmpty) {
          return Center(
            child: Text(context.loc.commonNoPictureAvailable),
          );
        } else {
          return Column(
            children: [
              Expanded(
                child: ImageCarousel(
                    key: const Key('image'),
                    images: widget.images,
                    constraints: constraints),
              ),
            ],
          );
        }
      },
    );
  }
}
