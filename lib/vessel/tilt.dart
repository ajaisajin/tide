import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Opens a stream of roll readings: sideways gravity divided by g, about -1
/// to 1, positive when the phone's left edge is the lower one.
///
/// The sensor is read only while the stream has a listener, so cancelling the
/// subscription is what stops it.
typedef TiltSource = Stream<double> Function();

const double _gravity = 9.80665;

Stream<double> _accelerometerRoll() => accelerometerEventStream(
  samplingPeriod: SensorInterval.gameInterval,
).map((event) => event.x / _gravity);

/// Where the Vessel gets tilt from. The default is the device accelerometer;
/// on web, or with no sensor, that stream is silent, all zeros or an error,
/// each of which leaves the surface level.
///
/// Tests supply their own:
/// `tiltSourceProvider.overrideWithValue(() => controller.stream)`.
final tiltSourceProvider = Provider<TiltSource>((ref) => _accelerometerRoll);
