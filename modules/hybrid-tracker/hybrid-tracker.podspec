require 'json'

package = JSON.parse(File.read(File.join(__dir__, '../../package.json')))

Pod::Spec.new do |s|
  s.name           = 'hybrid-tracker'
  s.version        = package['version']
  s.summary        = 'Hybrid tracker local module'
  s.description    = 'Native background location tracking with H3 and SQLite'
  s.author         = 'derivee'
  s.homepage       = 'https://github.com/derivee'
  s.platforms      = { :ios => '13.4' }
  s.source         = { :git => '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.dependency 'React-Core'
  s.dependency 'NitroModules'
  
  # Include the H3 C source files so CocoaPods compiles them
  s.source_files = 'h3/src/**/*.c', 'h3/src/**/*.h', 'ios/**/*.{swift,h,m,mm,cpp,hpp}', 'cpp/**/*.{h,hpp,cpp}'
  s.public_header_files = 'cpp/**/*.hpp'
  s.private_header_files = 'h3/src/**/*.h'

  # Tell CocoaPods this module uses a custom module map for the C library
  s.preserve_paths = 'h3/**/*'

  # Compiler Directives for C++17 (required for Nitrogen)
  s.compiler_flags = '-std=c++20'

  # Ensure Swift can find the H3 headers and enable C++ Interop
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'SWIFT_OBJC_INTEROP_MODE' => 'objcxx',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'SWIFT_INCLUDE_PATHS' => '"$(PODS_TARGET_SRCROOT)/h3" "$(PODS_TARGET_SRCROOT)/h3/src/**"',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/h3/src/**" "$(PODS_ROOT)/Headers/Public/**" "$(PODS_ROOT)/RCT-Folly" "$(PODS_ROOT)/glog/src" "$(PODS_ROOT)/boost" "$(PODS_ROOT)/DoubleConversion" "$(PODS_ROOT)/fmt/include"',
    'USE_HEADERMAP' => 'NO',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) FOLLY_NO_CONFIG=1 FOLLY_CFG_NO_COROUTINES=1 FOLLY_MOBILE=1 FOLLY_USE_LIBCPP=1'
  }
end
