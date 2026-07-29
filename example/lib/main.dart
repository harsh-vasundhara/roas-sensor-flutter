import 'package:flutter/material.dart';
import 'package:roas_flutter/roas_flutter.dart';

/// The Flutter twin of `sample/MainActivity.kt` in the native roas-android-sdk
/// repo — same buttons, same values to fill in, so the two are easy to
/// compare side by side while testing.
///
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │ FILL IN THE TWO VALUES BELOW before running.                        │
/// └─────────────────────────────────────────────────────────────────────┘
const String kBaseUrl = 'http://10.0.2.2:8000'; // emulator alias for localhost
const String kPublicKey = '360bd19f-b945-4c44-a410-8f9f14390cce';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Roas.initialize(publicKey: kPublicKey, baseUrl: kBaseUrl);
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

  Future<void> _append(String line) async {
    setState(() => _log.add(line));
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
