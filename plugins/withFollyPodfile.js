const { withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

const rubyScript = `
  # --- 1. Dynamic Header Injection (The Doom Loop Fix) ---
  installer.pods_project.targets.each do |target|
    if target.name.start_with?('React') || target.name == 'RCT-Folly' || target.name == 'hermes-engine'
      target.build_configurations.each do |config|
        config.build_settings['HEADER_SEARCH_PATHS'] ||= ['$(inherited)']
        config.build_settings['HEADER_SEARCH_PATHS'] << '"$(PODS_ROOT)/Headers/Public/**"'
      end
    end
  end

  # --- 2. RCT-Folly Umbrella & C++17 Fixes ---
  installer.pods_project.targets.each do |target|
    if target.name == 'RCT-Folly'
      # Force C++17 and disable HeaderMap
      target.build_configurations.each do |config|
        config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
        config.build_settings['USE_HEADERMAP'] = 'NO'
      end

      # Strip broken umbrella header files
      folly_umbrella = File.join(installer.sandbox.root, 'Target Support Files', 'RCT-Folly', 'RCT-Folly-umbrella.h')
      if File.exist?(folly_umbrella)
        content = File.read(folly_umbrella)
        # The true 96-header strip:
        content.gsub!(/#import ".*-inl\.h"\n/, '')
        content.gsub!(/#import ".*CompressionContextPoolSingletons\.h"\n/, '')
        content.gsub!(/#import ".*AtomicSharedPtr-detail\.h"\n/, '')
        File.write(folly_umbrella, content)
      end

      # Create stub folly-config.h
      folly_config_dir = File.join(installer.sandbox.root, 'RCT-Folly', 'folly')
      folly_config_path = File.join(folly_config_dir, 'folly-config.h')
      unless File.exist?(folly_config_path)
        FileUtils.mkdir_p(folly_config_dir)
        File.write(folly_config_path, "#pragma once\n")
      end
    end
  end
`;

module.exports = function withFollyPodfile(config) {
  return withDangerousMod(config, [
    'ios',
    async (cfg) => {
      const podfilePath = path.join(cfg.modRequest.platformProjectRoot, 'Podfile');
      let podfile = fs.readFileSync(podfilePath, 'utf8');

      // Inject safely inside Expo's existing post_install block
      if (!podfile.includes('Dynamic Header Injection')) {
        const postInstallMatch = /post_install do \|installer\|/g;
        podfile = podfile.replace(postInstallMatch, "post_install do |installer|\n" + rubyScript);
        fs.writeFileSync(podfilePath, podfile);
      }

      return cfg;
    },
  ]);
};