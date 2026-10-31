import 'package:discere/shared/extensions/image_request_headers_extension.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../support/installed_package.dart';

void main() {
  testWidgets('names the provided app version in the User-Agent', (
    tester,
  ) async {
    late Map<String, String> headers;
    await tester.pumpWidget(
      Provider<PackageInfo>.value(
        value: installedPackage,
        child: Builder(
          builder: (context) {
            headers = context.imageRequestHeaders;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(headers, {
      'User-Agent': AppConstants.userAgentFor(installedPackage.version),
    });
  });
}
