import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_spacing.dart';

class ImportOnlineDeckListTile extends StatelessWidget {
  final CreateDeck deck;
  final bool isSelected;
  final bool isExpanded;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onToggleExpanded;

  const ImportOnlineDeckListTile({
    required this.deck,
    required this.isSelected,
    required this.isExpanded,
    required this.onSelected,
    required this.onToggleExpanded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: ValueKey('deck-checkbox-${deck.name}'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      visualDensity: const VisualDensity(vertical: -2),
      value: isSelected,
      onChanged: onSelected,
      title: Text(
        deck.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (deck.description.isNotEmpty)
            _ExpandableDescription(
              text: deck.description,
              isExpanded: isExpanded,
              onToggle: onToggleExpanded,
            ),
          Text(
            context.loc.importOnlineSpeciesCount(
              deck.speciesNames?.length ?? 0,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      secondary: deck.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: deck.imageUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[300]),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.broken_image),
              ),
            )
          : const Icon(Icons.image_not_supported),
    );
  }
}

class _ExpandableDescription extends StatelessWidget {
  final String text;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ExpandableDescription({
    required this.text,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: isExpanded ? null : 2,
            overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                isExpanded
                    ? context.loc.importOnlineDescriptionCollapse
                    : context.loc.importOnlineDescriptionExpand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
