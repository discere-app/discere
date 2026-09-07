import 'dart:async';
import 'dart:io';

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/share/import_export_service.dart';
import 'package:discere/learning/share/widgets/share_download_item.dart';
import 'package:discere/learning/share/widgets/share_option_item.dart';
import 'package:discere/learning/share/widgets/share_qr_section.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShareDeckPage extends StatefulWidget {
  final BaseDeck deck;

  const ShareDeckPage({required this.deck, super.key});

  @override
  State<ShareDeckPage> createState() => _ShareDeckPageState();
}

class _ShareDeckPageState extends State<ShareDeckPage> {
  DownloadStatus _downloadStatus = DownloadStatus.idle;
  late Future<_ShareDeckPayload> _payloadFuture;

  @override
  void initState() {
    super.initState();
    _payloadFuture = _loadPayload();
  }

  Future<_ShareDeckPayload> _loadPayload() async {
    final importExportService = context.read<ImportExportService>();
    final results = await Future.wait([
      importExportService.exportDeckToGzip(widget.deck.id!),
      importExportService.exportDeckToJson(widget.deck.id!),
    ]);
    return _ShareDeckPayload(compressedBase64: results[0], rawJson: results[1]);
  }

  Future<void> _downloadJsonFile(String jsonData, String deckName) async {
    setState(() {
      _downloadStatus = DownloadStatus.loading;
    });

    final importExportService = Provider.of<ImportExportService>(
      context,
      listen: false,
    );

    final success = await importExportService.saveJsonToFile(
      jsonData: jsonData,
      deckName: deckName,
      exportPrefix: context.loc.appExportPrefix,
    );

    if (mounted) {
      if (success) {
        setState(() {
          _downloadStatus = DownloadStatus.success;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                AppSpacing.widthS12,
                Expanded(
                  child: Text(
                    Platform.isAndroid
                        ? context.loc.shareDownloadSuccessAndroid
                        : context.loc.shareDownloadSuccessIos,
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: OceanColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        // Fallback to Share sheet if direct save fails
        try {
          await importExportService.shareDeckAsFile(
            jsonData: jsonData,
            deckName: deckName,
            exportPrefix: context.loc.appExportPrefix,
          );

          if (mounted) {
            setState(() {
              _downloadStatus = DownloadStatus.success;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _downloadStatus = DownloadStatus.error;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.loc.shareDownloadError(context.loc.describeError(e)),
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
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

  Future<void> _shareAsSpeciesList(BuildContext context) async {
    final importExportService = Provider.of<ImportExportService>(
      context,
      listen: false,
    );

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    await importExportService.shareDeckAsSpeciesListText(
      deckId: widget.deck.id!,
      deckName: widget.deck.name,
      sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _shareAsJsonText(BuildContext context) async {
    final importExportService = Provider.of<ImportExportService>(
      context,
      listen: false,
    );

    final box = context.findRenderObject() as RenderBox?;

    await importExportService.shareDeckAsJsonText(
      deckId: widget.deck.id!,
      deckName: widget.deck.name,
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.shareDeckTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<_ShareDeckPayload>(
          future: _payloadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: AppSpacing.screenPaddingAll,
                  child: Text(
                    '${context.loc.error}: ${context.loc.describeError(snapshot.error)}',
                    style: TextStyle(color: colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final payload = snapshot.data!;
            return SingleChildScrollView(
              padding: AppSpacing.screenPaddingAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSpacing.heightS12,
                  ShareQrSection(qrData: payload.compressedBase64),
                  AppSpacing.heightS24,
                  ShareOptionItem(
                    key: const Key('share_species_list_option'),
                    icon: Icons.list,
                    title: context.loc.shareSpeciesList,
                    subtitle: context.loc.shareSystemShareDescription,
                    onTap: () => _shareAsSpeciesList(context),
                  ),
                  ShareDownloadItem(
                    key: const Key('share_download_json_option'),
                    status: _downloadStatus,
                    onTap: () =>
                        _downloadJsonFile(payload.rawJson, widget.deck.name),
                  ),
                  AppSpacing.heightS12,
                  ShareOptionItem(
                    key: const Key('share_json_text_option'),
                    icon: Icons.code,
                    title: context.loc.shareJsonText,
                    subtitle: context.loc.shareSystemShareDescription,
                    onTap: () => _shareAsJsonText(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

}

class _ShareDeckPayload {
  final String compressedBase64;
  final String rawJson;

  const _ShareDeckPayload({
    required this.compressedBase64,
    required this.rawJson,
  });
}
