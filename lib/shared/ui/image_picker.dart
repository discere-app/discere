import 'dart:io';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as pk;

class ImagePicker extends StatefulWidget {
  final String? currentImagePath;
  final Future<void> Function(String? path) onImageSelected;

  const ImagePicker({
    super.key,
    required this.currentImagePath,
    required this.onImageSelected,
  });

  @override
  State<ImagePicker> createState() => _ImagePickerState();
}

class _ImagePickerState extends State<ImagePicker> {
  bool _isLoading = false;

  Future<void> _pickFromGallery() async {
    final picker = pk.ImagePicker();
    final pk.XFile? file = await picker.pickImage(
      source: pk.ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await widget.onImageSelected(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.errorSaveImage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearImage() async {
    await widget.onImageSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Preview area (16:9) ─────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image or placeholder
                if (widget.currentImagePath != null)
                  Image.file(File(widget.currentImagePath!), fit: BoxFit.cover)
                else
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        style: BorderStyle.solid,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 40,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        AppSpacing.heightS8,
                        Text(
                          context
                              .loc
                              .coverImageNoImage, // Could be generic localization later, keeping coverImageNoImage for now to avoid breaking Strings
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(color: Colors.white),
                  ),

                // Clear button (top-right) when image is set
                if (widget.currentImagePath != null && !_isLoading)
                  Positioned(
                    top: AppSpacing.s8,
                    right: AppSpacing.s8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _clearImage(),
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.s4),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        AppSpacing.heightS12,

        // ── Action button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(context.loc.coverImageFromGallery),
            style: OutlinedButton.styleFrom(
              padding: AppSpacing.paddingS12Vertical,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
