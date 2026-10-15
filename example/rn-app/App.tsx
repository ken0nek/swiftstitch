/**
 * SwiftStitch RN example. It exercises two HybridObjects, each defined by a
 * single Swift file and wired through nitrogen:
 *
 * - `Counter` (counter-module) is Swift on iOS, Kotlin on Android.
 * - `SimpleMath` (math-module) is Swift on Android, compiled to Embedded
 *   Swift. The same file does not yet compile for iOS. It is exercised from
 *   `index.js`, not from here, so that a counter-module failure in this
 *   component cannot stop the parity bar's logcat line from being emitted.
 */

import { useMemo, useState } from 'react';
import {
  Pressable,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';
import { type Int64 } from 'react-native-nitro-modules';
import { createCounter } from 'react-native-swiftstitch-counter';

function App() {
  const isDarkMode = useColorScheme() === 'dark';
  const counter = useMemo(() => createCounter(), []);
  const [value, setValue] = useState<Int64>(() => counter.value());

  const refresh = () => setValue(counter.value());

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <View style={styles.body}>
        <Text style={styles.title}>SwiftStitch · Counter</Text>
        <Text style={styles.value}>{String(value)}</Text>
        <View style={styles.row}>
          <Button label="−1" onPress={() => { counter.add(-1n as Int64); refresh(); }} />
          <Button label="+1" onPress={() => { counter.increment(); refresh(); }} />
        </View>
        <Button label="reset" onPress={() => { counter.reset(); refresh(); }} />
        <Text style={styles.hint}>
          Counter is a Swift HybridObject. The `+1` button calls{' '}
          <Text style={styles.code}>HybridCounter.increment()</Text> in
          swift/HybridCounter.swift via the nitrogen-generated bridge.
        </Text>
      </View>
    </SafeAreaView>
  );
}

function Button({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable
      style={({ pressed }) => [styles.btn, pressed && styles.btnPressed]}
      onPress={onPress}
    >
      <Text style={styles.btnLabel}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 16 },
  title: { fontSize: 18, fontWeight: '600', opacity: 0.7 },
  value: { fontSize: 72, fontVariant: ['tabular-nums'] },
  row: { flexDirection: 'row', gap: 12 },
  btn: {
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    backgroundColor: '#2c7be5',
    minWidth: 80,
    alignItems: 'center',
  },
  btnPressed: { opacity: 0.6 },
  btnLabel: { color: 'white', fontSize: 16, fontWeight: '600' },
  hint: { textAlign: 'center', opacity: 0.6, fontSize: 13, marginTop: 24 },
  code: { fontFamily: 'Menlo' },
});

export default App;
