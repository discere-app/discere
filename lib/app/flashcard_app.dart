import 'package:discere/app/bootstrap/popup_route_observer.dart';
import 'package:discere/app/bootstrap/reference_db_apply_notice.dart';
import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

class FlashcardApp extends StatefulWidget {
  const FlashcardApp({super.key});

  @override
  State<FlashcardApp> createState() => _FlashcardAppState();
}

class _FlashcardAppState extends State<FlashcardApp> {
  // One for the life of the navigator: a fresh one per rebuild would miss the
  // routes already on it.
  final _popupRoutes = PopupRouteObserver();

  @override
  void dispose() {
    _popupRoutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageService>(
      builder: (context, languageService, child) {
        return MaterialApp(
          locale: languageService.getLanguage().toLocale(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: oceanTheme,
          navigatorObservers: [_popupRoutes],
          builder: (context, navigator) => ReferenceDbApplyNotice(
            popupRoutes: _popupRoutes,
            child: navigator!,
          ),
          home: const MainScreenPage(),
        );
      },
    );
  }
}
