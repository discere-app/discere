String formatDisplayNumber(num value) {
  final rounded = value.roundToDouble();
  return rounded == value ? value.toInt().toString() : value.toStringAsFixed(1);
}
