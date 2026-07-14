import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'flashcard_front.dart';

class FlashcardWidget extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImage;
  final Language language;
  final LearningMode learningMode;
  final GlobalKey? watchlistKey;

  const FlashcardWidget({
    required this.speciesWithLocalImage,
    required this.language,
    this.learningMode = LearningMode.species,
    this.watchlistKey,
    super.key,
  });

  @override
  FlashcardWidgetState createState() => FlashcardWidgetState();
}

class FlashcardWidgetState extends State<FlashcardWidget> {
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
              margin: AppSpacing.paddingS20All,
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                color: theme.cardTheme.color ?? theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _showData
                    ? FlashcardBackContent(
                        speciesWithLocalImages: widget.speciesWithLocalImage,
                        language: widget.language,
                        learningMode: widget.learningMode,
                      )
                    : FlashcardFront(
                        speciesWithLocalImages: widget.speciesWithLocalImage,
                        watchlistKey: widget.watchlistKey,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant FlashcardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speciesWithLocalImage != oldWidget.speciesWithLocalImage) {
      setState(() {
        _showData = false;
      });
    }
  }
}
