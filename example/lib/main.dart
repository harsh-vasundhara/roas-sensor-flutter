import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:roas_flutter/roas_flutter.dart';

/// The Flutter twin of `sample/MainActivity.kt` in the native roas-android-sdk
/// repo — same buttons, same values to fill in, so the two are easy to
/// compare side by side while testing.

const String kBaseUrl = 'http://10.0.127.242:8000'; // this PC's LAN IP, for the physical device
const String kPublicKey = '360bd19f-b945-4c44-a410-8f9f14390cce';

// RevenueCat's public Google API key for this project (Project settings →
// API keys). Not the same as kPublicKey above — that one is ours, this one
// is RevenueCat's.
const String kRevenueCatApiKey = 'test_FzaGVLRLGebnvdQzbrWpjQxAKiR';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This reports the install (first launch) and flushes any queued beacons.
  await Roas.initialize(publicKey: kPublicKey, baseUrl: kBaseUrl);

  // appUserID = our vid, so the purchase RevenueCat's webhook reports later
  // carries the exact visitor whose ad click drove the install.
  final vid = await Roas.visitorId();
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey)..appUserID = vid);

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
  final List<String> _log = ['ROASSensor Flutter sample', 'baseUrl: $kBaseUrl', ''];
  List<Package> _packages = [];

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
