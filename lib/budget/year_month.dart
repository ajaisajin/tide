/// A calendar month and the instants that bound it. Pure Dart: imports nothing
/// from Flutter.
library;

/// One calendar month, for example October 2026.
///
/// Compares and sorts in calendar order. Its text form is `YYYY-MM`, which is
/// also the key the saved ledger uses for a month's budget.
class YearMonth implements Comparable<YearMonth> {
  /// [month] is 1 to 12.
  const YearMonth(this.year, this.month)
    : assert(month >= 1 && month <= 12, 'month is 1 to 12');

  /// The calendar month [moment] falls in, read from its own `year` and
  /// `month` fields. Pass a local time to get the local month.
  YearMonth.of(DateTime moment) : this(moment.year, moment.month);

  /// Parses `YYYY-MM`. Throws a [FormatException] for anything else.
  factory YearMonth.parse(String text) {
    final parsed = tryParse(text);
    if (parsed == null) {
      throw FormatException('Not a month in YYYY-MM form', text);
    }
    return parsed;
  }

  /// Parses `YYYY-MM`, or returns null when [text] is not in that form.
  static YearMonth? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return YearMonth(int.parse(match.group(1)!), month);
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})$');

  final int year;
  final int month;

  /// The month after this one. December is followed by January.
  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  /// The month before this one. January is preceded by December.
  YearMonth get previous =>
      month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);

  /// The first instant of this month in the device's local time.
  DateTime get localStart => DateTime(year, month);

  /// The first instant of the following month in the device's local time.
  /// This month's instants are those from [localStart] up to, but not
  /// including, this one.
  DateTime get localEnd => DateTime(year, month + 1);

  /// `YYYY-MM`, for example `2026-10`.
  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  bool isBefore(YearMonth other) => compareTo(other) < 0;
  bool isAfter(YearMonth other) => compareTo(other) > 0;

  @override
  int compareTo(YearMonth other) =>
      year != other.year ? year.compareTo(other.year) : month - other.month;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}

/// The stretch of universal time that one local calendar month covers:
/// from [startUtc] up to, but not including, [endUtc].
class MonthUtcBounds {
  /// Both instants are converted to UTC, so either local or UTC values may be
  /// passed.
  MonthUtcBounds({required DateTime start, required DateTime end})
    : startUtc = start.toUtc(),
      endUtc = end.toUtc();

  /// The first instant of the month, in UTC.
  final DateTime startUtc;

  /// The first instant of the next month, in UTC. Not part of the month.
  final DateTime endUtc;

  /// [startUtc] as milliseconds since the Unix epoch.
  int get startMillis => startUtc.millisecondsSinceEpoch;

  /// [endUtc] as milliseconds since the Unix epoch. Not part of the month.
  int get endMillis => endUtc.millisecondsSinceEpoch;

  /// Whether [instant] falls in the month. Local and UTC values of the same
  /// instant give the same answer.
  bool contains(DateTime instant) =>
      containsMillis(instant.millisecondsSinceEpoch);

  /// Whether the instant [millisecondsSinceEpoch] falls in the month.
  bool containsMillis(int millisecondsSinceEpoch) =>
      millisecondsSinceEpoch >= startMillis &&
      millisecondsSinceEpoch < endMillis;

  @override
  bool operator ==(Object other) =>
      other is MonthUtcBounds &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc;

  @override
  int get hashCode => Object.hash(startUtc, endUtc);

  @override
  String toString() => 'MonthUtcBounds($startUtc to $endUtc)';
}

/// The UTC bounds of [month] in the device's local time zone.
///
/// The conversion is the platform's: the month's local first instant and the
/// next month's local first instant, each through `DateTime.toUtc()`. That
/// follows whatever daylight-saving rules the device has.
MonthUtcBounds monthUtcBounds(YearMonth month) =>
    MonthUtcBounds(start: month.localStart, end: month.localEnd);

/// The UTC bounds of [month] in a zone that is always [utcOffset] ahead of
/// UTC, whatever zone the device is in. Indian time is
/// `Duration(hours: 5, minutes: 30)`.
///
/// Only correct for zones without daylight saving. The app itself uses
/// [monthUtcBounds]; this exists so the arithmetic can be checked for a named
/// zone on any machine.
MonthUtcBounds monthUtcBoundsAtOffset(YearMonth month, Duration utcOffset) =>
    MonthUtcBounds(
      start: DateTime.utc(month.year, month.month).subtract(utcOffset),
      end: DateTime.utc(month.year, month.month + 1).subtract(utcOffset),
    );
