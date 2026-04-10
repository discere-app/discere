import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import '../service/biology_service.dart';
import 'species_detail_widget.dart';

class SpeciesDetailPage extends StatefulWidget {
  final String speciesId;
  final Language? language;

  const SpeciesDetailPage({super.key, required this.speciesId, this.language});

  @override
  SpeciesDetailPageState createState() => SpeciesDetailPageState();
}

class SpeciesDetailPageState extends State<SpeciesDetailPage> {
  late Future<SpeciesWithLocalImages?> _futureSpecies;
  BiologyService? _biologyService;
  bool _isRefreshingImages = false;

  @override
  void initState() {
    super.initState();
    _biologyService = Provider.of<BiologyService>(context, listen: false);
    _futureSpecies = _biologyService!.getSpeciesWithCachedImagesById(
      widget.speciesId,
    );
    _refreshINatImagesIfNeeded();
  }

  Future<void> _refreshINatImagesIfNeeded() async {
    final hasCacheEntry = await _biologyService!.hasCachedINatPhotoEntry(
      widget.speciesId,
    );
    if (!mounted || hasCacheEntry) return;

    setState(() {
      _isRefreshingImages = true;
    });

    final enriched = await _biologyService!
        .getSpeciesWithCachedOrFetchedImagesById(widget.speciesId);
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
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<SpeciesWithLocalImages?>(
          future: _futureSpecies,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Text(snapshot.data!.species.getBinomialName());
            } else {
              return Text(context.loc.speciesDetailTitle);
            }
          },
        ),
      ),
      body: FutureBuilder<SpeciesWithLocalImages?>(
        future: _futureSpecies,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text('${context.loc.error}: ${snapshot.error}'),
            );
          } else if (snapshot.hasData) {
            return Consumer<LanguageService>(
              builder: (context, languageService, child) {
                final currentLanguage =
                    widget.language ?? languageService.getLanguage();
                return SpeciesDetailWidget(
                  species: snapshot.data!,
                  language: currentLanguage,
                  isRefreshingImages: _isRefreshingImages,
                );
              },
            );
          } else {
            return Center(child: Text(context.loc.commonNoData));
          }
        },
      ),
    );
  }
}
