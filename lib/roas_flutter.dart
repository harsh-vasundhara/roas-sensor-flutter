import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Flutter bridge for the ROASSensor Android (`com.roassensor.sdk.Roas`) and
/// iOS (`RoasSensor.Roas`) native SDKs.
///
/// Android and iOS both have a native implementation behind this channel;
/// every other platform (web, desktop) is a no-op rather than a crash
/// (checked via [Platform] at the call site, not hidden inside the channel,
/// so callers can see exactly what happens on each OS).
///
/// The wire format matches both native SDKs' `/api/tracking/mobile/*`
/// beacons exactly — this is a thin bridge, not a reimplementation. See
/// `Roas.kt` in `sdk-android` and `Roas.swift` in `sdk-ios` for the source of
/// truth. The iOS side is newly added and, unlike the Android side, has not
/// yet been proven on-device (no Xcode/macOS available where it was
/// written) — see the package README before relying on it.
class Roas {
  Roas._();

  static const MethodChannel _channel = MethodChannel('roas_flutter');

  /// Start the SDK. Call once, as early as possible — e.g. in `main()`
  /// before `runApp()`. Idempotent on the native side: a second call is a
  /// no-op there, but still cheap to call again defensively.
  ///
  /// [publicKey] is the app property's public key from ROASSensor's Tracking
  /// Setup page. [baseUrl] overrides the collector host (defaults to
  /// production on the native side). [customerUserId] is your own user id if
  /// already known at launch.
  /// [appSecret] is this property's beacon signing secret (Setup → your app →
  /// Beacon signing). Optional: without it beacons go unsigned, which the
  /// collector accepts until you turn on "reject unsigned beacons". It is NOT a
  /// revenue credential — that is the server-side api key, which must never
  /// ship inside an app. The worst an extracted one allows is forging beacons,
  /// which the public key alone already allowed, and rotating it invalidates
  /// every build carrying the old one. Prefer `--dart-define` over a literal so
  /// it stays out of source control.
  static Future<void> initialize({
    required String publicKey,
    String? customerUserId,
    String? baseUrl,
    String? appSecret,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('initialize', {
      'publicKey': publicKey,
      'customerUserId': customerUserId,
      'baseUrl': baseUrl,
      'appSecret': appSecret,
    });
  }

  /// The stable visitor id for this install (`null` before [initialize] has
  /// run, or on a platform with no native implementation). Pass this to
  /// RevenueCat as the `appUserID` so a purchase attributes back to this
  /// install and its ad click.
  static Future<String?> visitorId() {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<String?>.value();
    return _channel.invokeMethod<String?>('visitorId');
  }

  /// Bind the user's identity. At least one of [email]/[phone] must be
  /// non-null for this to send anything. Hashed on-device by the native SDK
  /// — this bridge never sees or sends raw PII differently than the native
  /// code already does.
  static Future<void> identify({
    String? email,
    String? phone,
    String? customerUserId,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('identify', {
      'email': email,
      'phone': phone,
      'customerUserId': customerUserId,
    });
  }

  /// Record a funnel/behaviour event — never revenue (see `RoasEvent.kt` /
  /// `RoasEvent.swift`: money only ever enters through the signed
  /// RevenueCat/Stripe webhook).
  ///
  /// [event] should be one of the known keys native `RoasEvent` defines on
  /// both platforms (e.g. `"add_to_cart"`, `"begin_checkout"`, `"sign_up"` —
  /// see [RoasEvent] below for the full list as constants). Anything else is
  /// sent as a custom event named [event] — matching how the native samples
  /// call `Roas.track(RoasEvent.CUSTOM, name = "...")` (Kotlin) /
  /// `Roas.track(.custom, name: "...")` (Swift).
  static Future<void> track(String event, {Map<String, Object?>? properties}) {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('track', {
      'event': event,
      'properties': properties,
    });
  }

  /// Forward a direct deep link (a link that opened the app while it was
  /// already installed — an Android App Link or an iOS universal link) so
  /// its `rsclid` attributes this open deterministically. A no-op if [url]
  /// carries no `rsclid` query parameter. This is *not* the install-referrer
  /// path (that's automatic on first launch) — it's for a later open.
  static Future<void> handleDeepLink(String url) {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('handleDeepLink', {'url': url});
  }

  /// Controls how much the native SDK writes to Logcat (Android) / the
  /// console (iOS). Defaults to [RoasLogLevel.error] on the native side —
  /// quiet in a release build, but enough to see a device that can never
  /// deliver anything. Delivery success/failure was previously invisible
  /// from Dart entirely; this at least makes it inspectable via the
  /// device's own native logs while a full Dart-side delivery callback
  /// (an EventChannel) remains a follow-up, not yet built.
  static Future<void> setLogLevel(RoasLogLevel level) {
    if (!Platform.isAndroid && !Platform.isIOS) return Future<void>.value();
    // Uppercased to match RoasLogLevel's Kotlin/Swift enum case names exactly.
    return _channel.invokeMethod<void>('setLogLevel', {'level': level.name.toUpperCase()});
  }
}

/// Mirrors `RoasLogLevel` in `Roas.kt` / `RoasLogLevel.swift`.
enum RoasLogLevel { none, error, debug }

/// The known event keys `RoasEvent.kt` defines natively — mirrored here as
/// plain strings so Dart code gets autocomplete without needing a generated
/// enum bridge. Anything not in this list is still valid: [Roas.track] sends
/// it as a custom event with that exact name.
abstract final class RoasEvent {
  static const viewContent = 'view_content';
  static const addToCart = 'add_to_cart';
  static const addToWishlist = 'add_to_wishlist';
  static const beginCheckout = 'begin_checkout';
  static const search = 'search';
  static const lead = 'lead';
  static const signUp = 'sign_up';
  static const login = 'login';
  static const startTrial = 'start_trial';
  static const subscribe = 'subscribe';
  static const levelStart = 'level_start';
  static const levelComplete = 'level_complete';
  static const tutorialComplete = 'tutorial_complete';
  static const share = 'share';
}
