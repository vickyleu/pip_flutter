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
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.{h}'
  s.dependency 'Flutter'
  # s.dependency 'YYCache', '~> 1.0.4'
  s.dependency 'Cache', '~> 6.0.0'
  s.dependency 'PINCache', '~> 3.0.3'
  s.dependency 'GCDWebServer', '~> 3.0'
  s.dependency 'HLSCachingReverseProxyServer', '~> 0.1.0'

  s.frameworks=['GLKit','Foundation','AVFoundation','MediaPlayer', 'AVKit']
  #系统的Libraries
  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES',
                            'SWIFT_VERSION' => '5',
                            'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64'
                          }
end
