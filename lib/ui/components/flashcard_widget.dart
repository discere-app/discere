import 'package:flutter/material.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../service/common/language_service.dart';
import 'flashcard_back_widget.dart';
import 'flashcard_front_widget.dart';

class FlashCardWidget extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImage;
  final LanguageService languageService;

  const FlashCardWidget({
    required this.speciesWithLocalImage,
    required this.languageService,
    super.key,
  });

  @override
  FlashCardWidgetState createState() => FlashCardWidgetState();
}

class FlashCardWidgetState extends State<FlashCardWidget> {
  bool _showData = false;

  void _flip() {
    setState(() {
      _showData = !_showData;
    });
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: _flip,
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: _showData ? 180 : 0),
        duration: const Duration(milliseconds: 500),
        builder: (BuildContext context, double val, _) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(val * (3.14 / 180)),
            child: Container(
              margin: const EdgeInsets.all(20),
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                border: Border.all(color: theme.primaryColor),
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _showData
                  ? FlashCardBack(
                      speciesWithLocalImages: widget.speciesWithLocalImage,
                    )
                  : FlashCardFront(
                      images: widget.speciesWithLocalImage.localImages,
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant FlashCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speciesWithLocalImage != oldWidget.speciesWithLocalImage) {
      setState(() {
        _showData = false;
      });
    }
  }
}
