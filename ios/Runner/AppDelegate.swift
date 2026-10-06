import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Keeps Tide's saved data out of iCloud and computer backups: the key that
    // opens it stays in this device's Keychain. Called from
    // lib/storage/backup_exclusion.dart with the ledger's directory.
    // Written on a machine that cannot build iOS; not yet compiled or run.
    let backup = FlutterMethodChannel(
      name: "app.tide/backup",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backup.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(FlutterError(code: "bad_arguments", message: "path is required", details: nil))
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "not_excluded", message: error.localizedDescription, details: nil))
      }
    }
  }
}
