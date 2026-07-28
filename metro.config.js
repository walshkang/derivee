const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

config.resolver.assetExts.push('sqlite', 'db');

config.resolver.blockList = [
  /transit-web\/.*/,
  /observer\/.*/,
];

module.exports = config;
