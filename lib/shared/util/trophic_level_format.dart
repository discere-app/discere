import 'display_number_format.dart';

String? formatTrophicLevel(double? trophicLevel) {
  if (trophicLevel == null) return null;
  return formatDisplayNumber(trophicLevel);
}
