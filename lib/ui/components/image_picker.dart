import 'dart:io';
import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as pk;
import 'image_search_sheet.dart';

class ImagePicker extends StatefulWidget {
  final String? currentImagePath;
  final Future<void> Function(String? path) onImageSelected;
  final String Function() getSearchQuery;

  const ImagePicker({
    super.key,
    required this.currentImagePath,
    required this.onImageSelected,
    required this.getSearchQuery,
  });

  @override
  State<ImagePicker> createState() => _ImagePickerState();
}

class _ImagePickerState extends State<ImagePicker> {
  bool _isLoading = false;

  Future<void> _pickFromGallery() async {
    final picker = pk.ImagePicker();
    final pk.XFile? file =
        await picker.pickImage(source: pk.ImageSource.gallery, imageQuality: 85);
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

  Future<void> _searchImages() async {
    final String? localPath = await showImageSearchSheet(
      context,
      initialQuery: widget.getSearchQuery(),
    );
    if (localPath != null && mounted) {
      setState(() => _isLoading = true);
      try {
        await widget.onImageSelected(localPath);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
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
                        Icon(Icons.image_outlined,
                            size: 40, color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(
                          context.loc.coverImageNoImage, // Could be generic localization later, keeping coverImageNoImage for now to avoid breaking Strings
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
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
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _clearImage(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child:
                              Icon(Icons.close, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Action buttons ─────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.loc.coverImageFromGallery), // Could use generic loc later
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _searchImages,
                icon: const Icon(Icons.image_search_outlined),
                label: Text(context.loc.coverImageSearch), // Could use generic loc later
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
