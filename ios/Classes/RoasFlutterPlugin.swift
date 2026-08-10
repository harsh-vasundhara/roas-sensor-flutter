import Flutter
import UIKit
import RoasSensor

/// The iOS half of the `roas_flutter` bridge. Every method here is a thin
/// pass-through to `Roas` (`RoasSensor`'s public entry point, from sdk-ios)
/// — no retry/queueing/hashing logic is duplicated here; that all still
/// lives in the native SDK, exactly as it does for a pure-Swift app. Mirrors
/// `RoasFlutterPlugin.kt`'s Android half method-for-method so the two
/// platforms behave identically from the Dart side.
public class RoasFlutterPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "roas_flutter", binaryMessenger: registrar.messenger())
        let instance = RoasFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Delivery results are pushed, not requested — a beacon queued on a
        // previous offline launch is flushed during configure, with nothing in
        // Dart awaiting it — so they need a stream, not a method result.
        let delivery = FlutterEventChannel(
            name: "roas_flutter/delivery", binaryMessenger: registrar.messenger()
        )
        delivery.setStreamHandler(RoasDeliveryStreamHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard
                let args = call.arguments as? [String: Any],
                let publicKey = args["publicKey"] as? String
            else {
                result(FlutterError(code: "MISSING_ARG", message: "publicKey is required", details: nil))
                return
            }
            let customerUserId = args["customerUserId"] as? String
            let appSecret = args["appSecret"] as? String
            // Defaults to true to match Roas.configure, so an app that never
            // passes the flag behaves exactly as before.
            let ask = args["requestTrackingAuthorization"] as? Bool ?? true
            if let baseUrl = args["baseUrl"] as? String {
                Roas.configure(
                    publicKey: publicKey,
                    customerUserId: customerUserId,
                    requestTrackingAuthorization: ask,
                    appSecret: appSecret,
                    baseUrl: baseUrl
                )
            } else {
                Roas.configure(
                    publicKey: publicKey,
                    customerUserId: customerUserId,
                    requestTrackingAuthorization: ask,
                    appSecret: appSecret
                )
            }
            result(nil)

        case "requestTracking":
            // Answers only once ATT has resolved, so Dart can await the prompt
            // and know the IDFA binding has been attempted before continuing.
            Roas.requestTrackingAuthorization { result(nil) }

        case "updateConversionValue":
            guard
                let args = call.arguments as? [String: Any],
                let value = args["value"] as? Int
            else {
                result(FlutterError(code: "MISSING_ARG", message: "value is required", details: nil))
                return
            }
            Roas.updateConversionValue(
                value,
                coarse: args["coarse"] as? String,
                lockWindow: args["lockWindow"] as? Bool ?? false
            )
            result(nil)

        case "visitorId":
            result(Roas.visitorId())

        case "appAccountToken":
            // Handed to StoreKit on a purchase so the App Store Server
            // Notification carries it back and the backend can rebuild the vid.
            result(Roas.appAccountToken()?.uuidString)

        case "identify":
            let args = call.arguments as? [String: Any]
            Roas.identify(
                email: args?["email"] as? String,
                phone: args?["phone"] as? String,
                customerUserId: args?["customerUserId"] as? String
            )
            result(nil)

        case "track":
            guard
                let args = call.arguments as? [String: Any],
                let eventKey = args["event"] as? String
            else {
                result(FlutterError(code: "MISSING_ARG", message: "event is required", details: nil))
                return
            }
            let properties = args["properties"] as? [String: Any]
            // Anything not in the RoasEvent taxonomy is still tracked — as a
            // custom event named exactly what the caller passed, mirroring
            // Roas.track(.custom, name: "...") in the native sample and the
            // Android plugin's identical fallback.
            if let known = RoasEvent(rawValue: eventKey), known != .custom {
                Roas.track(known, properties: properties)
            } else {
                Roas.track(.custom, name: eventKey, properties: properties)
            }
            result(nil)

        case "handleDeepLink":
            guard
                let args = call.arguments as? [String: Any],
                let urlString = args["url"] as? String,
                let url = URL(string: urlString)
            else {
                result(FlutterError(code: "MISSING_ARG", message: "url is required", details: nil))
                return
            }
            Roas.handleDeepLink(url)
            result(nil)

        case "setLogLevel":
            let args = call.arguments as? [String: Any]
            let levelName = (args?["level"] as? String) ?? "ERROR"
            let level: RoasLogLevel
            switch levelName {
            case "NONE": level = .none
            case "DEBUG": level = .debug
            default: level = .error
            }
            Roas.setLogLevel(level)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Feeds `Roas.setOnDeliveryResult` into the `roas_flutter/delivery`
/// EventChannel, mirroring `RoasFlutterPlugin.kt`'s StreamHandler.
///
/// The native callback is a process-wide singleton, so it is cleared on cancel:
/// left pointing at a torn-down engine's sink it would leak the engine and fire
/// into a dead channel on the first delivery after a hot restart.
private class RoasDeliveryStreamHandler: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        Roas.setOnDeliveryResult { [weak self] path, success, error in
            // Transport delivers off the main thread; a FlutterEventSink must be
            // invoked on it, and breaking that crashes rather than misbehaves.
            DispatchQueue.main.async {
                self?.sink?([
                    "path": path,
                    "success": success,
                    // NSNull, not `error as Any` — the latter boxes a nil
                    // Optional, which FlutterStandardWriter cannot encode.
                    // NSNull crosses cleanly and arrives in Dart as null.
                    "error": error ?? NSNull(),
                ])
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        Roas.setOnDeliveryResult(nil)
        sink = nil
        return nil
    }
}
