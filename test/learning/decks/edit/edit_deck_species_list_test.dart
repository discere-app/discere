import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_species_list.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';

/// Covers the image each row of the edit-deck species list shows.
///
/// A deck's species carry only their reference pictures. The image a user
/// expects in the list is the one the detail page shows: a file already on
/// disk, which may be an iNaturalist photo the species itself knows nothing
/// about. The list therefore resolves its rows through SpeciesMediaService and
/// keeps doing so as the cache moves under it — a species is added, the detail
/// page fetched photos — without ever letting a failed or outdated resolution
/// cost the user the list itself.

const _iNatUrl = 'https://inat/photo.jpg';

Species _species(String id, {String? referenceUrl}) => Species(
  id,
  id,
  'fishbase',
  id,
  const {},
  Classification(
    'Genus',
    const {},
    null,
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
  ),
  [
    if (referenceUrl != null)
      Picture(
        id: 'ref-$id',
        species: id,
        url: referenceUrl,
        origin: 'fishbase',
        isUsable: 1,
      ),
  ],
);

/// What SpeciesMediaService answers for [species]: its reference pictures plus
/// an iNaturalist photo if [withINatPhoto], and [localPath] as the file the
/// first of them resolved to — null while none of them is on disk.
SpeciesWithLocalImages _resolved(
  Species species, {
  bool withINatPhoto = false,
  String? localPath,
}) {
  final pictures = [
    ...species.pictures,
    if (withINatPhoto)
      Picture(
        id: 'inat-${species.id}',
        species: species.id,
        url: _iNatUrl,
        origin: 'iNaturalist',
        isUsable: 1,
      ),
  ];
  return SpeciesWithLocalImages(
    Species(
      species.id,
      species.externalId,
      species.externalSource,
      species.scientificName,
      species.commonNames,
      species.classification,
      pictures,
    ),
    localPath == null ? const [] : [LocalPicture(pictures.first, localPath)],
  );
}

