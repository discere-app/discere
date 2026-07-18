import 'package:discere/catalog/model/picture.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';

class InaturalistPhotoPictureMapper {
  const InaturalistPhotoPictureMapper();

  List<Picture> map(String speciesId, List<INatPhoto> photos) {
    return photos
        .map(
          (photo) => Picture(
            id: 'inat_${speciesId}_${photo.mediumUrl.hashCode}',
            species: speciesId,
            url: photo.mediumUrl,
            author: photo.attribution,
            origin: 'iNaturalist',
            licenseKey: (photo.licenseCode ?? '').toUpperCase(),
            isUsable: 1,
          ),
        )
        .toList();
  }
}
