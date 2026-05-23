import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ── تسجيل مؤثرات الصوت ──
    let controller = window?.rootViewController as! FlutterViewController
    AudioEffectsPlugin.register(
      with: controller.registrar(forPlugin: "AudioEffectsPlugin")!
    )

    GeneratedPluginRegistrant.register(with: self)
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }
}