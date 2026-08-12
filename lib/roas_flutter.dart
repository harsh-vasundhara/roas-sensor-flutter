import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  static const EventChannel _deliveryChannel =
      EventChannel('roas_flutter/delivery');
  static Stream<RoasDeliveryResult>? _deliveryStream;

  /// Test-only escape hatch for the platform check every method below starts
  /// with. `dart:io`'s [Platform] reports the REAL host OS with no override
  /// hook — on the machine `flutter test` actually runs on (typically macOS,
  /// Linux, or Windows CI), `Platform.isAndroid`/`isIOS` are both false, so
  /// every method would silently take its no-op branch and never touch the
  /// channel at all, making the channel argument contract untestable. Null
  /// (the default) means "ask dart:io for real" — production code must never
  /// set this to anything else.
  @visibleForTesting
  static RoasDebugPlatform? debugPlatformOverride;

  static bool get _isAndroid =>
      debugPlatformOverride?.isAndroid ?? Platform.isAndroid;
  static bool get _isIOS => debugPlatformOverride?.isIOS ?? Platform.isIOS;
  static bool get _supportsNativeChannel => _isAndroid || _isIOS;

  /// Every beacon delivery attempt, success or failure.
  ///
  /// An EventChannel rather than a callback argument because deliveries happen
  /// on the native side long after any Dart call returned — a queued beacon from
  /// a previous offline launch is flushed during `initialize`, and nothing in
  /// Dart is waiting on it.
  ///
  /// Most apps do not need this. It exists because without it a Flutter app that
  /// silently delivers nothing looks exactly like one with no traffic, and lost
  /// beacons are lost touchpoints — which means credit assigned to the wrong
  /// touch, or to none. Wire it to a debug banner in a QA build, or forward it
  /// to your own crash reporting.
  ///
  /// Broadcast and lazily created, so several listeners share one native
  /// subscription. Empty on platforms with no native implementation.
  static Stream<RoasDeliveryResult> get onDeliveryResult {
    if (!_supportsNativeChannel) {
      return const Stream<RoasDeliveryResult>.empty();
    }
    return _deliveryStream ??= _deliveryChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
          final map = (event as Map).cast<Object?, Object?>();
          return RoasDeliveryResult(
            path: map['path'] as String? ?? '',
            success: map['success'] as bool? ?? false,
            error: map['error'] as String?,
          );
        })
        .asBroadcastStream();
  }

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
  /// [requestTrackingAuthorization] (**iOS only**) controls whether the App
  /// Tracking Transparency prompt is shown on first launch. Leave it true and
  /// the prompt appears ~0.6s after this call — a cold-start system alert,
  /// before the user has seen anything worth trusting the app with, which is the
  /// classic way to depress opt-in. Every denial costs the IDFA, the strongest
  /// identity key an iOS install can carry. Pass false and call
  /// [requestTracking] yourself after a priming screen; the SDK binds the IDFA
  /// at that point either way, so deferring costs nothing.
  static Future<void> initialize({
    required String publicKey,
    String? customerUserId,
    String? baseUrl,
    String? appSecret,
    bool requestTrackingAuthorization = true,
  }) {
    if (!_supportsNativeChannel) return Future<void>.value();
    return _channel.invokeMethod<void>('initialize', {
      'publicKey': publicKey,
      'customerUserId': customerUserId,
      'baseUrl': baseUrl,
      'appSecret': appSecret,
      'requestTrackingAuthorization': requestTrackingAuthorization,
    });
  }

  /// **iOS only** — show the ATT prompt now, and bind the IDFA if granted.
  /// A no-op on Android. Pair with
  /// `initialize(requestTrackingAuthorization: false)`.
  ///
  /// Calling this long after the install was reported is fine and is the point:
  /// the install beacon went out with no advertising id, so on a grant the SDK
  /// binds the IDFA through `/identify`, minting the same identity key the
  /// install beacon would have. Safe to call more than once — once the user has
  /// answered, iOS returns the stored answer without re-prompting.
  static Future<void> requestTracking() {
    if (!_isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('requestTracking');
  }

  /// **iOS only** — report a SKAdNetwork conversion value. A no-op on Android.
  ///
  /// For a user who denied ATT — most of them — SKAN is the *only* channel that
  /// tells the ad network the install converted, so leaving this uncalled means
  /// the network has nothing to optimise against and your own SKAN lane records
  /// installs with no events.
  ///
  /// [value] is the fine value, 0–63; its meaning is the site's SKAN schema,
  /// which lives server-side so it can be retuned without an app release.
  /// [coarse] is `'low'`, `'medium'` or `'high'` — **send it**: below Apple's
  /// install-volume privacy threshold the fine value is withheld entirely and
  /// coarse is all that survives the postback, so fine-only reporting goes dark
  /// on exactly the small campaigns that most need measuring. [lockWindow] posts
  /// immediately and discards every later conversion — only when the value is
  /// final.
  static Future<void> updateConversionValue(
    int value, {
    String? coarse,
    bool lockWindow = false,
  }) {
    if (!_isIOS) return Future<void>.value();
    return _channel.invokeMethod<void>('updateConversionValue', {
      'value': value,
      'coarse': coarse,
      'lockWindow': lockWindow,
    });
  }

  /// The stable visitor id for this install (`null` before [initialize] has
  /// run, or on a platform with no native implementation). Pass this to
  /// RevenueCat as the `appUserID` so a purchase attributes back to this
  /// install and its ad click.
  static Future<String?> visitorId() {
    if (!_supportsNativeChannel) return Future<String?>.value();
    return _channel.invokeMethod<String?>('visitorId');
  }

  /// **iOS only** — a UUID derived from the visitor id, to hand StoreKit as the
  /// purchase's `appAccountToken`. Returns null on Android and before
  /// [initialize].
  ///
  /// This is what ties a native App Store purchase back to the install that
  /// drove it: the App Store Server Notification carries the token, and the
  /// backend reconstructs the vid from it. Without it, a Flutter app buying
  /// through `in_app_purchase` (Flutter's own IAP plugin, which is StoreKit —
  /// not RevenueCat) has no path at all from an iOS sale to its ad click, so the
  /// revenue lands UNATTRIBUTED while the spend still counts and iOS ROAS reads
  /// low enough to kill a working campaign.
  ///
  /// ```dart
  /// final token = await Roas.appAccountToken();
  /// await InAppPurchase.instance.buyConsumable(
  ///   purchaseParam: AppStorePurchaseParam(
  ///     productDetails: product,
  ///     applicationUserName: token, // iOS: becomes appAccountToken
  ///   ),
  /// );
  /// ```
  ///
  /// Not needed with RevenueCat — that path uses [visitorId] as the `appUserID`
  /// instead. **Android's analogue is [visitorId] itself**: pass it to Play
  /// Billing as `obfuscatedAccountId` and the Play webhook resolves it the same
  /// way.
  static Future<String?> appAccountToken() {
    if (!_supportsNativeChannel) return Future<String?>.value();
    return _channel.invokeMethod<String?>('appAccountToken');
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
    if (!_supportsNativeChannel) return Future<void>.value();
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
    if (!_supportsNativeChannel) return Future<void>.value();
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
    if (!_supportsNativeChannel) return Future<void>.value();
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
    if (!_supportsNativeChannel) return Future<void>.value();
    // Uppercased to match RoasLogLevel's Kotlin/Swift enum case names exactly.
    return _channel.invokeMethod<void>('setLogLevel', {'level': level.name.toUpperCase()});
  }
}

/// Mirrors `RoasLogLevel` in `Roas.kt` / `RoasLogLevel.swift`.
enum RoasLogLevel { none, error, debug }

/// Test-only values for [Roas.debugPlatformOverride] — see its doc comment.
/// Not `bool` because several methods below need to tell Android and iOS
/// apart (e.g. [Roas.requestTracking] is iOS-only), which a single flag can't
/// express.
enum RoasDebugPlatform {
  android,
  ios;

  bool get isAndroid => this == RoasDebugPlatform.android;
  bool get isIOS => this == RoasDebugPlatform.ios;
}

/// One beacon delivery attempt, from [Roas.onDeliveryResult].
class RoasDeliveryResult {
  const RoasDeliveryResult({
    required this.path,
    required this.success,
    this.error,
  });

  /// The endpoint, e.g. `/api/tracking/mobile/first-open`.
  final String path;
  final bool success;

  /// Null on success. Note that a beacon which fails here is not necessarily
  /// lost — the native queue is persisted and retries on a later launch.
  final String? error;

  @override
  String toString() => success
      ? 'RoasDeliveryResult($path, ok)'
      : 'RoasDeliveryResult($path, failed: $error)';
}

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
