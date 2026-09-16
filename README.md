# roas_flutter

A thin Flutter bridge to the native **roas-android-sdk**
(`com.roassensor.sdk.Roas`) and **RoasSensor iOS SDK** (`RoasSensor.Roas`,
from `sdk-ios`). Both platforms have a native implementation behind this
bridge — every other platform (web, desktop) is a no-op, not a crash.

This package does not reimplement any tracking logic. Every call is a direct
pass-through to the native SDK for that platform — the same install-referrer
reading (Android) / ATT+IDFA+ASA+SKAdNetwork handling (iOS), on-device
hashing, and persisted retry queue a pure-Kotlin or pure-Swift app gets. See
`Roas.kt` in `sdk-android` and `Roas.swift` in `sdk-ios` for the actual
implementations.

## ✅ Verified end to end (Android)

This package was written directly against the real `Roas.kt`/`RoasEvent.kt`
source, then actually proven, not just compiled — both on an emulator and on
a physical device:

- Built and installed a debug APK on an Android **emulator**, then again on a
  **physical device** (Realme RMX1941, Android 9) over the same LAN as the
  backend.
- `initialize()`, `track()`, and `identify()` all confirmed reaching the
  native plugin, and the resulting beacons confirmed landing in the Django
  backend's database (`TouchPoint`/`Event` rows with matching visitor ids) —
  on both the emulator run and the physical-device run.
- Two real bugs were caught and fixed doing this: the example app's
  `AndroidManifest.xml` needed `android:usesCleartextTraffic="true"` (Android
  blocks plain `http://` by default for apps targeting SDK 28+, which
  silently dropped every beacon to a local test backend — this only matters
  for local testing; production uses HTTPS), and a stale-build caching issue
  that required `flutter clean` to resolve after an unrelated manifest edit.

**The Play install referrer is verified too**, which is the part `adb` and
`flutter run` can never show: those installs carry no referrer at all, because
no Play Store performed them. A production Flutter integration on this plugin
has since produced **34 Play-Store installs carrying a real referrer** —
`referrer_source=google`, meaning Play's own Install Referrer API answered
rather than any fallback — with the click id, campaign and source resolving
through, a click-to-install gap of one second, across vivo, Xiaomi and Samsung
handsets. Deterministic click → install works through this bridge.

Still unverified on Android:

- **Signed beacons.** Every install so far reports `signed: false`, because no
  build has passed `appSecret` yet. The `Signer` is shared with iOS and has a
  parity test against the backend, and iOS has now run it on a device — but the
  Android path has never signed in the wild. Worth one run before any customer
  turns on `require_signed_beacons`, since that switch starts *rejecting*
  unsigned beacons.
- **A real in-app purchase.** No store notification has reached a backend from
  a Flutter build on either platform. The wiring is one field on the purchase;
  see "Binding a purchase to the install" below.
- **The OEM-store referrer fallback** (Vivo/Huawei/Xiaomi/Samsung app stores,
  and the legacy `INSTALL_REFERRER` broadcast). Only matters for installs those
  stores performed — a Play install on such a handset goes through Google's API
  like any other, as the results above show.

## ✅ Verified end to end (iOS)

Built, installed and run from `example/` on a physical iPhone 12 mini
(iOS 16.7), against `RoasSensor` 0.1.7:

- Install, session-start, deep-link and event beacons all delivered through the
  Dart→Swift bridge and landed in the backend.
- **All 36 device fields** arrived and were individually checked — form factor,
  screen vs viewport, device class, network, battery, install dates, integrity.
- **IDFA bound under a real ATT grant**, on the install beacon itself.
- **Apple Search Ads token** read and resolved server-side to
  `utm_source=apple_search_ads`.
- **HMAC-signed beacons** accepted (`signed: true`), via
  `--dart-define=ROAS_APP_SECRET=…`.
- Deep links forwarded with their click id extracted server-side.
- The delivery `EventChannel` — the riskiest piece, since it crosses threads and
  clears a process-wide native callback on cancel — survived repeated hot
  restarts with the stream listening.

Two real bugs came out of that run, both now fixed: the SDK's ATT prompt never
appeared on a Flutter host (iOS shows it only while the app is `.active`, and
the SDK's fixed 0.6s wait was tuned for a native app calling `configure` from
`onAppear` — Flutter runs `initialize` from Dart `main()` before `runApp()`, so
the request landed mid-boot and was silently discarded), and `last_update_at`
never arrived from a real device because the `.app` bundle carries no creation
date on device while the Simulator hands one over happily.

