const { withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

const FOLLY_PATCH_START = '# @generated begin RCT-Folly-post-install-patch';
const FOLLY_PATCH_END = '# @generated end RCT-Folly-post-install-patch';

const RUBY_PATCH = `${FOLLY_PATCH_START}
    # Patch xcconfig files manually because CocoaPods overwrites things
    Dir.glob('Pods/Target Support Files/**/*.xcconfig').each do |file|
      xc = File.read(file)
      paths = '"\${PODS_ROOT}/Headers/Public/React-jsinspector" "\${PODS_ROOT}/Headers/Public/React-jsi" "\${PODS_ROOT}/Headers/Public/React-callinvoker" "\${PODS_ROOT}/Headers/Public/ReactCommon" "\${PODS_ROOT}/boost" "\${PODS_ROOT}/DoubleConversion" "\${PODS_ROOT}/fmt/include"'

      # 1. Swift Flags Injection
      if xc.match?(/^OTHER_SWIFT_FLAGS =/)
        xc.sub!(/^OTHER_SWIFT_FLAGS = (.*)$/, 'OTHER_SWIFT_FLAGS = \\1 -cxx-interoperability-mode=default')
      else
        xc += "\\nOTHER_SWIFT_FLAGS = $(inherited) -cxx-interoperability-mode=default\\n"
      end

      # 2. Header Search Paths Injection (only for RNFlashList and React-Core)
      if file.include?('RNFlashList') || file.include?('React-Core')
        if xc.match?(/^HEADER_SEARCH_PATHS =/)
          unless xc.include?('Headers/Public/React-jsinspector')
            xc.sub!(/^HEADER_SEARCH_PATHS = (.*)$/, "HEADER_SEARCH_PATHS = \\1 \#{paths}")
          end
        else
          xc += "\\nHEADER_SEARCH_PATHS = $(inherited) \#{paths}\\n"
        end
      end

      # 3. Folly Macros Injection
      folly_flags = " -DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -DFOLLY_CFG_NO_COROUTINES=1 -DFOLLY_HAVE_CLOCK_GETTIME=1 -DFOLLY_HAVE_PTHREAD=1"
      if xc.match?(/^OTHER_CPLUSPLUSFLAGS =/)
        xc.sub!(/^OTHER_CPLUSPLUSFLAGS = (.*)$/, "OTHER_CPLUSPLUSFLAGS = \\1 \#{folly_flags}")
      else
        xc += "\\nOTHER_CPLUSPLUSFLAGS = $(inherited) \#{folly_flags}\\n"
      end

      File.write(file, xc)
    end

    # Fix 1: Strip iOS-incompatible headers from RCT-Folly umbrella
    folly_umbrella = File.join(
      installer.sandbox.root,
      'Target Support Files', 'RCT-Folly', 'RCT-Folly-umbrella.h'
    )
    if File.exist?(folly_umbrella)
      original = File.read(folly_umbrella)
      patched = original.lines.reject { |line|
        line.include?('-inl.h') ||
        line.include?('CompressionContextPoolSingletons') ||
        line.include?('AtomicSharedPtr-detail')
      }.join
      if original != patched
        removed = original.lines.count - patched.lines.count
        File.write(folly_umbrella, patched)
        Pod::UI.puts "Patched RCT-Folly-umbrella.h: removed \#{removed} incompatible headers".yellow
      end
    end

    # Fix 2: Create stub folly-config.h
    folly_config_dir = File.join(installer.sandbox.root, 'RCT-Folly', 'folly')
    folly_config_path = File.join(folly_config_dir, 'folly-config.h')
    unless File.exist?(folly_config_path)
      FileUtils.mkdir_p(folly_config_dir)
      File.write(folly_config_path, <<~STUB)
        // Auto-generated stub for mobile builds (FOLLY_NO_CONFIG is defined).
        // See: ios/Podfile post_install
        #pragma once
      STUB
      Pod::UI.puts "Created stub folly-config.h for RCT-Folly".yellow
    end

    # Resource bundle code signing fix
    installer.target_installation_results.pod_target_installation_results
      .each do |pod_name, target_installation_result|
      target_installation_result.resource_bundle_targets.each do |resource_bundle_target|
        resource_bundle_target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        end
      end
    end
${FOLLY_PATCH_END}`;

function applyFollyPodfilePatch(podfileContent) {
  if (podfileContent.includes(FOLLY_PATCH_START)) {
    const regex = new RegExp(`${FOLLY_PATCH_START}[\\s\\S]*?${FOLLY_PATCH_END}`, 'm');
    return podfileContent.replace(regex, RUBY_PATCH);
  }

  if (podfileContent.includes('post_install do |installer|')) {
    return podfileContent.replace(
      'post_install do |installer|',
      `post_install do |installer|\n${RUBY_PATCH}`
    );
  }

  return `${podfileContent}\n\npost_install do |installer|\n${RUBY_PATCH}\nend\n`;
}

function withFollyPodfile(config) {
  return withDangerousMod(config, [
    'ios',
    async (config) => {
      const podfilePath = path.join(config.modRequest.platformProjectRoot, 'Podfile');
      if (fs.existsSync(podfilePath)) {
        const podfileContent = await fs.promises.readFile(podfilePath, 'utf8');
        const patchedContent = applyFollyPodfilePatch(podfileContent);
        await fs.promises.writeFile(podfilePath, patchedContent, 'utf8');
      }
      return config;
    },
  ]);
}

module.exports = withFollyPodfile;