void main() {
  late MockSpeciesMediaService speciesMediaService;

  /// Runs [change] against the list's species and rebuilds it, the way the
  /// page applies a draft change. Set by [pumpList].
  late void Function(VoidCallback change) changeDraft;

  setUp(() {
    speciesMediaService = MockSpeciesMediaService();
  });

  /// Lets every resolution answer from [localPaths] as it stands at the time
  /// of the call, so a test can put a file "on disk" between two resolutions.
  /// For a species without a reference picture that file is an iNaturalist
  /// photo, the only other picture a species can have.
  void givenFilesOnDisk(Map<String, String> localPaths) {
    when(speciesMediaService.resolveSpeciesFromCache(any)).thenAnswer((
      invocation,
    ) async {
      final species = invocation.positionalArguments.single as List<Species>;
      return [
        for (final entry in species)
          _resolved(
            entry,
            withINatPhoto:
                entry.pictures.isEmpty && localPaths.containsKey(entry.id),
            localPath: localPaths[entry.id],
          ),
      ];
    });
  }

  Future<void> pumpList(
    WidgetTester tester,
    List<Species> species, {
    Future<void> Function(Species species)? onOpen,
    ValueChanged<Species>? onRemove,
  }) async {
    await tester.pumpWidget(
      Provider<SpeciesMediaService>.value(
        value: speciesMediaService,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                changeDraft = setState;
                return CustomScrollView(
                  slivers: [
                    EditDeckSpeciesList(
                      species: species,
                      language: Language.en,
                      onOpen: onOpen ?? (_) async {},
                      onRemove: onRemove ?? (_) {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  SpeciesListItemViewModel row(WidgetTester tester, String speciesId) =>
      tester.widget<SpeciesListItem>(find.byKey(ValueKey(speciesId))).item;

  Finder imageFileOf(String speciesId, String path) => find.descendant(
    of: find.byKey(ValueKey(speciesId)),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is ResizeImage &&
          ((widget.image as ResizeImage).imageProvider as FileImage)
                  .file
                  .path ==
              path,
    ),
  );

  group('EditDeckSpeciesList', () {
    testWidgets('shows the file on disk instead of fetching the reference '
        'picture again', (tester) async {
      givenFilesOnDisk({'sp1': '/local/sp1.jpg'});

      await pumpList(tester, [
        _species('sp1', referenceUrl: 'https://host/sp1.jpg'),
      ]);

      expect(row(tester, 'sp1').localImagePath, '/local/sp1.jpg');
      expect(imageFileOf('sp1', '/local/sp1.jpg'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('shows the cached iNat photo of a species that has no '
        'reference picture', (tester) async {
      final species = _species('sp1');
      when(speciesMediaService.resolveSpeciesFromCache(any)).thenAnswer(
        (_) async => [
          _resolved(species, withINatPhoto: true, localPath: '/inat/sp1.jpg'),
        ],
      );

      await pumpList(tester, [species]);

      expect(imageFileOf('sp1', '/inat/sp1.jpg'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    });

    testWidgets('falls back to the cached iNat photo\'s URL while its file is '
        'not on disk', (tester) async {
      final species = _species('sp1');
      when(
        speciesMediaService.resolveSpeciesFromCache(any),
      ).thenAnswer((_) async => [_resolved(species, withINatPhoto: true)]);

      await pumpList(tester, [species]);

      expect(row(tester, 'sp1').localImagePath, isNull);
      expect(row(tester, 'sp1').remoteImageUrl, _iNatUrl);
    });

    testWidgets('lists the species before their images are resolved', (
      tester,
    ) async {
      final pending = Completer<List<SpeciesWithLocalImages>>();
      when(
        speciesMediaService.resolveSpeciesFromCache(any),
      ).thenAnswer((_) => pending.future);

      await pumpList(tester, [_species('sp1'), _species('sp2')]);

      expect(find.byType(SpeciesListItem), findsNWidgets(2));
      expect(row(tester, 'sp1').scientificName, 'Genus sp1');
      expect(row(tester, 'sp2').scientificName, 'Genus sp2');
    });

    testWidgets('keeps the list when resolving the images fails', (
      tester,
    ) async {
      when(
        speciesMediaService.resolveSpeciesFromCache(any),
      ).thenAnswer((_) async => throw Exception('cache unreadable'));

      await pumpList(tester, [
        _species('sp1', referenceUrl: 'https://host/sp1.jpg'),
        _species('sp2'),
      ]);
      await tester.pump();

      expect(find.byType(SpeciesListItem), findsNWidgets(2));
      expect(row(tester, 'sp1').localImagePath, isNull);
      expect(row(tester, 'sp1').remoteImageUrl, 'https://host/sp1.jpg');
      expect(tester.takeException(), isNull);
    });

    testWidgets('resolves the image of a species added to the list', (
      tester,
    ) async {
      givenFilesOnDisk({'sp1': '/local/sp1.jpg', 'sp2': '/local/sp2.jpg'});
      final species = [_species('sp1')];
      await pumpList(tester, species);

      // In place, as the page's draft is changed: the list is handed the same
      // object again and has to notice the new entry by itself.
      changeDraft(() => species.add(_species('sp2')));
      await tester.pump();
      await tester.pump();

      expect(row(tester, 'sp1').localImagePath, '/local/sp1.jpg');
      expect(row(tester, 'sp2').localImagePath, '/local/sp2.jpg');
    });

    testWidgets('picks up an image the detail page cached', (tester) async {
      final localPaths = <String, String>{};
      givenFilesOnDisk(localPaths);
      final detailPage = Completer<void>();

      await pumpList(
        tester,
        [_species('sp1')],
        onOpen: (_) {
          // The detail page fetches the species' photos while it is open.
          localPaths['sp1'] = '/inat/sp1.jpg';
          return detailPage.future;
        },
      );
      expect(row(tester, 'sp1').localImagePath, isNull);

      await tester.tap(find.byKey(const ValueKey('sp1')));
      await tester.pump();
      // Still on the detail page: the list has no reason to look yet.
      expect(row(tester, 'sp1').localImagePath, isNull);

      detailPage.complete();
      await tester.pump();
      await tester.pump();

      expect(row(tester, 'sp1').localImagePath, '/inat/sp1.jpg');
    });

    testWidgets('ignores a resolution that answers after a newer one', (
      tester,
    ) async {
      final first = Completer<List<SpeciesWithLocalImages>>();
      final sp1 = _species('sp1');
      final sp2 = _species('sp2');
      final species = [sp1];
      when(
        speciesMediaService.resolveSpeciesFromCache(any),
      ).thenAnswer((_) => first.future);
      await pumpList(tester, species);

      givenFilesOnDisk({'sp1': '/local/sp1.jpg', 'sp2': '/local/sp2.jpg'});
      changeDraft(() => species.add(sp2));
      await tester.pump();
      await tester.pump();
      expect(row(tester, 'sp2').localImagePath, '/local/sp2.jpg');

      // The resolution started for [sp1] alone answers last. It knows nothing
      // of sp2 and predates sp1's file.
      first.complete([_resolved(sp1)]);
      await tester.pump();
      await tester.pump();

      expect(row(tester, 'sp1').localImagePath, '/local/sp1.jpg');
      expect(row(tester, 'sp2').localImagePath, '/local/sp2.jpg');
    });

    testWidgets('reports the species whose remove button was tapped', (
      tester,
    ) async {
      givenFilesOnDisk(const {});
      final removed = <String>[];

      await pumpList(tester, [
        _species('sp1'),
        _species('sp2'),
      ], onRemove: (species) => removed.add(species.id));
      await tester.tap(find.byTooltip('Remove').last);

      expect(removed, ['sp2']);
    });
  });
}
