import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single image to display in the [FullscreenImageViewer].
class FullscreenImage {
  final ImageProvider provider;
  final String attributionText;

  const FullscreenImage({
    required this.provider,
    required this.attributionText,
  });
}

/// A full-screen image gallery with pinch-to-zoom, double-tap-to-zoom and
/// horizontal swiping between images.
class FullscreenImageViewer extends StatefulWidget {
  final List<FullscreenImage> images;
  final int initialIndex;

  const FullscreenImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  /// Opens the viewer as a fullscreen overlay route.
  static Future<void> open(
    BuildContext context, {
    required List<FullscreenImage> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FullscreenImageViewer(images: images, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final PageController _pageController;
  final Map<int, TransformationController> _controllers = {};
  late int _currentIndex;
  bool _isZoomed = false;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // Lift the app-wide portrait lock (see main.dart) so users can rotate to
    // landscape while viewing images.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int index) {
    return _controllers.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(() {
        final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
        if (zoomed != _isZoomed) {
          setState(() => _isZoomed = zoomed);
        }
      });
      return controller;
    });
  }

  void _handleDoubleTap(TransformationController controller) {
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
      return;
    }

    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;

    const scale = 2.5;
    final x = -position.dx * (scale - 1);
    final y = -position.dy * (scale - 1);
    controller.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.images.length > 1;
    final attribution = widget.images[_currentIndex].attributionText;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => _buildPage(index),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.s8,
            left: AppSpacing.s8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: context.loc.commonClose,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),

          // Attribution + page counter
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s16,
                AppSpacing.s16,
                MediaQuery.of(context).padding.bottom + AppSpacing.s12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasMultiple)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (attribution.isNotEmpty)
                    Text(
                      attribution,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    final image = widget.images[index];
    final controller = _controllerFor(index);

    return InteractiveViewer(
      transformationController: controller,
      minScale: 1,
      maxScale: 5,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: () => _handleDoubleTap(controller),
        child: SizedBox.expand(
          child: Image(image: image.provider, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
