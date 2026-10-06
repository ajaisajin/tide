import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'start_timing_web.dart' if (dart.library.io) 'start_timing_io.dart';

/// DEVELOPMENT AID, not a product feature.
///
/// In a profile build only, logs how long the app took from the start of its
/// process to its first frame being on the screen, as one line:
///
///     TIDE_START home 412 ms
///
/// [screen] names what that first frame showed: `home`, `setup` or `error`.
/// Call it straight after `runApp`. A debug or release build logs nothing
/// and reads nothing. The README has the commands that use it.
void logStartTime(String screen) {
  if (!kProfileMode) return;
  WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
    final ms = millisecondsSinceProcessStart();
    // ignore: avoid_print
    print('TIDE_START $screen ${ms ?? 'unknown'} ms');
  });
}
