/**
 * @format
 */

import { AppRegistry } from 'react-native';
import { createSimpleMath } from 'react-native-swiftstitch-math';
import App from './App';
import { name as appName } from './app.json';

// The parity bar's assertion, emitted here rather than from a component so it
// cannot be suppressed by anything else in the app. `App` builds a `Counter`
// during render; were the parity line logged from an effect, a counter-module
// failure would throw before that effect ran and the parity bar would score a
// counter-module bug as a Swift-on-Android bug. Module scope runs once, before
// `App` is ever rendered, and depends on math-module alone.
const math = createSimpleMath();
const sum = math.add(2, 3); // 5
const product = math.multiply(4, 5); // 20
console.log(`SwiftStitchParity: sum=${sum} product=${product}`);

AppRegistry.registerComponent(appName, () => App);
