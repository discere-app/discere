String? formatLengthCm(double? lengthCm) {
  if (lengthCm == null) return null;

  if (lengthCm < 1) {
    final lengthMm = lengthCm * 10;
    final value = lengthMm == lengthMm.roundToDouble()
        ? lengthMm.toInt().toString()
        : lengthMm.toStringAsFixed(1);
    return '$value mm';
  }

  final value = lengthCm == lengthCm.roundToDouble()
      ? lengthCm.toInt().toString()
      : lengthCm.toStringAsFixed(1);
  return '$value cm';
}
