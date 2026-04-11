import 'display_number_format.dart';

String? formatYears(double? years) {
  if (years == null) return null;
  return '${formatDisplayNumber(years)} years';
}
