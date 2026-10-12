import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every warning that reaches the persisted diagnostics log, as
/// `[scope] message`, until the test ends.
List<String> recordPersistedWarnings() {
  final warnings = <String>[];
  Logger.configurePersistence(
    enabled: true,
    sink: (level, scope, message) async {
      if (level == LogLevel.warning) warnings.add('[$scope] $message');
    },
  );
  addTearDown(() => Logger.configurePersistence(enabled: false));
  return warnings;
}
