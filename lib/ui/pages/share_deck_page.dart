import 'dart:convert';
import 'dart:io';

import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/learning/base_deck.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/ocean_theme/ocean_colors.dart';

enum DownloadStatus { idle, loading, success, error }

class ShareDeckPage extends StatefulWidget {
  final BaseDeck deck;

  const ShareDeckPage({
    required this.deck,
    super.key,
  });

  @override
  State<ShareDeckPage> createState() => _ShareDeckPageState();
}

class _ShareDeckPageState extends State<ShareDeckPage> {
  DownloadStatus _downloadStatus = DownloadStatus.idle;

  Future<void> _downloadQrCode(String qrData, String deckName) async {
    setState(() {
      _downloadStatus = DownloadStatus.loading;
    });

    try {
      final qrValidationResult = QrValidator.validate(
        data: qrData,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );

      if (qrValidationResult.status != QrValidationStatus.valid) {
        throw Exception('QR validation failed');
      }

      final painter = QrPainter.withQr(
        qr: qrValidationResult.qrCode!,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
        ),
        gapless: true,
      );

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/qr_code_${deckName.replaceAll(' ', '_')}.png';
      
      final picData = await painter.toImageData(1024);
      if (picData == null) throw Exception('Failed to generate image data');
      
      final file = File(path);
      await file.writeAsBytes(picData.buffer.asUint8List());

      await Gal.putImage(path);
      
      setState(() {
        _downloadStatus = DownloadStatus.success;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(context.loc.shareDownloadSuccess),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: OceanColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Reset to idle after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _downloadStatus = DownloadStatus.idle;
          });
        }
      });
    } catch (e) {
      setState(() {
        _downloadStatus = DownloadStatus.error;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.shareDownloadError(e.toString())),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }

      // Reset to idle after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _downloadStatus = DownloadStatus.idle;
          });
        }
      });
    }
  }

  Future<void> _shareDeck(BuildContext context) async {
    final decksService = Provider.of<DecksService>(context, listen: false);
    
    final speciesList = await decksService.getSpeciesByDeckId(widget.deck.id!);
    
    // Export raw binomial names only, one per line, for easier importing
    final shareText = speciesList.map((Species s) => s.getBinomialName()).join('\n');

    if (!context.mounted) return;
    
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    await Share.share(
      shareText,
      subject: widget.deck.name,
      sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.loc.shareDeckTitle),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(Icons.waves, color: colorScheme.primary), // Placeholder for logo
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<CreateDeck>(
          future: context.read<DecksService>().getCreateDeck(widget.deck.id!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Error: ${snapshot.error}', 
                    style: TextStyle(color: colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            
            final fullDeck = snapshot.data!;
            final qrData = jsonEncode(fullDeck.toJson());

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // QR Code Section
                  _buildQrSection(context, qrData),
                  const SizedBox(height: 24),

                  // Animated Download Item
                  _buildAnimatedDownloadItem(context, qrData),
                  
                  const SizedBox(height: 12),
                  
                  // Native Share Item
                  _buildOptionItem(
                    context,
                    icon: Icons.share,
                    title: context.loc.shareDeckTitle, // Sharing purely scientific names now
                    subtitle: context.loc.shareSystemShareDescription, 
                    onTap: () => _shareDeck(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildFooter(context),
    );
  }

  Widget _buildAnimatedDownloadItem(BuildContext context, String qrData) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: _downloadStatus == DownloadStatus.idle 
          ? () => _downloadQrCode(qrData, widget.deck.name) 
          : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _downloadStatus == DownloadStatus.success 
              ? OceanColors.success.withOpacity(0.1) 
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _downloadStatus == DownloadStatus.success 
                ? OceanColors.success.withOpacity(0.5) 
                : colorScheme.outlineVariant.withOpacity(0.2),
            width: _downloadStatus == DownloadStatus.success ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: _buildStatusIcon(context),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.shareExportCovers, 
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, 
                      color: _downloadStatus == DownloadStatus.success 
                          ? OceanColors.success 
                          : colorScheme.onSurface
                    )
                  ),
                  Text(
                    _downloadStatus == DownloadStatus.success 
                        ? context.loc.shareDownloadSuccess 
                        : context.loc.shareExportCoversDescription, 
                    style: theme.textTheme.bodySmall
                  ),
                ],
              ),
            ),
            if (_downloadStatus == DownloadStatus.idle)
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    switch (_downloadStatus) {
      case DownloadStatus.loading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        );
      case DownloadStatus.success:
        return const Icon(Icons.check_circle, color: OceanColors.success, key: ValueKey('success'));
      case DownloadStatus.error:
        return Icon(Icons.error, color: colorScheme.error, key: const ValueKey('error'));
      case DownloadStatus.idle:
      default:
        return Container(
          key: const ValueKey('idle'),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.download, color: colorScheme.primary),
        );
    }
  }

  Widget _buildQrSection(BuildContext context, String qrData) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            context.loc.shareQrCodeTitle.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200.0,
              gapless: false,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.loc.shareQrCodeDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.1),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            context.loc.shareSecureLink,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
