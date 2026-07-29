import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Flutter bridge for the ROASSensor Android SDK (`com.roassensor.sdk.Roas`).
///
/// This is Android-only today — there is no iOS SDK yet, so every call here
/// is a no-op on iOS rather than a crash (checked via [Platform] at the call
/// site, not hidden inside the channel, so callers can see exactly what
/// happens on each OS).
///
/// The wire format matches the native SDK's `/api/tracking/mobile/*`
/// beacons exactly — this is a thin bridge, not a reimplementation. See
/// `Roas.kt` in the `roas-android-sdk` repo for the source of truth.
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
  static Future<void> initialize({
    required String publicKey,
    String? customerUserId,
    String? baseUrl,
  }) {
    if (!Platform.isAndroid) return Future<void>.value();
    return _channel.invokeMethod<void>('initialize', {
      'publicKey': publicKey,
      'customerUserId': customerUserId,
      'baseUrl': baseUrl,
    });
  }

  /// The stable visitor id for this install (`null` before [initialize] has
  /// run, or on any platform other than Android). Pass this to RevenueCat as
  /// the `appUserID` so a purchase attributes back to this install and its
  /// ad click.
  static Future<String?> visitorId() {
    if (!Platform.isAndroid) return Future<String?>.value();
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
    if (!Platform.isAndroid) return Future<void>.value();
    return _channel.invokeMethod<void>('identify', {
      'email': email,
      'phone': phone,
      'customerUserId': customerUserId,
    });
  }

  /// Record a funnel/behaviour event — never revenue (see `RoasEvent.kt`:
  /// money only ever enters through the signed RevenueCat/Stripe webhook).
  ///
  /// [event] should be one of the known keys native `RoasEvent` defines
  /// (e.g. `"add_to_cart"`, `"begin_checkout"`, `"sign_up"` — see
  /// [RoasEvent] below for the full list as constants). Anything else is
  /// sent as a custom event named [event] — matching how the native sample
  /// app calls `Roas.track(RoasEvent.CUSTOM, name = "...")`.
  static Future<void> track(String event, {Map<String, Object?>? properties}) {
    if (!Platform.isAndroid) return Future<void>.value();
    return _channel.invokeMethod<void>('track', {
      'event': event,
      'properties': properties,
    });
  }
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
