Pod::Spec.new do |s|
  s.name             = 'roas_flutter'
  # Tracks pubspec.yaml. It had drifted (0.1.2 against a 0.1.3 pubspec), which
  # makes `pod install` resolve a version that names a different plugin release
  # than the Dart side claims to be.
  s.version          = '0.1.4'
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

  # RoasSensor (sdk-ios) isn't published to a resolvable CocoaPods source yet
  # (see sdk-ios/RoasSensor.podspec's own note — same pre-publish phase the
  # Android bridge's roas-android dependency was in before Maven Central).
  # Declaring the dependency here is still correct — it's what the plugin
  # actually needs to compile — but until RoasSensor has a real git tag or
  # trunk listing, whoever consumes this plugin must add an explicit source
  # for it in their OWN app's ios/Podfile, e.g.:
  #   pod 'RoasSensor', :path => '../../../sdk-ios'      # local dev
  #   pod 'RoasSensor', :git => 'https://github.com/harsh-vasundhara/roas-sensor-ios.git', :tag => '0.1.0'
  # Without one of those, `pod install` fails with "Unable to find a
  # specification for RoasSensor" — that's expected until publishing lands,
  # not a bug in this podspec.
  s.dependency 'RoasSensor'

  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
