import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';

class LocalPicture {
  final Picture picture;
  final String localPath;

  LocalPicture(this.picture, this.localPath);
}

class SpeciesWithLocalImages {
  final Species species;
  final List<LocalPicture> localPictures;
  SpeciesWithLocalImages(this.species, this.localPictures);
}
