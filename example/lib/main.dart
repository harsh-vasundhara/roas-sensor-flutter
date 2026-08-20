import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:roas_flutter/roas_flutter.dart';

/// The Flutter twin of `sample/MainActivity.kt` in the native roas-android-sdk
/// repo — same buttons, same values to fill in, so the two are easy to
/// compare side by side while testing.

const String kBaseUrl = 'https://footless-hamper-playlist.ngrok-free.dev'; // reachable regardless of network
// "ROAS Flutter Sample" — this app's OWN site, deliberately not HOP's. Sharing
// HOP's key put sample-app installs inside HOP's retention, fraud and ROAS
// numbers, which is exactly the data the beta exists to read.
const String kPublicKey = '4709392e-486c-4d1f-b79f-50c9a39f515b';

// RevenueCat's public Google API key for this project (Project settings →
// API keys). Not the same as kPublicKey above — that one is ours, this one
// is RevenueCat's.
const String kRevenueCatApiKey = 'test_FzaGVLRLGebnvdQzbrWpjQxAKiR';

/// Beacon signing secret — Setup → your app → Beacon signing → "Generate".
///
/// Read from the build environment rather than written here as a literal, so it
/// never lands in source control:
///
///     flutter run          --dart-define=ROAS_APP_SECRET=xxxxx
///     flutter build appbundle --dart-define=ROAS_APP_SECRET=xxxxx
///
/// Empty (the default) means beacons go out unsigned, which the collector still
/// accepts until "reject unsigned beacons" is switched on for the site — so
/// forgetting the flag degrades to today's behaviour rather than breaking.
const String kAppSecret = String.fromEnvironment('ROAS_APP_SECRET');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This reports the install (first launch) and flushes any queued beacons.
  await Roas.initialize(
    publicKey: kPublicKey,
    baseUrl: kBaseUrl,
    // Empty → null: an empty-string secret would make the SDK sign with a key
    // of "", producing a signature the server computes differently and rejects
    // outright as INVALID. Absent must mean absent.
    appSecret: kAppSecret.isEmpty ? null : kAppSecret,
  );

  // appUserID = our vid, so the purchase RevenueCat's webhook reports later
  // carries the exact visitor whose ad click drove the install.
  final vid = await Roas.visitorId();
  // Guarded because this runs BEFORE runApp(): RevenueCat is a third party
  // whose key here is a placeholder, and an exception at this line would leave
  // the app with no UI at all -- which reads as "the ROAS plugin is broken"
  // when it is nothing of the sort. Attribution does not depend on RevenueCat
  // succeeding; Roas.initialize above has already reported the install.
  try {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey)..appUserID = vid);
  } catch (e) {
    debugPrint('RevenueCat not configured (fine for tracking tests): $e');
  }

  runApp(const RoasSampleApp());
}

class RoasSampleApp extends StatelessWidget {
  const RoasSampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ROASSensor Flutter sample',
      home: const RoasSamplePage(),
    );
  }
}

class RoasSamplePage extends StatefulWidget {
  const RoasSamplePage({super.key});

  @override
  State<RoasSamplePage> createState() => _RoasSamplePageState();
}

class _RoasSamplePageState extends State<RoasSamplePage> {
  // Signing state is shown on screen, not just in the log, because the whole
  // failure mode it guards against is invisible: an unsigned build looks
  // identical to a signed one from the device, and the difference only shows up
  // as beacons silently 401ing once the site enforces.
  final List<String> _log = [
    'ROASSensor Flutter sample',
    'baseUrl: $kBaseUrl',
    kAppSecret.isEmpty
        ? 'signing: OFF (pass --dart-define=ROAS_APP_SECRET=… to enable)'
        : 'signing: ON (secret ${kAppSecret.length} chars)',
    '',
  ];
  List<Package> _packages = [];