## Install

In the Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  roas_flutter:
    git:
      url: https://github.com/harsh-vasundhara/roas-sensor-flutter.git
      ref: main
```

Then:

```bash
flutter pub get
```

For local development against a checked-out copy instead, a path dependency
also works:

```yaml
dependencies:
  roas_flutter:
    path: ../roas-sensor-flutter   # adjust to wherever you place this folder
```

### iOS-specific setup

**Set your deployment target to 14.0 first.** This bites every new Flutter app,
because Flutter's template ships the platform line commented out and CocoaPods
then defaults to iOS 13, while this plugin requires 14. In `ios/Podfile`:

```ruby
platform :ios, '14.0'   # uncomment this line — the template leaves it off
```

The error, if you skip it, names the plugin but not the fix:

```
[!] CocoaPods could not find compatible versions for pod "roas_flutter":
    ... they required a higher minimum deployment target.
```

Raise the **Runner target** to 14.0 as well (Xcode → Runner → General →
Minimum Deployments). That is a separate setting from the Podfile's, so fixing
only the Podfile clears the `pod install` failure and then fails again during
the build with the same complaint from the app target.

`RoasSensor` (the underlying native SDK) now has a real repository and tag, but
it is **not on the CocoaPods trunk** — and a podspec cannot name a git source
for its own dependency. So your app's `ios/Podfile` has to say where it comes
from (`pod install` fails with "Unable to find a specification for RoasSensor"
otherwise, which reads like a broken plugin and is really a missing source):

```ruby
pod 'RoasSensor', :git => 'https://github.com/rishabhrk2345/Roas-ios-SDK.git', :tag => '0.1.10'
```

`example/ios/Podfile` already carries that line — copy it from there. Pin a
**tag**, never a branch: the plugin and the native SDK share one version number
so a build can be traced to a release, and a branch would move the SDK under a
build that still reports a fixed `sdk_version`.

Developing against a local checkout instead:

```ruby
pod 'RoasSensor', :path => '../../sdk-ios'   # adjust to wherever you placed it
```

Also add to `Info.plist`, for the App Tracking Transparency prompt
`Roas.initialize()` presents by default on first launch:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>Used to measure which ads brought you here.</string>
```

## Usage

```dart
import 'package:roas_flutter/roas_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Roas.initialize(
    publicKey: 'YOUR-SITE-PUBLIC-KEY', // Site with platform=android, from the panel
    // baseUrl: 'http://10.0.2.2:8000', // only for local testing against an emulator
  );

  runApp(const MyApp());
}

// Later, anywhere:
await Roas.track(RoasEvent.addToCart, properties: {'sku': 'ABC', 'qty': 1});
await Roas.identify(email: 'buyer@example.com');
final vid = await Roas.visitorId();
```

Any event name not in `RoasEvent`'s constants still works — it's sent as a
custom event under that exact name, matching how the native sample app calls
`Roas.track(RoasEvent.CUSTOM, name = "boss_defeated")`:

```dart
await Roas.track('boss_defeated');
```

### Binding a purchase to the install (do this, or revenue is orphaned)

Attribution needs the purchase to carry an id resolvable back to the install.
The store gives you one field for it; put ours in it.

```dart
// iOS — StoreKit / in_app_purchase
final token = await Roas.appAccountToken();   // a UUID; null on Android

// Android — Play Billing / in_app_purchase
final accountId = await Roas.visitorId();     // the raw visitor id
```

`appAccountToken` is a UUID **derived from the visitor id**, not a separate
identifier — the backend reconstructs the vid from it. Two different shapes
because the two stores accept different things: Apple's `appAccountToken` is
typed as a UUID, Play's `obfuscatedAccountId` is a free string.

Skip it and the sale arrives with nothing tying it to an ad click. The revenue
still lands, the spend still counts, and ROAS reads *low* — the campaign looks
dead when it is working.

### iOS: the App Store purchase path, end to end

No RevenueCat, no shared secret, and nothing for your server to poll.

