import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onNewDay] when the phone's local date changes: at midnight, and
/// when the app comes back to the foreground on a later day (a timer may
/// not fire while the phone sleeps). Home and the Prayer List use the same
/// watcher, so "today" changes on both at the same moment.
class DayChangeWatcher with WidgetsBindingObserver {
  DayChangeWatcher(this.onNewDay, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _day = _dayOf(_clock());
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No Flutter binding (plain unit tests): the timer alone.
    }
    _schedule();
  }

  final void Function() onNewDay;
  final DateTime Function() _clock;
  late DateTime _day;
  Timer? _timer;
  bool _observing = false;

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  void _schedule() {
    _timer?.cancel();
    final now = _clock();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    // A second late, so "today" is surely the new day.
    _timer = Timer(midnight.difference(now) + const Duration(seconds: 1), () {
      check();
      _schedule();
    });
  }

  /// Calls [onNewDay] if the date changed since the last call.
  void check() {
    final today = _dayOf(_clock());
    if (today == _day) return;
    _day = today;
    onNewDay();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      check();
      _schedule();
    }
  }

  void dispose() {
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}
