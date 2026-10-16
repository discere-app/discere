import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_common_name_api.dart';
import 'package:discere/external/inaturalist/inat_metadata_api.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/external/wikipedia/wikipedia_api.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// The `external` clients, as the slices' wiring takes them.
typedef ExternalClients = ({
  INatTaxonDetails iNatTaxonDetails,
  INatTaxonIdResolver iNatTaxonIds,
  INatSearchApi iNatSearch,
  INatMetadataApi iNatMetadata,
  INatPhotoApi iNatPhotos,
  INatCommonNameApi iNatNames,
  WikipediaApi wikipediaApi,
  List<SingleChildWidget> providers,
});

/// Builds the `external` clients over [client], the shared logging client.
///
/// One [INatTaxonDetails] and one [INatTaxonIdResolver] for all of them:
/// both memoise, and enrichment resolves the same taxon for many species.
ExternalClients buildExternalClients(http.Client client) {
  final iNatApi = INatApiClient(client: client);
  final iNatTaxonDetails = INatTaxonDetails(api: iNatApi);
  final iNatTaxonIds = INatTaxonIdResolver(api: iNatApi);
  final iNatPhotos = INatPhotoApi(
    api: iNatApi,
    taxonIds: iNatTaxonIds,
    taxonDetails: iNatTaxonDetails,
  );
  final wikipediaApi = WikipediaApi(client: client);
  return (
    iNatTaxonDetails: iNatTaxonDetails,
    iNatTaxonIds: iNatTaxonIds,
    iNatSearch: INatSearchApi(api: iNatApi),
    iNatMetadata: INatMetadataApi(taxonDetails: iNatTaxonDetails),
    iNatPhotos: iNatPhotos,
    iNatNames: INatCommonNameApi(api: iNatApi, taxonIds: iNatTaxonIds),
    wikipediaApi: wikipediaApi,
    providers: [
      Provider<INatPhotoApi>.value(value: iNatPhotos),
      Provider<WikipediaApi>.value(value: wikipediaApi),
    ],
  );
}
