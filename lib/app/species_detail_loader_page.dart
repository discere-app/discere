import 'package:discere/application/species_media/species_media_service.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_page.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeciesDetailLoaderPage extends StatefulWidget {
  final String speciesId;
  final Language? language;

  const SpeciesDetailLoaderPage({
    super.key,
    required this.speciesId,
    this.language,
  });

  @override
  State<SpeciesDetailLoaderPage> createState() =>
      _SpeciesDetailLoaderPageState();
}

class _SpeciesDetailLoaderPageState extends State<SpeciesDetailLoaderPage> {
  late final SpeciesMediaService _speciesMediaService;
  late Future<SpeciesWithLocalImages?> _futureSpecies;
  bool _isRefreshingImages = false;

  @override
  void initState() {
    super.initState();
    _speciesMediaService = Provider.of<SpeciesMediaService>(
      context,
      listen: false,
    );
    _futureSpecies = _speciesMediaService.resolveFromCache(widget.speciesId);
    _refreshINatImagesIfNeeded();
  }

  Future<void> _refreshINatImagesIfNeeded() async {
    final hasCacheEntry = await _speciesMediaService.hasEnrichedPhotos(
      widget.speciesId,
    );
    if (!mounted || hasCacheEntry) return;

    setState(() {
      _isRefreshingImages = true;
    });

    final enriched = await _speciesMediaService.resolveWithFetch(
      widget.speciesId,
    );
    if (!mounted) return;

    setState(() {
      _isRefreshingImages = false;
      if (enriched != null) {
        _futureSpecies = Future.value(enriched);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpeciesWithLocalImages?>(
      future: _futureSpecies,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(context.loc.speciesDetailTitle)),
            body: Center(
              child: Text('${context.loc.error}: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(context.loc.speciesDetailTitle)),
            body: Center(child: Text(context.loc.commonNoData)),
          );
        }

        return SpeciesDetailPage(
          species: snapshot.data!,
          isRefreshingImages: _isRefreshingImages,
          language: widget.language,
        );
      },
    );
  }
}
