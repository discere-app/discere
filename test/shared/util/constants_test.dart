import 'package:discere/shared/util/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConstants.userAgentFor', () {
    test('names the app, the version, the bundle ID and the repository', () {
      expect(
        AppConstants.userAgentFor('1.4.0'),
        'DiscereApp/1.4.0 (ch.feberle.discere; https://github.com/discere-app/discere)',
      );
    });
  });
}
