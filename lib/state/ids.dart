int _counter = 0;

/// Returns an id that is unique within this run of the app.
///
/// The technical specification calls for UUID v7 once data is persisted. Until
/// then entries live in memory only, so a timestamp plus a counter is enough
/// and avoids adding a package.
String newEntryId() {
  _counter++;
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'e-$micros-${_counter.toRadixString(36)}';
}
