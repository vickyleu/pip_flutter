#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'pip_flutter'
  s.version          = '0.0.5'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
#   s.source_files = 'Classes/**/*'
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.{h}'
  s.dependency 'Flutter'
  s.dependency 'Cache', '~> 6.0.0'
  s.dependency 'GCDWebServer', '~> 3.0'
  s.dependency 'Aspects', '~> 1.4.1'
  s.dependency 'HLSCachingReverseProxyServer', '~> 0.1.0'

  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '4' }
  s.frameworks=['GLKit','Foundation','AVFoundation','MediaPlayer', 'AVKit']
  #系统的Libraries


  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
end