```
  app                     Apple                      ROASSensor
  ───                     ─────                      ──────────
  purchase with
  appAccountToken   ──▶   App Store Server
                          Notification v2      ──▶   POST /api/tracking/
                          (signedPayload JWS)         webhooks/appstore/<public_key>
                                                          │
                                                          ├─ verify Apple's ES256
                                                          │  cert chain (x5c)
                                                          ├─ appAccountToken → vid
                                                          └─ attribute to the install
                                                             and its ad click
```

**1. Set the token on the purchase.** With `in_app_purchase`, the iOS
implementation exposes `applicationUserName`; with raw StoreKit 2 it is
`Product.PurchaseOption.appAccountToken(_:)`. Either way the value is
`await Roas.appAccountToken()`.

**2. Tell ROASSensor your bundle id.** Setup → your app → the iOS property's
`bundle_id` must equal the app's real bundle identifier. The webhook checks the
`bundleId` inside Apple's signed payload against it — a valid JWS for someone
else's app is still authentic, so the bundle id is what scopes it to you.

**3. Point Apple at the webhook.** App Store Connect → your app → **App
Information → App Store Server Notifications**, set **Version 2**, and use:

```
https://<your-host>/api/tracking/webhooks/appstore/<your-site-public-key>
```

Set the **Sandbox URL** to the same endpoint. Sandbox purchases arrive with
`environment: "sandbox"` and are recorded as test revenue rather than counted
as money, so pointing both at one URL is safe and saves a second config.

**4. There is no secret to configure.** Authenticity is Apple's signature: the
payload is a JWS signed with a certificate chain that must terminate at Apple
Root CA G3. Nothing is shared, so nothing can leak.

#### What gets counted

| Apple `notificationType` | Recorded as |
|---|---|
| `SUBSCRIBED`, `DID_RENEW`, `ONE_TIME_CHARGE`, `OFFER_REDEEMED` | revenue |
| `REFUND` | a negative conversion mirroring the original |
| everything else (`EXPIRED`, `DID_CHANGE_RENEWAL_STATUS`, …) | ignored, answered `200` |

Ignored types still get a `2xx` on purpose — Apple retries a non-2xx for days,
and "I understood you and there is no money here" is not a failure.

**Each renewal needs its own transaction**, which Apple already provides:
subscription renewals arrive as separate notifications with their own
transaction ids, so they are counted individually rather than deduping away
against the first one.

#### Verifying it

The sample's **"Show appAccountToken"** button prints the value the purchase
must carry. Make a sandbox purchase, then check the conversion landed against
the same `vid` the install reported. If revenue arrives but shows as
UNATTRIBUTED, the token was not set on the purchase — that is the only thing
that link depends on.

### Verifying a purchase the instant it happens (plugin 0.1.9+)

The store's own notification remains the source of truth and stays so. What
it cannot be is *prompt* — Play's can take minutes — and until it lands the
buyer is standing in the app having just paid while the dashboard shows
nothing. `verifyPurchase` closes that gap without moving the trust boundary:
the app only **names** a receipt, the collector asks the store what it was
worth, and the later notification for the same sale dedupes against it.

```dart
// iOS — from your StoreKit transaction handling; the transaction's own id,
// not originalID (that names the subscription's first purchase).
await Roas.verifyPurchase(transactionId: transaction.id.toString());

// Android — once the purchase is PURCHASED.
await Roas.verifyPurchase(
  purchaseToken: purchase.purchaseToken,
  productId: purchase.productId,
  isSubscription: true,
);
```

One signature for both platforms; each native side reads only its own fields.
Fire-and-forget: the outcome arrives on the delivery stream under
`/api/tracking/mobile/purchase`. Needs the store credential saved on the app in
the panel (an Apple In-App Purchase key, or the Play service account); without
it the collector answers 422 and books nothing — the notification path is
unaffected. The sample's **"Verify purchase (fake receipt)"** button sends a
fake receipt so a 422 is the expected, passing outcome.

### iOS: ATT timing

The prompt fires ~0.6s after `initialize` by default — a cold-start system
alert, before the user has seen anything worth trusting the app with, which is
the classic way to depress opt-in. Every denial costs the IDFA. To ask at a
better moment:

```dart
await Roas.initialize(publicKey: key, requestTrackingAuthorization: false);
// ...after your own priming screen:
await Roas.requestTracking();
```

Deferring costs nothing: the install beacon goes out without an advertising id,
and on a grant the SDK binds the IDFA through `/identify`, minting the same
identity key the install beacon would have carried.

### iOS: SKAdNetwork conversion values

