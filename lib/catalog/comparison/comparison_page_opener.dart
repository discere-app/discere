import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:flutter/material.dart';

/// The one way to a [ComparisonPage]: holds what the page needs besides its
/// list, so that a screen opening a comparison — the overview, the
/// confirmation after adding to one — needs only this.
///
/// Built by the composition root, which owns the species pictures and the
/// species detail page, and provided above the navigator, so every route can
/// read it.
class ComparisonPageOpener {
  final ResolveSpeciesWithImages resolveFromCache;
  final ResolveSpeciesWithImages resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const ComparisonPageOpener({
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  /// Pushes [list] onto [navigator]. Takes the navigator rather than a
  /// context, so a caller can take it before its own route goes.
  Future<void> open(NavigatorState navigator, ComparisonList list) {
    return navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ComparisonPage(
          list: list,
          resolveFromCache: resolveFromCache,
          resolveWithDownload: resolveWithDownload,
          buildSpeciesDetailPage: buildSpeciesDetailPage,
        ),
      ),
    );
  }
}
