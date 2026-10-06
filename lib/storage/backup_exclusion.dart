/// Keeping the ledger's files out of iOS backups.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel answered by `ios/Runner/AppDelegate.swift`.
const MethodChannel backupExclusionChannel = MethodChannel('app.tide/backup');

/// Marks the file or directory at [path] as excluded from iCloud and
/// computer backups. Returns whether the mark was set.
///
/// Does something on iOS only. Everywhere else it returns false without
/// calling the platform: Android excludes all of the app's data through its
/// manifest instead (`allowBackup="false"` and the data-extraction rules).
///
/// It never throws: failing to set the mark must not stop the ledger
/// opening. Not yet run on a real iOS build.
Future<bool> excludeFromBackup(String path) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    final done = await backupExclusionChannel.invokeMethod<bool>(
      'excludeFromBackup',
      {'path': path},
    );
    return done ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
