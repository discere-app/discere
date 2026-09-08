import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class TapToRevealHint extends StatefulWidget {
  const TapToRevealHint({super.key});

  @override
  State<TapToRevealHint> createState() => _TapToRevealHintState();
}

class _TapToRevealHintState extends State<TapToRevealHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ).drive(Tween(begin: 0.35, end: 1.0));

  bool _hasStartedAnimating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStartedAnimating) return;
    _hasStartedAnimating = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _runPulses();
    }
  }

  /// A handful of pulses to catch the eye on first appearance, then settles
  /// on full opacity — deliberately finite (not `repeat()`) so it doesn't
  /// keep `pumpAndSettle()` spinning forever in widget tests.
  Future<void> _runPulses() async {
    for (var i = 0; i < 3 && mounted; i++) {
      await _controller.forward();
      if (i < 2 && mounted) await _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _pulse,
          child: Icon(
            Icons.visibility_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        AppSpacing.widthS8,
        Text(
          context.loc.flashcardTapToReveal,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
