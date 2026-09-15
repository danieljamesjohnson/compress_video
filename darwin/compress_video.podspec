#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint compress_video.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'compress_video'
  s.version          = '0.1.0'
  s.summary          = 'Compress phone-recorded video, with typed media info and thumbnails.'
  s.description      = <<-DESC
A Flutter plugin that compresses a video, reads its media info and makes rotation-correct
thumbnails, on Android, iOS and macOS. Drop-in successor to video_compress.
                       DESC
  s.homepage         = 'https://github.com/danieljamesjohnson/compress_video'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dan Johnson' => 'danthebeliever@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'compress_video/Sources/compress_video/**/*.swift'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'compress_video_privacy' => ['compress_video/Sources/compress_video/PrivacyInfo.xcprivacy']}
end
