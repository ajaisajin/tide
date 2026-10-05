import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two controls that share one area of the log flow.
enum EntryPanel { pad, ring }

/// Which of the ring and the pad the log flow shows. Remembered for the
/// session, so the flow reopens on the one used last.
class EntryPanelChoice extends Notifier<EntryPanel> {
  @override
  EntryPanel build() => EntryPanel.pad;

  void choose(EntryPanel panel) => state = panel;
}

final entryPanelProvider = NotifierProvider<EntryPanelChoice, EntryPanel>(
  EntryPanelChoice.new,
);
