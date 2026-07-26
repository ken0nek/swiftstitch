const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// `react-native-swiftstitch-counter` is installed via `file:../counter-module`,
// so its sources live outside the rn-app project root. Tell Metro to watch
// that path and follow the symlinks bun installed.
const counterModulePath = path.resolve(__dirname, '../counter-module');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  watchFolders: [counterModulePath],
  resolver: {
    unstable_enableSymlinks: true,
    // Counter-module's source files import `react-native-nitro-modules`
    // (a peerDep). With symlinks on, Metro resolves relative to the real
    // path under counter-module/, which has no node_modules — so point it
    // back at the rn-app's installation here.
    nodeModulesPaths: [path.resolve(__dirname, 'node_modules')],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
