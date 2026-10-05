import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True once rendering has been too slow for too long (see FrameTimeMonitor).
/// It then stays true until the app is next launched; the Vessel shows still
/// water and stops reading the sensor.
class SlowFrames extends Notifier<bool> {
  @override
  bool build() => false;

  void trip() => state = true;
}

final slowFramesProvider = NotifierProvider<SlowFrames, bool>(SlowFrames.new);

/// Loads the liquid's fragment program, or returns null when it cannot be
/// used, in which case the Vessel paints the liquid with paths instead.
typedef LiquidProgramLoader = Future<ui.FragmentProgram?> Function();

Future<ui.FragmentProgram?> _loadLiquidProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset('shaders/liquid.frag');
  } catch (error) {
    debugPrint('Tide: liquid shader unavailable, using paths: $error');
    return null;
  }
}

/// How the Vessel gets its shader. Widget tests cannot load a fragment
/// program, so they turn it off:
/// `liquidProgramLoaderProvider.overrideWithValue(noLiquidProgram)`.
final liquidProgramLoaderProvider = Provider<LiquidProgramLoader>(
  (ref) => _loadLiquidProgram,
);

/// A [LiquidProgramLoader] that never loads anything.
Future<ui.FragmentProgram?> noLiquidProgram() async => null;
