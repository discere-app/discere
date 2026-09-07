import 'package:discere/learning/share/share_qr_capacity.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The scannable form of the deck. Three outcomes, in order of how much the
/// user can do about them: a normal code, a code that renders but is too
/// dense to scan reliably, and a payload that fits no QR version at all.
class ShareQrSection extends StatelessWidget {
  final String qrData;

  const ShareQrSection({required this.qrData, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final moduleCount = qrModuleCount(qrData);

    return SectionCard(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: AppSpacing.screenPaddingAll,
        child: Column(
          children: [
            Text(
              context.loc.shareQrCodeTitle.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.onSurface,
              ),
            ),
            AppSpacing.heightS16,
            if (moduleCount == null)
              _TooLargeNotice(colorScheme: colorScheme, theme: theme)
            else ...[
              _QrCanvas(qrData: qrData),
              AppSpacing.heightS16,
              if (isDenseQr(moduleCount))
                _DenseWarning(colorScheme: colorScheme, theme: theme)
              else
                Text(
                  context.loc.shareQrCodeDescription,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrCanvas extends StatelessWidget {
  final String qrData;

  const _QrCanvas({required this.qrData});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the available card width (up to a sane cap on wide screens)
        // rather than a fixed size — a bigger physical QR renders with bigger
        // modules, which is what actually makes it reliably scannable by a
        // real camera.
        final size = constraints.maxWidth.clamp(0.0, 320.0);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            // Shadow for contrast; corners stay sharp so the quiet zone
            // around the code is not clipped.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TooLargeNotice extends StatelessWidget {
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _TooLargeNotice({required this.colorScheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('share_qr_too_large_warning'),
      padding: AppSpacing.paddingS12Vertical,
      child: Column(
        children: [
          Icon(
            Icons.qr_code_2,
            size: AppSpacing.emptyStateIconSize,
            color: colorScheme.onSurfaceVariant,
          ),
          AppSpacing.heightS16,
          Text(
            context.loc.shareQrTooLarge,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DenseWarning extends StatelessWidget {
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _DenseWarning({required this.colorScheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('share_qr_dense_warning'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.error),
        AppSpacing.widthS8,
        Flexible(
          child: Text(
            context.loc.shareQrDenseWarning,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
