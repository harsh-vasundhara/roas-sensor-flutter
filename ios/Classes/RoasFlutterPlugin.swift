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
            if let baseUrl = args["baseUrl"] as? String {
                Roas.configure(
                    publicKey: publicKey,
                    customerUserId: customerUserId,
                    baseUrl: baseUrl,
                    appSecret: appSecret
                )
            } else {
                Roas.configure(
                    publicKey: publicKey,
                    customerUserId: customerUserId,
                    appSecret: appSecret
                )
            }
            result(nil)

        case "visitorId":
            result(Roas.visitorId())

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
