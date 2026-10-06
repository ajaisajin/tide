import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clock.dart';

/// The current local date, as midnight at the start of that day.
///
/// The clock is read again when the app returns to the foreground and when a
/// timer set for the next local midnight fires, so whatever watches this
/// hears about a new day, and through it a new month, without a restart.
class TodayNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    final now = ref.watch(clockProvider)();
    final observer = _ResumeObserver(refresh);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() {
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    _schedule(now);
    return _dateOf(now);
  }

  /// Reads the clock again and moves to its date if the day has changed.
  void refresh() {
    final now = ref.read(clockProvider)();
    _schedule(now);
    final today = _dateOf(now);
    if (today != state) state = today;
  }

  void _schedule(DateTime now) {
    _timer?.cancel();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    var wait = midnight.difference(now);
    // A timer that fires a moment early finds the same date and comes back
    // here; the floor keeps that from spinning.
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, refresh);
  }

  static DateTime _dateOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final void Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Today's local date. Watch it for anything that depends on the day.
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(
  TodayNotifier.new,
);
