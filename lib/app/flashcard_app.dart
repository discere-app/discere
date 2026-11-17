import 'package:discere/app/bootstrap/reference_db_apply_notice.dart';
import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageService>(
      builder: (context, languageService, child) {
        return MaterialApp(
          locale: languageService.getLanguage().toLocale(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: oceanTheme,
          builder: (context, navigator) =>
              ReferenceDbApplyNotice(child: navigator!),
          home: const MainScreenPage(),
        );
      },
    );
  }
}
