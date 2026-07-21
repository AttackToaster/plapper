Pod::Spec.new do |s|
  s.name             = 'plounter_native'
  s.version          = '0.1.0'
  s.summary          = 'plounter clap-detection core (macOS build).'
  s.description      = <<-DESC
Builds the shared plounter C++ DSP core + miniaudio capture for macOS.
Podspecs cannot reference files outside this folder, so Classes/ contains
forwarder files that relatively include ../../../../core sources.
                       DESC
  s.homepage         = 'https://github.com/SeamusMullan/plounter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SeamusMullan' => 'seamusmullan2023@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.library = 'c++'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
  }
  s.swift_version = '5.0'
end
