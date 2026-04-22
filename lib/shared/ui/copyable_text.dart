import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? copiedStyle;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const CopyableText({
    super.key,
    required this.text,
    this.style,
    this.copiedStyle,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  State<CopyableText> createState() => _CopyableTextState();
}

class _CopyableTextState extends State<CopyableText> {
  static const Duration _feedbackDuration = Duration(milliseconds: 1600);

  Timer? _feedbackTimer;
  bool _copied = false;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final value = widget.text.trim();
    if (value.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: value));
    _feedbackTimer?.cancel();

    if (!mounted) return;
    setState(() => _copied = true);

    _feedbackTimer = Timer(_feedbackDuration, () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final copiedStyle =
        widget.copiedStyle ??
        baseStyle.copyWith(color: theme.colorScheme.primary);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _copyToClipboard,
      child: Padding(
        padding: widget.padding,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _copied ? 1.02 : 1,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: _copied ? copiedStyle : baseStyle,
            child: Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              textAlign: widget.textAlign,
            ),
          ),
        ),
      ),
    );
  }
}
