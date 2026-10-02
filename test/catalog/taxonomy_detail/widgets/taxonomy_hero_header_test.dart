import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_hero_header.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TaxonomyDetailViewModel _viewData({String entityLabel = 'Family'}) =>
    TaxonomyDetailViewModel(
      pageTitle: entityLabel,
      entityLabel: entityLabel,
      primaryTitle: 'Mackerel sharks',
      scientificName: 'Lamnidae',
      commonNames: const ['Mackerel sharks'],
      isEnglishFallback: false,
      metrics: const [],
      classificationRows: const [],
      attributes: const [],
      isReferenceBacked: true,
      emptyCommonNamesLabel: '',
      emptyClassificationLabel: '',
      onlineOnlyHint: '',
      attributesTitle: '',
    );

Widget _buildApp(TaxonomyDetailViewModel viewData, {Widget? languageSelector}) {
  return MaterialApp(
    home: Scaffold(
      body: TaxonomyHeroHeader(
        viewData: viewData,
        type: SearchEntityType.family,
        accent: Colors.blue,
        languageSelector: languageSelector,
      ),
    ),
  );
}

/// The header's content starts this far in from its edge: its padding plus
/// the one-pixel border.
const _inset = AppSpacing.s20 + 1;

void main() {
  testWidgets('leads the badge row with the language selector, in the '
      'header\'s top-left corner above the name', (tester) async {
    await tester.pumpWidget(
      _buildApp(_viewData(), languageSelector: const Text('selector')),
    );

    final header = tester.getRect(find.byType(TaxonomyHeroHeader));
    final selector = tester.getRect(find.text('selector'));
    final badge = tester.getRect(find.byType(SearchEntityTypeBadge));

    expect(selector.left, header.left + _inset);
    expect(badge.left, selector.right + AppSpacing.s8);
    expect(badge.center.dy, moreOrLessEquals(selector.center.dy));
    expect(
      tester.getRect(find.text('Mackerel sharks')).top,
      greaterThan(selector.bottom),
    );
  });

  testWidgets('starts the row with the badge when there is no selector', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(_viewData()));

    expect(
      tester.getRect(find.byType(SearchEntityTypeBadge)).left,
      tester.getRect(find.byType(TaxonomyHeroHeader)).left + _inset,
    );
  });

  testWidgets('keeps selector and badge inside the header on a narrow '
      'screen, even with a long rank label', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildApp(
        _viewData(entityLabel: 'A rank label far too long for one line'),
        languageSelector: const SizedBox(width: 48, height: 28),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(SearchEntityTypeBadge)).right,
      lessThanOrEqualTo(
        tester.getRect(find.byType(TaxonomyHeroHeader)).right - _inset,
      ),
    );
  });
}