For a user who denied ATT — most of them — SKAN is the *only* channel that tells
the ad network the install converted. Call this on your key events:

```dart
await Roas.updateConversionValue(12, coarse: 'high');
```

`value` is 0–63 and its meaning is your site's SKAN schema, held server-side so
it can be retuned without an app release. **Send `coarse` too**: below Apple's
install-volume privacy threshold the fine value is withheld entirely and coarse
is all that survives the postback, so fine-only reporting goes dark on exactly
the small campaigns that most need measuring.

### Watching deliveries

```dart
Roas.onDeliveryResult.listen((r) => debugPrint('$r'));
```

Most apps don't need it. It exists because an app that silently delivers nothing
looks identical to one with no traffic, and lost beacons mean credit assigned to
the wrong touch or to none.

## Running the example app

`example/` is a fully scaffolded Flutter app for **both** platforms now, with
the path dependency, `android:usesCleartextTraffic="true"`, and the iOS
Podfile / ATT key already wired in.

```bash
cd example
flutter pub get
flutter run   # with an emulator, simulator or device selected
```

On iOS the first run also needs `pod install`, which `flutter run` does for
you. Three things are pre-solved in the checked-in `example/ios/` so you do not
hit them:

| Already handled | What it would have cost |
|---|---|
| `platform :ios, '14.0'` in the Podfile | `pod install` fails on a platform mismatch, and raising it in Xcode does not help — it is a separate setting |
| `IPHONEOS_DEPLOYMENT_TARGET = 14.0` in the project | the same complaint again, at build time instead |
| `NSUserTrackingUsageDescription` in Info.plist | iOS **terminates the app** when the ATT prompt fires without it |

The `pod 'RoasSensor', :git => …, :tag => '0.1.10'` line is in the Podfile too —
that one is not optional for any consuming app, so copy it into yours.

Same `publicKey`/`baseUrl` values as `sample/MainActivity.kt` in the native
repo — edit `example/lib/main.dart`'s `kPublicKey`/`kBaseUrl` constants if you
need different ones. Watch your Django backend the same way you did for the
native sample app — `POST /api/tracking/mobile/first-open|events|identify`
landing with `200`/`201` is the real confirmation, exactly as already done
once for this package (see "Verified end to end" above).

If you ever delete/regenerate `example/` from scratch, remember: `flutter
create` overwrites `AndroidManifest.xml` back to the default (no cleartext
flag) and `pubspec.yaml` (no path dependency) — both need re-adding, or local
HTTP testing will silently fail exactly the way it did during initial
verification.

## Does this give "proper, accurate" tracking data from a Flutter app?

**On Android: yes, proven.** The accuracy is identical to the native SDK's,
because it IS the native SDK underneath — install referrer reading, GAID
lookup, on-device hashing, and the persisted retry queue are all unchanged;
this bridge adds no new logic that could degrade accuracy. Confirmed on both
an emulator and a physical device (see "Verified end to end" above).

**On iOS: yes, proven.** Same reasoning and now the same evidence — the bridge
is a pass-through to the real `Roas.swift`, and a physical-device run confirmed
all 36 fields, the IDFA under an ATT grant, a resolved Apple Search Ads token
and signed beacons (see "Verified end to end (iOS)" above).

Worth keeping the reason that section exists, though: "it should behave like the
native SDK because it is a thin pass-through" was true of Android too, right up
until someone ran it and found two real bugs. iOS was no different — running it
turned up an ATT prompt that never fired on any Flutter host, and an install
timestamp that the Simulator reported and a real device did not. A pass-through
adds no *tracking* logic, but the host platform still gets a vote.

Other things that differ from a pure-native app on either platform:

- **Timing of `initialize()`**: it must still run as early as possible
  (ideally before `runApp()`), same as `Application.onCreate()` (Android) /
  `Roas.configure()` at app start (iOS) do natively. Calling it late in a
  deep widget tree risks missing the earliest events — including, on iOS,
  the ATT prompt firing late enough to miss the first-open IDFA window.
- **AAB/Play Console testing rules are unchanged**: the Android install
  referrer still only works on a real Play Store install (internal testing
  track), never `flutter run` straight to a device via USB — see
  `docs/play-console-testing-flutter.md`.
- **App Store review**: shipping the ATT prompt means the standard App Store
  Review Guidelines around tracking transparency apply, same as any native
  iOS app using IDFA.
