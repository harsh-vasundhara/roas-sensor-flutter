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

What's *not* yet verified on Android: a real Play Store install (the
referrer was empty in every test so far, as expected for `adb`/`flutter run`
installs — see `docs/play-console-testing-flutter.md` in the main repo for
why that's expected, not a bug, and the runbook for closing that gap), and a
a real in-app purchase — no store notification has reached this backend from a
Flutter build yet, on either platform. The wiring for it is one field on the
purchase; see "Binding a purchase to the install" below.

## ⚠️ iOS: the native SDK is proven, this bridge is not

Two different claims, and it matters which is which.

**The native SDK underneath is verified.** `RoasSensor` 0.1.6 builds clean,
passes 54 tests, and was confirmed field-by-field on a physical iPhone 12 mini
(iOS 16.7): install beacon delivered, IDFA bound under an ATT grant, a real
Apple Search Ads token resolved to `utm_source=apple_search_ads`, engagement
folded onto the install touchpoint, and no false integrity signals. Every one
of the ~25 device parameters landed.

**This Dart→Swift bridge has still never been compiled.** It mirrors the
Android plugin method-for-method and every call in it was checked against
`Roas.swift`'s real public signatures, but no Swift compiler has seen it. What
changed is that it is now *runnable*: `example/ios/` exists (with a Podfile and
the ATT key already wired), so proving it is one `flutter run` on a Mac rather
than an afternoon of scaffolding.

The riskiest part is the delivery `EventChannel`, not the method channel: it
crosses threads (`Transport` delivers off-main, a `FlutterEventSink` must be
invoked on main) and clears a process-wide native callback on cancel. Hot
restart the example a few times with the stream listening — that is the case
the cleanup exists for.

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
pod 'RoasSensor', :git => 'https://github.com/rishabhrk2345/Roas-ios-SDK.git', :tag => '0.1.6'
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

The `pod 'RoasSensor', :git => …, :tag => '0.1.6'` line is in the Podfile too —
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

**On iOS: should be, by the same reasoning, but unproven.** The bridge is a
pass-through to the same real `Roas.swift`/`RoasEvent.swift` — no logic is
duplicated — but "should behave like the native SDK because it's a thin
pass-through" was also true of Android before anyone actually ran it, and
that's exactly when the two real bugs (cleartext traffic, stale build cache)
turned up. Treat iOS as unverified until someone with a Mac runs it and
confirms beacons land in the backend, the same way Android was proven.

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
