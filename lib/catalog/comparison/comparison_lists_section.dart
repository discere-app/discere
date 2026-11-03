import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The user's comparison lists, newest first; tapping one opens it.
///
/// The resolvers and the species detail page are only handed on to the
/// comparison that opens.
class ComparisonListsSection extends StatelessWidget {
  final ResolveSpeciesWithImages resolveFromCache;
  final ResolveSpeciesWithImages resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const ComparisonListsSection({
    super.key,
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ComparisonListService>(
      builder: (context, service, _) {
        final lists = service.lists;
        if (lists == null) {
          final loadError = service.loadError;
          return loadError == null
              ? const Center(child: CircularProgressIndicator())
              : _message(
                  context.loc.errorWithDetail(
                    context.loc.describeError(loadError),
                  ),
                );
        }
        if (lists.isEmpty) return _message(context.loc.comparisonListsEmpty);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.elementSpacing,
          ),
          itemCount: lists.length,
          itemBuilder: (context, index) => _item(context, lists[index]),
        );
      },
    );
  }

  Widget _item(BuildContext context, ComparisonList list) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.elementSpacing,
      ),
      child: TappableSectionCard(
        key: ValueKey('comparison_lists_item_${list.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, list),
        child: ListTile(
          leading: const Icon(Icons.compare),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            context.loc.comparisonSpeciesCount(list.speciesIds.length),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  void _open(BuildContext context, ComparisonList list) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComparisonPage(
          list: list,
          resolveFromCache: resolveFromCache,
          resolveWithDownload: resolveWithDownload,
          buildSpeciesDetailPage: buildSpeciesDetailPage,
        ),
      ),
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
