/**
 * Tells RN's autolinking that this package ships native code on Android only.
 *
 * - Android: the Gradle module is auto-discovered from `android/build.gradle`,
 *   which in turn applies the nitrogen-generated autolinking gradle/cmake
 *   files under `nitrogen/generated/android/`.
 * - iOS: deliberately absent. `nitro.json` still declares `ios.language:
 *   "swift"`, so the iOS sources still generate from the same Swift file, but
 *   this module ships no podspec and is not built for iOS in this phase.
 *   `example/counter-module` is the worked Swift-on-iOS reference.
 */
module.exports = {
  dependency: {
    platforms: {
      android: {},
    },
  },
};
