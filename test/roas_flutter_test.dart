import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roas_flutter/roas_flutter.dart';

/// Platform-channel contract tests for the Dart half of the bridge.
///
/// `Roas.kt`'s own comments describe a real production bug from exactly this
/// boundary: a parameter added anywhere but the end of an argument list
/// silently rebinds every positional call one slot along, and it still
/// compiles because the types line up. This SDK bridge sends everything as a
/// NAMED argument map precisely to make that class of bug impossible — but
/// nothing verified that until now. These tests pin the exact map each method
/// sends, so a future edit that drops/renames/misplaces a key fails here
/// instead of silently reaching a device as a wrong host, an unsigned beacon,
/// or a swallowed deep link.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('roas_flutter');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    // Every test in this file runs as if it were Android — dart:io's real
    // Platform reports the host `flutter test` runs on (not a mobile OS), so
    // without this override every method below would take its no-op branch
    // and never touch the channel at all. See Roas.debugPlatformOverride.
    Roas.debugPlatformOverride = RoasDebugPlatform.android;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'visitorId':
          return 'rs-test-vid';
        case 'appAccountToken':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    Roas.debugPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('initialize', () {
    test('sends every argument as a named map entry, nothing positional', () async {
      await Roas.initialize(
        publicKey: 'site-key',
        customerUserId: 'user-42',
        baseUrl: 'https://collector.example.com',
        appSecret: 'shh',
        requestTrackingAuthorization: false,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'initialize');
      expect(calls.single.arguments, {
        'publicKey': 'site-key',
        'customerUserId': 'user-42',
        'baseUrl': 'https://collector.example.com',
        'appSecret': 'shh',
        'requestTrackingAuthorization': false,
      });
    });

    test('optional arguments default to null/true without shifting keys', () async {
      await Roas.initialize(publicKey: 'site-key');

      expect(calls.single.arguments, {
        'publicKey': 'site-key',
        'customerUserId': null,
        'baseUrl': null,
        'appSecret': null,
        'requestTrackingAuthorization': true,
      });
    });
  });

  test('identify sends email/phone/customerUserId verbatim', () async {
    await Roas.identify(email: 'buyer@example.com', customerUserId: 'user-42');

    expect(calls.single.method, 'identify');
    expect(calls.single.arguments, {
      'email': 'buyer@example.com',
      'phone': null,
      'customerUserId': 'user-42',
    });
  });

  group('track', () {
    test('a known RoasEvent key is forwarded with its properties', () async {
      await Roas.track(RoasEvent.addToCart, properties: {'sku': 'DEMO-1', 'qty': 1});

      expect(calls.single.method, 'track');
      expect(calls.single.arguments, {
        'event': 'add_to_cart',
        'properties': {'sku': 'DEMO-1', 'qty': 1},
      });
    });

    test('an unrecognised event name is still forwarded, not dropped', () async {
      // The native side falls back to a custom event for anything outside
      // RoasEvent's taxonomy — the bridge must not filter it out first.
      await Roas.track('my_custom_event');

      expect(calls.single.arguments, {
        'event': 'my_custom_event',
        'properties': null,
      });
    });
  });

  test('handleDeepLink forwards the raw url unmodified', () async {
    const url = 'https://example.com/open?rsclid=AbC123&utm_source=meta';
    await Roas.handleDeepLink(url);

    expect(calls.single.method, 'handleDeepLink');
    expect(calls.single.arguments, {'url': url});
  });

  test('setLogLevel uppercases the level name to match the native enum', () async {
    await Roas.setLogLevel(RoasLogLevel.debug);

    expect(calls.single.method, 'setLogLevel');
    expect(calls.single.arguments, {'level': 'DEBUG'});
  });

  group('iOS-only methods', () {
    test('requestTracking is a no-op on Android and never reaches the channel', () async {
      Roas.debugPlatformOverride = RoasDebugPlatform.android;
      await Roas.requestTracking();
      expect(calls, isEmpty);
    });

    test('requestTracking invokes the channel on iOS', () async {
      Roas.debugPlatformOverride = RoasDebugPlatform.ios;
      await Roas.requestTracking();
      expect(calls.single.method, 'requestTracking');
    });

    test('updateConversionValue is a no-op on Android', () async {
      Roas.debugPlatformOverride = RoasDebugPlatform.android;
      await Roas.updateConversionValue(42, coarse: 'high', lockWindow: true);
      expect(calls, isEmpty);
    });

    test('updateConversionValue sends value/coarse/lockWindow on iOS', () async {
      Roas.debugPlatformOverride = RoasDebugPlatform.ios;
      await Roas.updateConversionValue(42, coarse: 'high', lockWindow: true);

      expect(calls.single.method, 'updateConversionValue');
      expect(calls.single.arguments, {
        'value': 42,
        'coarse': 'high',
        'lockWindow': true,
      });
    });
  });

  group('platform guarding on an unsupported host', () {
    setUp(() {
      // Neither Android nor iOS — the real situation `flutter test` runs
      // under on a dev machine, simulated explicitly here rather than relying
      // on the host OS the CI happens to run on.
      Roas.debugPlatformOverride = null;
    });

    test('every method resolves to its documented no-op instead of throwing', () async {
      // No channel handler registered at all in this group — if any of these
      // reached the channel without one, the call would throw a
      // MissingPluginException instead of resolving quietly.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await Roas.initialize(publicKey: 'site-key');
      await Roas.identify(email: 'buyer@example.com');
      await Roas.track(RoasEvent.addToCart);
      await Roas.handleDeepLink('https://example.com?rsclid=x');
      await Roas.setLogLevel(RoasLogLevel.debug);
      await Roas.requestTracking();
      await Roas.updateConversionValue(1);

      expect(await Roas.visitorId(), isNull);
      expect(await Roas.appAccountToken(), isNull);
      expect(await Roas.onDeliveryResult.isEmpty, isTrue);
    });
  });
}
