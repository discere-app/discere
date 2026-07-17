// Single entry point for all integration tests.
// Run with: flutter test integration_test/all_tests.dart -d <device>
//
// This builds the APK once and runs all suites in a single process,
// instead of rebuilding for each test file.

import 'chunking_limit_test.dart' as chunking_limit;
import 'create_deck_test.dart' as create_deck;
import 'deck_lifecycle_test.dart' as deck_lifecycle;
import 'edit_deck_test.dart' as edit_deck;
import 'export_import_test.dart' as export_import;
import 'favorites_test.dart' as favorites;
import 'import_deck_test.dart' as import_deck;
import 'manual_card_activation_test.dart' as manual_card_activation;
import 'notification_test.dart' as notification;
import 'review_flow_test.dart' as review_flow;
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
  create_deck.main();
  import_deck.main();
  deck_lifecycle.main();
  edit_deck.main();
  favorites.main();
  watchlist.main();
  review_flow.main();
  manual_card_activation.main();
  species_search.main();
  export_import.main();
  search_species_delegate.main();
}
