import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the log flow is covering the Vessel. This is the app's only
/// navigation state: false shows the Vessel, true puts the log flow on top.
class LogFlowOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void close() => state = false;
}

/// Watch for the current layer; open and close with
/// `ref.read(logFlowOpenProvider.notifier).open()` and `.close()`.
final logFlowOpenProvider = NotifierProvider<LogFlowOpen, bool>(
  LogFlowOpen.new,
);
