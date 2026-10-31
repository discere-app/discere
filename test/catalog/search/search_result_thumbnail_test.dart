import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../support/installed_package.dart';

void main() {
  late List<String> requestedIds;

  setUp(() {
    // The thumbnail cache is static and shared across every test in this
    // shard, so a thumbnail resolved here must not leak into the next test.
    SearchResultThumbnail.resetCacheForTesting();
    requestedIds = [];
  });

  Future<String?> resolveThumbnailUrl(String speciesId) async {
    requestedIds.add(speciesId);
    return 'https://inat.test/$speciesId/medium.jpg';
  }

  Widget thumbnails(List<String> speciesIds) => Provider<PackageInfo>.value(
    value: installedPackage,
    child: MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (final speciesId in speciesIds)
              SearchResultThumbnail(
                speciesId: speciesId,
                resolveThumbnailUrl: resolveThumbnailUrl,
                size: 48,
                accentColor: Colors.teal,
                backgroundColor: Colors.white,
                borderRadius: BorderRadius.zero,
              ),
          ],
        ),
      ),
    ),
  );

  List<NetworkImage> shownImages(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      (image.image as ResizeImage).imageProvider as NetworkImage,
  ];

  List<String> shownUrls(WidgetTester tester) =>
      shownImages(tester).map((image) => image.url).toList();

  testWidgets("loads the thumbnail with the app's User-Agent", (tester) async {
    await tester.pumpWidget(thumbnails(['discere:species:1']));
    await tester.pump();

    expect(shownImages(tester).single.headers, {
      'User-Agent': AppConstants.userAgentFor(installedPackage.version),
    });
  });

  testWidgets('resolves each species by its own id', (tester) async {
    await tester.pumpWidget(
      thumbnails(['discere:species:1', 'discere:species:2']),
    );
    await tester.pump();

    expect(requestedIds, ['discere:species:1', 'discere:species:2']);
    expect(shownUrls(tester), [
      'https://inat.test/discere:species:1/medium.jpg',
      'https://inat.test/discere:species:2/medium.jpg',
    ]);
  });

  testWidgets('resolves the same species once, however often it is listed', (
    tester,
  ) async {
    await tester.pumpWidget(
      thumbnails(['discere:species:1', 'discere:species:1']),
    );
    await tester.pump();

    expect(requestedIds, ['discere:species:1']);
    expect(shownUrls(tester), [
      'https://inat.test/discere:species:1/medium.jpg',
      'https://inat.test/discere:species:1/medium.jpg',
    ]);
  });
}
