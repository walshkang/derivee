podfile = File.read('./ios/Podfile')
old_block = <<~BLOCK
    installer.aggregate_targets.each do |target|
      target.xcconfigs.each do |variant, xcconfig|
        xcconfig_path = target.client_root + target.xcconfig_relative_path(variant)
        IO.write(xcconfig_path, IO.read(xcconfig_path) + "\\nSWIFT_INCLUDE_PATHS = $(inherited) \\\"${PODS_ROOT}/RCT-Folly\\\" \\\"${PODS_ROOT}/Headers/Public/React-jsi\\\" \\\"${PODS_ROOT}/Headers/Public/React-callinvoker\\\" \\\"${PODS_ROOT}/Headers/Public/React-cxxreact\\\" \\\"${PODS_ROOT}/Headers/Public/ReactCommon\\\"\\nOTHER_SWIFT_FLAGS = $(inherited) -Xcc -DFOLLY_NO_CONFIG -Xcc -DFOLLY_MOBILE=1 -Xcc -DFOLLY_USE_LIBCPP=1 -Xcc -DFOLLY_CFG_NO_COROUTINES=1 -Xcc -DFOLLY_HAVE_CLOCK_GETTIME=1\\n")
      end
    end
BLOCK

new_block = <<~BLOCK
    installer.aggregate_targets.each do |target|
      target.xcconfigs.each do |variant, xcconfig|
        xcconfig_path = target.client_root + target.xcconfig_relative_path(variant)
        content = IO.read(xcconfig_path)
        
        if content.match?(/^OTHER_SWIFT_FLAGS =/)
          content.sub!(/^OTHER_SWIFT_FLAGS = (.*)$/, 'OTHER_SWIFT_FLAGS = \1 -Xcc -DFOLLY_NO_CONFIG -Xcc -DFOLLY_MOBILE=1 -Xcc -DFOLLY_USE_LIBCPP=1 -Xcc -DFOLLY_CFG_NO_COROUTINES=1 -Xcc -DFOLLY_HAVE_CLOCK_GETTIME=1')
        else
          content += "\\nOTHER_SWIFT_FLAGS = $(inherited) -Xcc -DFOLLY_NO_CONFIG -Xcc -DFOLLY_MOBILE=1 -Xcc -DFOLLY_USE_LIBCPP=1 -Xcc -DFOLLY_CFG_NO_COROUTINES=1 -Xcc -DFOLLY_HAVE_CLOCK_GETTIME=1"
        end

        if content.match?(/^SWIFT_INCLUDE_PATHS =/)
          content.sub!(/^SWIFT_INCLUDE_PATHS = (.*)$/, 'SWIFT_INCLUDE_PATHS = \1 "${PODS_ROOT}/RCT-Folly" "${PODS_ROOT}/Headers/Public/React-jsi" "${PODS_ROOT}/Headers/Public/React-callinvoker" "${PODS_ROOT}/Headers/Public/React-cxxreact" "${PODS_ROOT}/Headers/Public/ReactCommon"')
        else
          content += "\\nSWIFT_INCLUDE_PATHS = $(inherited) \\\"${PODS_ROOT}/RCT-Folly\\\" \\\"${PODS_ROOT}/Headers/Public/React-jsi\\\" \\\"${PODS_ROOT}/Headers/Public/React-callinvoker\\\" \\\"${PODS_ROOT}/Headers/Public/React-cxxreact\\\" \\\"${PODS_ROOT}/Headers/Public/ReactCommon\\\""
        end
        
        IO.write(xcconfig_path, content)
      end
    end
BLOCK

if podfile.include?(old_block.strip)
  podfile = podfile.sub(old_block.strip, new_block.strip)
  File.write('./ios/Podfile', podfile)
  puts "Patched!"
else
  puts "Could not find old block!"
end
