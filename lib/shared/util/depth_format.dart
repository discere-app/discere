import 'package:discere/shared/util/display_number_format.dart';

String? formatDepthRangeM(double? depthMinM, double? depthMaxM) {
  if (depthMinM == null && depthMaxM == null) return null;

  if (depthMinM != null && depthMaxM != null) {
    final minValue = formatDisplayNumber(depthMinM);
    final maxValue = formatDisplayNumber(depthMaxM);
    if (minValue == maxValue) {
      return '$minValue m';
    }
    return '$minValue-$maxValue m';
  }

  if (depthMinM != null) {
    return '>= ${formatDisplayNumber(depthMinM)} m';
  }

  return '<= ${formatDisplayNumber(depthMaxM!)} m';
}
