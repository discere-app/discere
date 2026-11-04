import 'dart:async';

import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/common/species_with_images_loader.dart';
import 'package:discere/catalog/comparison/comparison_image_height.dart';
import 'package:discere/catalog/comparison/comparison_name_dialog.dart';
import 'package:discere/catalog/comparison/comparison_species_presenter.dart';
import 'package:discere/catalog/comparison/comparison_species_section.dart';
import 'package:discere/catalog/comparison/delete_comparison_dialog.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/l10n/app_localizations.dart';
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
    const listPadding = AppSpacing.elementSpacing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight = comparisonImageHeight(
          viewportHeight: constraints.maxHeight - 2 * listPadding,
          rowsPerScreen: columns == 2 ? 1 : 2,
        );
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: listPadding),
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
                          imageHeight,
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _speciesCell(
    BuildContext context,
    SpeciesWithLocalImages entry,
    Language language,
    double imageHeight,
  ) {
    final speciesId = entry.species.id;
    final species = _presenter.present(entry.species, language, context.loc);
    return ComparisonSpeciesSection(
      key: ValueKey(speciesId),
      species: species,
      speciesWithLocalImages: entry,
      imageHeight: imageHeight,
      onOpen: () => _openSpeciesDetail(speciesId),
      onRemove: () => _onRemove(speciesId, species.primaryName),
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }

  /// Takes the species off the screen at once, and offers to put it back
  /// where it was.
  Future<void> _onRemove(String speciesId, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final loc = context.loc;
    _loader.removeOptimistically(speciesId);
    final removed = await _report(
      messenger,
      loc,
      () => _service.removeSpecies(_list.id, speciesId),
    );
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(loc.comparisonSpeciesRemoved(name)),
          action: SnackBarAction(
            key: const Key('comparison_species_undo'),
            label: loc.comparisonUndo,
            // Still works once the page has gone: it reports through what
            // was taken above, not through this page's context.
            onPressed: () =>
                _report(messenger, loc, () => _service.restoreSpecies(removed)),
          ),
        ),
      );
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

  Future<T?> _write<T>(Future<T> Function() change) =>
      _report(ScaffoldMessenger.of(context), context.loc, change);

  /// Runs [change] against the stored lists, answering its result, or null
  /// after telling the user through [messenger] that it failed.
  ///
  /// A failed removal leaves the species off the screen until the next reload
  /// brings it back; the message says why it came back.
  static Future<T?> _report<T>(
    ScaffoldMessengerState messenger,
    AppLocalizations loc,
    Future<T> Function() change,
  ) async {
    try {
      return await change();
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
      return null;
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
