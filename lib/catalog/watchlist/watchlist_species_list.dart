import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The watchlist's swipe-to-remove species list.
class WatchlistSpeciesList extends StatelessWidget {
  static const SpeciesListItemPresenter _presenter = SpeciesListItemPresenter();

  final List<SpeciesWithLocalImages> items;
  final Language language;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRemove;

  const WatchlistSpeciesList({
    super.key,
    required this.items,
    required this.language,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.elementSpacing),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final speciesId = item.species.id;

        return Dismissible(
          key: Key(speciesId),
          direction: DismissDirection.endToStart,
          background: _removeBackground(theme),
          onDismissed: (_) => onRemove(speciesId),
          child: SpeciesListItem(
            item: _presenter.presentSpeciesWithLocalImages(item, language),
            onTap: () => onOpen(speciesId),
            onDelete: () => onRemove(speciesId),
          ),
        );
      },
    );
  }

  Widget _removeBackground(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.s20),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.elementSpacing,
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}
