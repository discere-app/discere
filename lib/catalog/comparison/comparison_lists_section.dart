import 'package:discere/catalog/comparison/comparison_page_opener.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The user's comparison lists, newest first; tapping one opens it through
/// [ComparisonPageOpener].
class ComparisonListsSection extends StatelessWidget {
  const ComparisonListsSection({super.key});

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
        onTap: () => context.read<ComparisonPageOpener>().open(
          Navigator.of(context),
          list,
        ),
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

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