  // Deep-link wiring — the ONLY thing in this sample that exercises
  // Roas.handleDeepLink(). Without it, the deep-link → rsclid → backend
  // TouchPoint path (the Android-twin of a Play install referrer, but for a
  // later open of an app that's already installed) had no way to be verified
  // on a real device or emulator: the URL never reached the SDK at all.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _wireDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _wireDeepLinks() async {
    // Cold start: the OS launched this app FROM a link tap, before this
    // widget (or even Roas.initialize in main()) had a chance to see it.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleIncomingLink(initial);
    } catch (e) {
      await _append('→ initial deep link error: $e');
    }
    // Warm start: the app is already running and a link arrives — the
    // Android App Link / iOS universal link equivalent of a browser
    // navigation, which is what handleDeepLink documents itself as being for.
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (Object e) => _append('→ deep link stream error: $e'),
    );
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    await Roas.handleDeepLink(uri.toString());
    final hasRsclid = uri.queryParameters.containsKey('rsclid');
    await _append(
      '→ handleDeepLink($uri) sent'
      '${hasRsclid ? '' : ' — no rsclid in it, so this is a no-op on the native side'}',
    );
  }

  Future<void> _append(String line) async {
    setState(() => _log.add(line));
  }

  // Pulls the current Offering's packages from RevenueCat and adds one "Buy"
  // button per package below the fetch button, so a real purchase is one tap
  // away once a product exists in Play Console + RevenueCat.
  Future<void> _fetchOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        await _append('→ offerings: none configured yet (check RevenueCat dashboard)');
        return;
      }
      await _append(
        "→ offerings: '${current.identifier}' has ${current.availablePackages.length} package(s)",
      );
      setState(() => _packages = current.availablePackages);
    } catch (e) {
      await _append('→ offerings error: $e');
    }
  }

  Future<void> _buyPackage(Package pkg) async {
    try {
      final vid = await Roas.visitorId();
      await Purchases.purchasePackage(pkg);
      await _append('→ purchase completed: ${pkg.storeProduct.identifier} (vid=$vid)');
    } on Exception catch (e) {
      final cancelled = e is PlatformException &&
          PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError;
      await _append(cancelled ? '→ purchase cancelled' : '→ purchase error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ROAS Flutter sample')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await Roas.track(RoasEvent.addToCart, properties: {'sku': 'DEMO-1', 'qty': 1});
                    await _append('→ track(add_to_cart) sent');
                  },
                  child: const Text('Track: add_to_cart'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await Roas.track(RoasEvent.beginCheckout);
                    await _append('→ track(begin_checkout) sent');
                  },
                  child: const Text('Track: begin_checkout'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await Roas.identify(email: 'buyer@example.com');
                    await _append('→ identify(email) sent');
                  },
                  child: const Text('Identify: buyer@example.com'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final vid = await Roas.visitorId();
                    await _append('vid = $vid');
                  },
                  child: const Text('Show visitor id'),
                ),
                ElevatedButton(
                  // The fastest way to exercise the deep-link path with no
                  // adb/Xcode juggling: this fires the exact same code path a
                  // real tap on `roassample://open?rsclid=...` would, since
                  // both end up at _handleIncomingLink -> Roas.handleDeepLink.
                  // To trigger it via a REAL link instead:
                  //   adb shell am start -a android.intent.action.VIEW \
                  //     -d "roassample://open?rsclid=test123"
                  onPressed: () => _handleIncomingLink(
                    Uri.parse('roassample://open?rsclid=manual-test-123'),
                  ),
                  child: const Text('Simulate deep link'),
                ),
                ElevatedButton(
                  onPressed: _fetchOfferings,
                  child: const Text('RevenueCat: fetch offerings'),
                ),                                                                                  
                for (final pkg in _packages)
                  ElevatedButton(
                    onPressed: () => _buyPackage(pkg),
                    child: Text('Buy: ${pkg.identifier} (${pkg.storeProduct.priceString})'),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: _log.map((line) => Text(line, style: const TextStyle(fontSize: 13))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
