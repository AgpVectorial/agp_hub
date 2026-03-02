import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

  private let channelName = "agp_sdk"
  private let hrEventChannelName = "agp_sdk/hr_stream"

  private var hrEventSink: FlutterEventSink?
  private var hrTimer: Timer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController

    // MethodChannel
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: FlutterResult) in
      guard let self = self else { return }
      switch call.method {

      case "scan":
        // TODO: înlocuiește cu scan real din SDK
        let devices: [[String: Any]] = [
          ["id": "IOS-DEV-001", "name": "Mock Ring iOS", "rssi": -58],
          ["id": "IOS-DEV-002", "name": "Mock Watch iOS", "rssi": -71],
        ]
        result(devices)

      case "connect":
        // TODO: conectează device cu id real
        // let args = call.arguments as? [String: Any]
        result(true)

      case "readMetrics":
        // TODO: citește metrice reale
        let metrics: [String: Any] = ["heartRate": 73, "steps": 1420, "battery": 85]
        result(metrics)

      case "startHeartRateNotifications":
        self.startMockHrStream()
        result(nil)

      case "stopHeartRateNotifications":
        self.stopMockHrStream()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // EventChannel pentru HR live (opțional)
    let hrEventChannel = FlutterEventChannel(name: hrEventChannelName, binaryMessenger: controller.binaryMessenger)
    hrEventChannel.setStreamHandler(self)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startMockHrStream() {
    stopMockHrStream()
    var bpm = 70
    hrTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      guard let sink = self?.hrEventSink else { return }
      bpm += [-1, 0, 1].randomElement()!
      sink(bpm)
    }
  }

  private func stopMockHrStream() {
    hrTimer?.invalidate()
    hrTimer = nil
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    hrEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    hrEventSink = nil
    return nil
  }
}
