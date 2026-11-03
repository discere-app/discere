import 'package:discere/catalog/comparison/add_to_comparison_presenter.dart';
import 'package:discere/catalog/comparison/comparison_name_dialog.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens the "add to comparison" sheet for [speciesIds]: pick a comparison
/// list to add them to, or create a new one, whose name is suggested from
/// [speciesNames]. Resolves to `true` once the species are in a list, `false`
/// if the sheet was closed without adding them.
///
/// The one way into a comparison list — every screen that offers "add to
/// comparison" opens this.
Future<bool> showAddToComparisonSheet(
  BuildContext context, {
  required Set<String> speciesIds,
  required Set<String> speciesNames,
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddToComparisonSheet(
      speciesIds: speciesIds,
      speciesNames: speciesNames,
    ),
  );
  return added ?? false;
}

class AddToComparisonSheet extends StatefulWidget {
  final Set<String> speciesIds;
  final Set<String> speciesNames;

  const AddToComparisonSheet({
    required this.speciesIds,
    required this.speciesNames,
    super.key,
  });

  @override
  State<AddToComparisonSheet> createState() => _AddToComparisonSheetState();
}

class _AddToComparisonSheetState extends State<AddToComparisonSheet> {
  static final _log = Logger.forType(AddToComparisonSheet);
  static const _presenter = AddToComparisonPresenter();

  /// The sheet's own messenger: the app's one shows its SnackBars on the page
  /// underneath, covered by this sheet.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _isAdding = false;

  Future<void> _addTo(ComparisonList list) async {
    if (_isAdding) return;
    final added = _presenter.missingFrom(list, widget.speciesIds).length;
    final service = context.read<ComparisonListService>();
    if (await _write(() => service.addSpecies(list.id, widget.speciesIds))) {
      _closeWithConfirmation(added, list.name);
    }
  }

  Future<void> _createNew() async {
    final loc = context.loc;
    final service = context.read<ComparisonListService>();
    final name = await showComparisonNameDialog(
      context,
      title: loc.comparisonCreateNew,
      initialName: _presenter.suggestedName(widget.speciesNames, loc),
    );
    if (name == null || !mounted) return;
    if (await _write(() => service.createList(name, widget.speciesIds))) {
      _closeWithConfirmation(widget.speciesIds.length, name);
    }
  }

  /// Runs [change] with the sheet locked, and whether it succeeded. A failure
  /// is reported in the sheet, which stays open and usable to try again.
  Future<bool> _write(Future<void> Function() change) async {
    setState(() => _isAdding = true);
    try {
      await change();
      return true;
    } catch (error, stackTrace) {
      _log.warn(
        'Adding to a comparison failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return false;
      setState(() => _isAdding = false);
      final loc = context.loc;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(loc.comparisonSaveFailed(loc.describeError(error))),
        ),
      );
      return false;
    }
  }

  void _closeWithConfirmation(int added, String listName) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(content: Text(loc.comparisonAddSuccess(added, listName))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: AbsorbPointer(
              absorbing: _isAdding,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.loc.comparisonAdd,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('comparison_sheet_create_new'),
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.add,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(context.loc.comparisonCreateNew),
                    onTap: _createNew,
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildLists(scrollController, colorScheme)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLists(
    ScrollController scrollController,
    ColorScheme colorScheme,
  ) {
    return Consumer<ComparisonListService>(
      builder: (context, service, _) {
        final lists = service.lists;
        if (lists == null) {
          final loadError = service.loadError;
          return loadError == null
              ? const Center(child: CircularProgressIndicator())
              : _buildMessage(
                  context.loc.errorWithDetail(
                    context.loc.describeError(loadError),
                  ),
                  colorScheme,
                );
        }
        if (lists.isEmpty) {
          return _buildMessage(context.loc.comparisonNoLists, colorScheme);
        }
        return ListView.builder(
          controller: scrollController,
          itemCount: lists.length,
          itemBuilder: (context, index) {
            final list = lists[index];
            final isComplete = _presenter.containsAll(list, widget.speciesIds);
            return ListTile(
              key: ValueKey('comparison_sheet_list_${list.id}'),
              enabled: !isComplete,
              leading: Icon(Icons.compare, color: colorScheme.onSurfaceVariant),
              title: Text(list.name),
              subtitle: Text(
                context.loc.comparisonSpeciesCount(list.speciesIds.length),
              ),
              trailing: Icon(isComplete ? Icons.check : Icons.add),
              onTap: isComplete ? null : () => _addTo(list),
            );
          },
        );
      },
    );
  }

  Widget _buildMessage(String message, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
