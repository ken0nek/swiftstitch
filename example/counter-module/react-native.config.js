/**
 * Tells RN's `use_native_modules!` autolinking that this package ships
 * native code on both platforms.
 *
 * - iOS: the Pod is auto-discovered from `NitroCounter.podspec` in the
 *   package root.
 * - Android: the Gradle module is auto-discovered from `android/build.gradle`,
 *   which in turn applies the nitrogen-generated autolinking gradle/cmake
 *   files under `nitrogen/generated/android/`.
 *
 * Consumers don't need to add Pod / settings.gradle entries themselves.
 */
module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: {},
    },
  },
};
