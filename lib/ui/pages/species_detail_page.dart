import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import '../../service/common/biology_service.dart';
import '../../service/common/language_service.dart';
import '../components/species_detail_widget.dart';

class SpeciesDetailPage extends StatefulWidget {
  final String speciesId;
  final Language? language;

  const SpeciesDetailPage({super.key, required this.speciesId, this.language});

  @override
  SpeciesDetailPageState createState() => SpeciesDetailPageState();
}

class SpeciesDetailPageState extends State<SpeciesDetailPage> {
  late Future<SpeciesWithLocalImages?> _futureSpecies;

  @override
  void initState() {
    super.initState();
    final biologyService = Provider.of<BiologyService>(context, listen: false);
    _futureSpecies =
        biologyService.getSpeciesWithLocalImagesById(widget.speciesId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                child: Text('${context.loc.error}: ${snapshot.error}'));
          } else if (snapshot.hasData) {
            return Consumer<LanguageService>(
              builder: (context, languageService, child) {
                final currentLanguage =
                    widget.language ?? languageService.getLanguage();
                return SpeciesDetailWidget(
                  species: snapshot.data!,
                  language: currentLanguage,
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
