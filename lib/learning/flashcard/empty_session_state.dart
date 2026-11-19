import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:material_ui/material_ui.dart';

/// What a session shows instead of a card: a spinner while images for the
/// due cards are still being fetched, and otherwise the plain "nothing to
/// review" message.
class EmptySessionState extends StatelessWidget {
  final bool isWaitingForImages;

  const EmptySessionState({required this.isWaitingForImages, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(
        child: isWaitingForImages
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  AppSpacing.heightS24,
                  Text(
                    context.loc.flashcardImagesDownloading,
                    key: const Key('images_downloading_empty_state_text'),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : Text(
                context.loc.commonNoFlashcardsAvailable,
                key: const Key('no_flashcards_empty_state_text'),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
