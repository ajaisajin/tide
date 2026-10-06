import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_state.dart';
import 'timing_state.dart';

/// How long the confirmation and its Undo button stay.
const Duration undoWindow = Duration(seconds: 10);

/// How long a notice without Undo stays.
const Duration noticeWindow = Duration(seconds: 3);

/// What the toast says when Undo could not delete the entry.
const String undoFailedMessage = 'Could not undo. The entry is still saved.';

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
  bool _undoing = false;

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

  /// Says [message] for [noticeWindow], with nothing to undo.
  void notice(String message) {
    _show(Confirmation(message: message, serial: ++_serial), noticeWindow);
  }

  /// Deletes the entry the confirmation is for from the ledger, then drops
  /// its timing record and says so. If the delete fails the entry stays, and
  /// the toast says that instead, with Undo still offered.
  Future<void> undo() async {
    final current = state;
    final id = current?.entryId;
    if (current == null || id == null || _undoing) return;
    _undoing = true;
    try {
      await ref.read(budgetProvider.notifier).removeEntry(id);
    } catch (_) {
      if (!ref.mounted) return;
      _show(
        Confirmation(
          message: undoFailedMessage,
          entryId: id,
          serial: ++_serial,
        ),
        undoWindow,
      );
      return;
    } finally {
      _undoing = false;
    }
    if (!ref.mounted) return;
    ref.read(timingsProvider.notifier).removeForEntry(id);
    notice('Entry removed');
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
