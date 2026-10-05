/// The Vessel's layout maths as pure functions. Pure Dart.
library;

/// Liquid height at fill level 0, as a fraction of the screen height.
const double liquidFloorFraction = 0.08;

/// Liquid height at fill level 1, as a fraction of the screen height.
const double liquidCeilingFraction = 0.70;

/// The least distance, in logical pixels, kept between the floor and the
/// ceiling when the text above leaves very little room.
const double _minLiquidRange = 24;

/// The liquid's height in logical pixels for a fill [level] between 0 and 1.
///
/// The height runs from a floor of 8% of [screenHeight] at level 0 (so a band
/// of liquid always shows) to a ceiling of 70% at level 1. [maxHeight], when
/// given, is the room actually free below the text; if it is less than 70% of
/// the screen the ceiling comes down to it, so the liquid never reaches the
/// text however large the text is. The mapping stays linear between floor and
/// ceiling, so equal changes in level always move the surface equally.
double liquidHeight({
  required double level,
  required double screenHeight,
  double? maxHeight,
}) {
  final floor = screenHeight * liquidFloorFraction;
  final ceiling = _ceiling(screenHeight, floor, maxHeight);
  return floor + level.clamp(0.0, 1.0) * (ceiling - floor);
}

/// The overspent band's height in logical pixels: 6% of [screenHeight], plus
/// up to 20% more as the overspend grows to half of what was available.
double overspentHeight({
  required int overByMinor,
  required int availableMinor,
  required double screenHeight,
  double? maxHeight,
}) {
  final available = availableMinor > 0 ? availableMinor : 1;
  final ratio = (overByMinor / available).clamp(0.0, 0.5);
  final height = screenHeight * (0.06 + ratio * 0.40);
  final ceiling = _ceiling(
    screenHeight,
    screenHeight * liquidFloorFraction,
    maxHeight,
  );
  return height > ceiling ? ceiling : height;
}

double _ceiling(double screenHeight, double floor, double? maxHeight) {
  var ceiling = screenHeight * liquidCeilingFraction;
  if (maxHeight != null && maxHeight < ceiling) ceiling = maxHeight;
  if (ceiling < floor + _minLiquidRange) ceiling = floor + _minLiquidRange;
  return ceiling;
}

/// The smallest pebble: a comfortable touch target.
const double pebbleMinDiameter = 64;

/// How much a pebble grows between 0% and 100% of its category's limit.
const double pebbleMaxGrowth = 34;

/// How far an over-limit pebble sinks below the others.
const double pebbleSunkOffset = 26;

/// A pebble's diameter in logical pixels for a [share] of the category limit
/// (0.39 for 39%). Never below [pebbleMinDiameter]; stops growing at 100%.
/// [growth] is the most it may grow, reduced on narrow screens.
double pebbleDiameter(double share, {double growth = pebbleMaxGrowth}) {
  final s = share.isNaN ? 0.0 : share.clamp(0.0, 1.0);
  final g = growth < 0 ? 0.0 : growth;
  return pebbleMinDiameter + s * g;
}

/// The most a pebble may grow so that [perRow] pebbles at full size, [gap]
/// apart, fit in [width].
double pebbleGrowthFor(double width, {int perRow = 3, double gap = 10}) {
  final each = (width - gap * (perRow - 1)) / perRow;
  return (each - pebbleMinDiameter).clamp(0.0, pebbleMaxGrowth);
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The English name of [month], 1 for January to 12 for December.
String monthName(int month) => _monthNames[(month - 1) % 12];
