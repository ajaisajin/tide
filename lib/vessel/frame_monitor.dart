import 'dart:collection';

/// Watches frame times and trips once rendering has been slow for a while.
/// Pure Dart: feed it one duration per frame.
///
/// It keeps a rolling average over the last [sampleCount] frames. Whenever
/// that average is above [threshold] the frame's time is added to a running
/// total; whenever it is not, the total goes back to zero. When the total
/// reaches [sustain] the monitor trips, and stays tripped.
///
/// With the defaults that is "slower than 50 frames per second for two
/// seconds". A single long frame lifts the average only until it leaves the
/// rolling window, well short of two seconds, so a spike does not trip it.
class FrameTimeMonitor {
  FrameTimeMonitor({
    this.threshold = const Duration(milliseconds: 20),
    this.sustain = const Duration(seconds: 2),
    this.sampleCount = 30,
  }) : assert(sampleCount > 0);

  final Duration threshold;
  final Duration sustain;
  final int sampleCount;

  final Queue<int> _window = Queue<int>();
  int _windowMicros = 0;
  int _slowMicros = 0;
  bool _tripped = false;

  /// True once slow frames have been sustained. Never goes back to false.
  bool get tripped => _tripped;

  /// The rolling average frame time, zero before the first frame.
  Duration get average => _window.isEmpty
      ? Duration.zero
      : Duration(microseconds: _windowMicros ~/ _window.length);

  /// Records one frame. Returns true on the frame that trips the monitor.
  bool add(Duration frame) {
    if (_tripped) return false;
    final micros = frame.inMicroseconds;
    _window.addLast(micros);
    _windowMicros += micros;
    if (_window.length > sampleCount) _windowMicros -= _window.removeFirst();

    if (_windowMicros > threshold.inMicroseconds * _window.length) {
      // One frozen frame is a hitch, not two seconds of slow rendering, so a
      // single frame counts for at most five thresholds' worth.
      final cap = threshold.inMicroseconds * 5;
      _slowMicros += micros > cap ? cap : micros;
    } else {
      _slowMicros = 0;
    }
    if (_slowMicros >= sustain.inMicroseconds) {
      _tripped = true;
      return true;
    }
    return false;
  }
}
