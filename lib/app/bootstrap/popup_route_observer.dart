import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tells whether the route on top of the navigator it observes is a
/// [PopupRoute] — a dialog, a bottom sheet, a menu.
///
/// For widgets that sit above the navigator and so above every modal
/// barrier: `ReferenceDbApplyNotice` disables "Apply" while a modal is open,
/// because what a dialog or sheet is doing (applying a deck update, adding
/// species to a deck) may be writing to the user database in several steps.
class PopupRouteObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _routes = [];
  bool _popupOnTop = false;
  bool _disposed = false;

  bool get isPopupOnTop => _popupOnTop;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute != null) {
      index < 0 ? _routes.add(newRoute) : _routes[index] = newRoute;
    } else if (index >= 0) {
      _routes.removeAt(index);
    }
    _update();
  }

  void _update() {
    final popupOnTop = _routes.isNotEmpty && _routes.last is PopupRoute;
    if (popupOnTop == _popupOnTop) return;
    _popupOnTop = popupOnTop;
    // The navigator reports routes while it builds, too (its initial
    // route); a listener above it must not be marked dirty during that.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _notify());
    } else {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
