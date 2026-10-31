import 'package:discere/app/wiring/reference_db_wiring.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/installed_package.dart';

void main() {
  group('buildReferenceDbServices', () {
    test("fetches the manifest with the installed app's User-Agent", () async {
      final sent = <http.BaseRequest>[];
      final referenceDb = buildReferenceDbServices(
        packageInfo: installedPackage,
        foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
        httpClient: MockClient((request) async {
          sent.add(request);
          return http.Response('unavailable', 503);
        }),
      );

      // The manifest fetch fails on the 503; only the request matters here.
      // The download of a release goes through the same client.
      await expectLater(
        referenceDb.provisioner.findNewerVersion(),
        throwsA(isA<ServerException>()),
      );

      expect(sent.single.url.toString(), AppConstants.referenceDbManifestUrl);
      expect(
        sent.single.headers['User-Agent'],
        AppConstants.userAgentFor(installedPackage.version),
      );
    });
  });
}
