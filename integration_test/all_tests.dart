// Single entry point for all integration tests.
// Run with: flutter test integration_test/all_tests.dart -d <device>
//
// This builds the APK once and runs all suites in a single process,
// instead of rebuilding for each test file.

import 'about_page_test.dart' as about_page;
import 'chunking_limit_test.dart' as chunking_limit;
import 'create_deck_test.dart' as create_deck;
import 'deck_lifecycle_test.dart' as deck_lifecycle;
import 'edit_deck_test.dart' as edit_deck;
import 'enrichment_pipeline_test.dart' as enrichment_pipeline;
import 'enrichment_shutdown_test.dart' as enrichment_shutdown;
import 'export_import_test.dart' as export_import;
import 'favorites_test.dart' as favorites;
import 'import_deck_test.dart' as import_deck;
import 'learning_modes_test.dart' as learning_modes;
import 'manual_card_activation_test.dart' as manual_card_activation;
import 'no_photo_found_test.dart' as no_photo_found;
import 'notification_test.dart' as notification;
import 'reference_db_background_update_test.dart' as reference_db_background_update;
import 'review_flow_test.dart' as review_flow;
import 'runtime_common_name_fts_test.dart' as runtime_common_name_fts;
import 'search_species_delegate_test.dart' as search_species_delegate;
import 'settings_test.dart' as settings;
import 'smoke_test.dart' as smoke;
import 'sources_page_test.dart' as sources_page;
import 'species_search_test.dart' as species_search;
import 'watchlist_test.dart' as watchlist;

void main() {
  smoke.main();
  chunking_limit.main();
  notification.main();
  settings.main();
  sources_page.main();
  about_page.main();
  create_deck.main();
  import_deck.main();
  deck_lifecycle.main();
  edit_deck.main();
  enrichment_pipeline.main();
  enrichment_shutdown.main();
  favorites.main();
  watchlist.main();
  review_flow.main();
  manual_card_activation.main();
  no_photo_found.main();
  reference_db_background_update.main();
  learning_modes.main();
  species_search.main();
  export_import.main();
  search_species_delegate.main();
  runtime_common_name_fts.main();
}
