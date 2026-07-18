import 'package:discere/shared/util/display_number_format.dart';

String? formatLengthCm(double? lengthCm) {
  if (lengthCm == null) return null;

  if (lengthCm < 1) {
    final lengthMm = lengthCm * 10;
    return '${formatDisplayNumber(lengthMm)} mm';
  }

  return '${formatDisplayNumber(lengthCm)} cm';
}
