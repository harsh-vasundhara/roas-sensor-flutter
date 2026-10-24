Pod::Spec.new do |s|
  s.name             = 'roas_flutter'
  # Tracks pubspec.yaml. It had drifted (0.1.2 against a 0.1.3 pubspec), which
  # makes `pod install` resolve a version that names a different plugin release
  # than the Dart side claims to be.
  s.version          = '0.1.10'
  s.summary          = 'Flutter bridge for the ROASSensor iOS tracking SDK.'
  s.description      = <<-DESC
    Thin Flutter bridge to the native RoasSensor iOS SDK (install attribution,
    funnel events, identity). Every call passes straight through to the
    native SDK — the same on-device hashing, ATT/IDFA/ASA/SKAdNetwork
    handling, and persisted retry queue a pure-Swift app gets. No tracking
    logic is reimplemented here.
  DESC
  s.homepage         = 'https://github.com/harsh-vasundhara/roas-sensor-flutter'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Vasundhara Infotech LLP. All rights reserved.' }
  s.author           = { 'ROASSensor' => 'support@roassensor.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # RoasSensor now has a real home and a real tag:
  #   https://github.com/rishabhrk2345/Roas-ios-SDK  (tag 0.1.15)
  # It is NOT on the CocoaPods trunk, though, and a podspec cannot name a git
  # source for its own dependency. So the consuming APP still has to say where
  # it comes from, in its own ios/Podfile:
  #
  #   pod 'RoasSensor', :git => 'https://github.com/rishabhrk2345/Roas-ios-SDK.git', :tag => '0.1.15'
  #
  # Without that line `pod install` fails with "Unable to find a specification
  # for RoasSensor", which reads like a broken plugin and is really a missing
  # source. `example/ios/Podfile` carries the line, ready to copy.
  #
  # Version-pinned rather than bare. The plugin and the native SDK share one
  # version number precisely so a build can be traced to a release, and an
  # unconstrained dependency would let a future incompatible RoasSensor resolve
  # silently against this bridge — the failure landing at runtime as missing
  # methods rather than at resolve time as a version conflict.
  #
  # 0.1.15 is the floor as of plugin 0.1.10. Below it, a Dart Map holding a
  # NaN (or any value JSONSerialization refuses) reached track() and crashed
  # the host app with an exception Swift cannot catch, and the default
  # collector was api.roassensor.com, which has no DNS. An app whose Podfile
  # still names an older tag now fails at `pod install` with a version
  # conflict rather than shipping that crash. (0.1.10 added the
  # PrivacyInfo.xcprivacy App Store Connect requires; 0.1.9 the
  # verifyPurchase(transactionId:) RoasFlutterPlugin.swift calls.)
  s.dependency 'RoasSensor', '~> 0.1.15'

  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
