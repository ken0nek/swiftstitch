const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Both example modules are installed via `file:../<name>`, so their sources
// live outside the rn-app project root. Metro only resolves what it watches,
// so every such module must be listed here. A module wired into package.json
// but missing from this list fails to bundle with "could not be found within
// the project", even though node_modules/<name> exists and its symlinks are
// intact.
const localModulePaths = [
  path.resolve(__dirname, '../counter-module'),
  path.resolve(__dirname, '../math-module'),
];

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  watchFolders: localModulePaths,
  resolver: {
    unstable_enableSymlinks: true,
    // The modules' source files import `react-native-nitro-modules`
    // (a peerDep). With symlinks on, Metro resolves relative to the real
    // path under each module dir, which has no node_modules, so point it
    // back at the rn-app's installation here.
    nodeModulesPaths: [path.resolve(__dirname, 'node_modules')],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
