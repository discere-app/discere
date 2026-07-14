import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppBottomNavigationBar extends StatelessWidget {
  final Key? favKey;
  final Key? watchlistKey;

  const AppBottomNavigationBar({super.key, this.favKey, this.watchlistKey});

  void _onTap(BuildContext context, int index, NavigationTabService service) {
    service.selectTab(index);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Consumer<NavigationTabService>(
      builder: (context, service, _) {
        final selectedIndex = service.selectedIndex;
        return BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) => _onTap(context, index, service),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined, key: ValueKey('nav-home')),
              activeIcon: const Icon(Icons.home, key: ValueKey('nav-home')),
              label: loc.navigationHome,
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(
                key: favKey,
                child: const Icon(
                  Icons.favorite_border,
                  key: ValueKey('nav-favourites'),
                ),
              ),
              activeIcon: KeyedSubtree(
                key: favKey,
                child: const Icon(
                  Icons.favorite,
                  key: ValueKey('nav-favourites'),
                ),
              ),
              label: loc.navigationFavourites,
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(
                key: watchlistKey,
                child: const Icon(
                  Icons.format_list_bulleted_outlined,
                  key: ValueKey('nav-watchlist'),
                ),
              ),
              activeIcon: KeyedSubtree(
                key: watchlistKey,
                child: const Icon(
                  Icons.format_list_bulleted,
                  key: ValueKey('nav-watchlist'),
                ),
              ),
              label: loc.navigationWatchlist,
            ),
          ],
        );
      },
    );
  }
}
