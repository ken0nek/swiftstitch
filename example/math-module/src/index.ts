import { NitroModules } from 'react-native-nitro-modules';
import type { SimpleMath as SimpleMathSpec } from '../specs/SimpleMath.nitro';

export type SimpleMath = SimpleMathSpec;

/**
 * Returns a `SimpleMath` HybridObject backed by `HybridSimpleMath.swift`,
 * the one file that is both this spec's source and, via Embedded Swift, the
 * Android implementation.
 */
export function createSimpleMath(): SimpleMath {
  return NitroModules.createHybridObject<SimpleMath>('SimpleMath');
}
