import 'dart:async';
import 'package:flutter/foundation.dart';

/// Global 3-second auto-refresh ticker shared by every role (Client, Lawyer,
/// Student).
///
/// This is deliberately ONE timer for the whole app, not one per screen/
/// provider — each provider or screen that needs to stay live registers a
/// small callback here (its own existing, already-silent load method) instead
/// of starting its own `Timer.periodic`. That satisfies the "no duplicate
/// timers" / "no memory leaks" requirement structurally: there is only ever
/// one `Timer` object in the whole app, and a screen that forgets to
/// unregister just leaves a no-op callback in a map, never a live timer
/// outliving its widget.
///
/// Started when the user is authenticated and the app is in the foreground
/// (see the lifecycle+auth wiring in main.dart); stopped on logout or when
/// the app is backgrounded, and resumed on the next foreground.
class AutoRefreshService {
  AutoRefreshService._();
  static final AutoRefreshService instance = AutoRefreshService._();

  static const interval = Duration(seconds: 3);

  Timer? _timer;
  final Map<String, Future<void> Function()> _tasks = {};
  final Set<String> _inFlight = {};

  bool get isRunning => _timer != null;

  /// Registers a refresh callback under [key]. Registering the same key again
  /// replaces the previous callback rather than adding a second one, so a
  /// screen that re-registers on every rebuild (instead of once in initState)
  /// still can't end up with duplicate scheduled work.
  void register(String key, Future<void> Function() task) {
    _tasks[key] = task;
  }

  void unregister(String key) {
    _tasks.remove(key);
    _inFlight.remove(key);
  }

  void start() {
    if (_timer != null) return; // already running — never a second Timer
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _inFlight.clear();
  }

  Future<void> _tick() async {
    for (final key in _tasks.keys.toList()) {
      // A task still running from a previous tick (slow network) is skipped
      // rather than piled on top of — this is what prevents duplicate
      // in-flight requests for the same data.
      if (_inFlight.contains(key)) continue;
      final task = _tasks[key];
      if (task == null) continue;
      _inFlight.add(key);
      // One failed cycle must never crash the app, pop an error dialog, or
      // stop the other registered tasks — swallow and let the next tick
      // (in 3s) retry on its own; the screen keeps showing its last-known-good
      // data in the meantime.
      unawaited(task().catchError((Object e) {
        debugPrint('AutoRefreshService[$key] error: $e');
      }).whenComplete(() => _inFlight.remove(key)));
    }
  }
}
