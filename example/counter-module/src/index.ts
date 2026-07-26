import { NitroModules } from 'react-native-nitro-modules';
import type { Counter as CounterSpec } from '../specs/Counter.nitro';

export type Counter = CounterSpec;

/**
 * Returns a fresh `Counter` HybridObject backed by `HybridCounter.swift`
 * via the nitrogen-generated bridge.
 */
export function createCounter(): Counter {
  return NitroModules.createHybridObject<Counter>('Counter');
}
