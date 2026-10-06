import 'dart:developer';
import 'dart:io';

/// How long ago this process started, in milliseconds, or null where that
/// cannot be read. Linux and Android only.
///
/// It is the monotonic clock now, less the start time in `/proc/self/stat`.
/// That start time counts in hundredths of a second, so the answer is good
/// to about 10 ms. It also counts time the device spent asleep since it
/// booted, which the monotonic clock does not, so the answer is only right
/// on a device that has not slept since boot, such as an emulator. (An app
/// may not read `/proc/uptime`, which would not have that limit.)
int? millisecondsSinceProcessStart() {
  try {
    return millisecondsBetween(
      stat: File('/proc/self/stat').readAsStringSync(),
      monotonicMicros: Timeline.now,
    );
  } catch (_) {
    return null;
  }
}

/// The time from the start recorded in [stat] (the text of
/// `/proc/<pid>/stat`) to [monotonicMicros] since boot, taking the kernel's
/// clock tick as a hundredth of a second, as it is on Android.
int millisecondsBetween({required String stat, required int monotonicMicros}) {
  // The process name, in brackets, may itself hold spaces and brackets. The
  // fields after it start with the state, field 3; the start time is 22.
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  final startTicks = int.parse(fields[22 - 3]);
  return (monotonicMicros / 1000).round() - startTicks * 10;
}
