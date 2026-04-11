String? formatDepthRangeM(double? depthMinM, double? depthMaxM) {
  if (depthMinM == null && depthMaxM == null) return null;

  String formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  if (depthMinM != null && depthMaxM != null) {
    final minValue = formatNumber(depthMinM);
    final maxValue = formatNumber(depthMaxM);
    if (minValue == maxValue) {
      return '$minValue m';
    }
    return '$minValue-$maxValue m';
  }

  if (depthMinM != null) {
    return '>= ${formatNumber(depthMinM)} m';
  }

  return '<= ${formatNumber(depthMaxM!)} m';
}
