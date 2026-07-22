import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Tinted, bordered banner used to draw attention to a single concern (a
/// warning, an error, or a hint) instead of letting it blend into
/// surrounding prose — colored entirely from [color], so the same shape
/// expresses different severities wherever it's used.
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget child;

  const InfoBanner({
    required this.icon,
    required this.color,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingS12All,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: child),
        ],
      ),
    );
  }
}
