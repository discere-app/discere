import 'dart:async';

import 'package:discere/catalog/common/remove_swipe_background.dart';
import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/common/species_with_images_loader.dart';
import 'package:discere/catalog/comparison/comparison_name_dialog.dart';
import 'package:discere/catalog/comparison/comparison_species_presenter.dart';
import 'package:discere/catalog/comparison/comparison_species_section.dart';
import 'package:discere/catalog/comparison/delete_comparison_dialog.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _ComparisonAction { rename, delete }

/// One comparison list: its species one below the other — side by side in
/// two columns in landscape — each with its pictures and a few facts. Loaded
/// through [SpeciesWithImagesLoader].
class ComparisonPage extends StatefulWidget {
  /// The list as it was when opened; the page follows its changes from
  /// [ComparisonListService].
  final ComparisonList list;
  final ResolveSpeciesWithImages resolveFromCache;
  final ResolveSpeciesWithImages resolveWithDownload;
  final Widget Function(String speciesId) buildSpeciesDetailPage;

  const ComparisonPage({
    super.key,
    required this.list,
    required this.resolveFromCache,
    required this.resolveWithDownload,
    required this.buildSpeciesDetailPage,
  });

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  static final _log = Logger.forType(ComparisonPage);
  static const _presenter = ComparisonSpeciesPresenter();

  late final ComparisonListService _service;

  /// The list on screen. Kept when the service no longer has it — after
  /// deleting, the page shows it until its route has gone.
  late ComparisonList _list = widget.list;

  late final SpeciesWithImagesLoader _loader = SpeciesWithImagesLoader(
    resolveFromCache: widget.resolveFromCache,
    resolveWithDownload: widget.resolveWithDownload,
    onChanged: () => setState(() {}),
    log: _log,
  );
  List<String> _currentSpeciesIds = const [];

  @override
  void initState() {
    super.initState();
    _service = Provider.of<ComparisonListService>(context, listen: false);
    _currentSpeciesIds = _list.speciesIds;
    unawaited(_loader.load(_currentSpeciesIds.toSet()));
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ComparisonListService>(
      builder: (context, service, _) {
        final language = context.watch<LanguageService>().getLanguage();
        _list = service.listById(_list.id) ?? _list;
        if (!listEquals(_list.speciesIds, _currentSpeciesIds)) {
          _currentSpeciesIds = _list.speciesIds;
          unawaited(_loader.load(_currentSpeciesIds.toSet()));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_list.name),
            actions: [
              PopupMenuButton<_ComparisonAction>(
                key: const Key('comparison_page_menu'),
                onSelected: _onAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const Key('comparison_page_rename'),
                    value: _ComparisonAction.rename,
                    child: Text(context.loc.comparisonRename),
                  ),
                  PopupMenuItem(
                    key: const Key('comparison_page_delete'),
                    value: _ComparisonAction.delete,
                    child: Text(context.loc.comparisonDelete),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(child: _body(context, language)),
        );
      },
    );
  }

  Widget _body(BuildContext context, Language language) {
    final species = _loader.species;
    if (species == null) {
      final loadError = _loader.loadError;
      return loadError != null
          ? _message(
              context.loc.errorWithDetail(context.loc.describeError(loadError)),
            )
          : const Center(child: CircularProgressIndicator());
    }
    if (species.isEmpty) return _message(context.loc.comparisonEmpty);

    final columns = MediaQuery.orientationOf(context) == Orientation.landscape
        ? 2
        : 1;
    final rowCount = (species.length / columns).ceil();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.elementSpacing),
      itemCount: rowCount,
      itemBuilder: (context, row) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns; column++)
            Expanded(
              child: row * columns + column < species.length
                  ? _speciesCell(
                      context,
                      species[row * columns + column],
                      language,
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _speciesCell(
    BuildContext context,
    SpeciesWithLocalImages entry,
    Language language,
  ) {
    final speciesId = entry.species.id;
    return Dismissible(
      key: ValueKey(speciesId),
      direction: DismissDirection.endToStart,
      background: const RemoveSwipeBackground(),
      onDismissed: (_) => _onRemove(speciesId),
      child: ComparisonSpeciesSection(
        species: _presenter.present(entry.species, language, context.loc),
        speciesWithLocalImages: entry,
        onOpen: () => _openSpeciesDetail(speciesId),
      ),
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }

  void _onRemove(String speciesId) {
    _loader.removeOptimistically(speciesId);
    unawaited(_write(() => _service.removeSpecies(_list.id, speciesId)));
  }

  Future<void> _onAction(_ComparisonAction action) async {
    switch (action) {
      case _ComparisonAction.rename:
        final name = await showComparisonNameDialog(
          context,
          title: context.loc.comparisonRenameTitle,
          initialName: _list.name,
        );
        if (name != null && mounted) {
          await _write(() => _service.renameList(_list.id, name));
        }
      case _ComparisonAction.delete:
        final confirmed = await showDeleteComparisonDialog(context, _list.name);
        if (!confirmed || !mounted) return;
        // Taken before the route goes, so a failure can still be reported.
        final write = _write(() => _service.deleteList(_list.id));
        Navigator.of(context).pop();
        await write;
    }
  }

  /// Runs [change] against the stored lists and tells the user if it failed.
  ///
  /// A failed removal leaves the species off the screen until the next reload
  /// brings it back; the message says why it came back.
  Future<void> _write(Future<void> Function() change) async {
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    try {
      await change();
    } catch (error, stackTrace) {
      _log.warn(
        'Comparison change failed',
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(loc.comparisonSaveFailed(loc.describeError(error))),
        ),
      );
    }
  }

  void _openSpeciesDetail(String speciesId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => widget.buildSpeciesDetailPage(speciesId),
      ),
    );
  }
}
