import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../support/installed_package.dart';

void main() {
  testWidgets("loads a remote picture with the app's User-Agent", (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<PackageInfo>.value(
        value: installedPackage,
        child: const MaterialApp(
          home: Scaffold(
            body: SpeciesListItem(
              item: SpeciesListItemViewModel(
                primaryName: 'Red lionfish',
                scientificName: 'Pterois miles',
                additionalNames: null,
                localImagePath: null,
                remoteImageUrl: 'https://images.test/pterois.jpg',
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .httpHeaders,
      {'User-Agent': AppConstants.userAgentFor(installedPackage.version)},
    );
  });
}
