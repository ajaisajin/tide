import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_state.dart';
import 'timing_state.dart';

/// How long the confirmation and its Undo button stay.
const Duration undoWindow = Duration(seconds: 10);

/// How long a notice without Undo stays.
const Duration noticeWindow = Duration(seconds: 3);

/// What the toast on the home screen says.
class Confirmation {
  const Confirmation({
    required this.message,
    this.detail,
    this.entryId,
    this.serial = 0,
  });

  /// "Logged ₹250 to Food" or "Added ₹5,000 from Freelance".
  final String message;

  /// The time-to-log, "2.4 s", for an expense.
  final String? detail;

  /// The entry Undo would remove; null when there is nothing to undo.
  final String? entryId;

  /// Goes up with every confirmation, so two alike are still told apart.
  final int serial;

  bool get canUndo => entryId != null;

  /// The whole line as shown: "Logged ₹250 to Food · 2.4 s".
  String get text => detail == null ? message : '$message · $detail';
}

/// The confirmation on show, if any. Only the latest entry can be undone: a
/// new confirmation replaces the one before it.
class ConfirmationNotifier extends Notifier<Confirmation?> {
  Timer? _timer;
  int _serial = 0;

  @override
  Confirmation? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Shows the confirmation for the entry just recorded, with Undo for
  /// [undoWindow].
  void entryRecorded({
    required String entryId,
    required String message,
    String? detail,
  }) {
    _show(
      Confirmation(
        message: message,
        detail: detail,
        entryId: entryId,
        serial: ++_serial,
      ),
      undoWindow,
    );
  }

  /// Removes the entry the confirmation is for, and its timing record.
  void undo() {
    final id = state?.entryId;
    if (id == null) return;
    ref.read(budgetProvider.notifier).removeEntry(id);
    ref.read(timingsProvider.notifier).removeForEntry(id);
    _show(
      Confirmation(message: 'Entry removed', serial: ++_serial),
      noticeWindow,
    );
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }

  void _show(Confirmation confirmation, Duration window) {
    _timer?.cancel();
    state = confirmation;
    _timer = Timer(window, () => state = null);
  }
}

final confirmationProvider =
    NotifierProvider<ConfirmationNotifier, Confirmation?>(
      ConfirmationNotifier.new,
    );
