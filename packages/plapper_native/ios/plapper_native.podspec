Pod::Spec.new do |s|
  s.name             = 'plapper_native'
  s.version          = '1.0.0'
  s.summary          = 'plapper clap-detection core (iOS build).'
  s.description      = <<-DESC
Builds the shared plapper C++ DSP core + miniaudio capture for iOS.
Podspecs cannot reference files outside this folder, so Classes/ contains
forwarder files that relatively include ../../../../core sources.
                       DESC
  s.homepage         = 'https://github.com/AttackToaster/plapper'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AttackToaster' => '171244563+AttackToaster@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.library = 'c++'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
