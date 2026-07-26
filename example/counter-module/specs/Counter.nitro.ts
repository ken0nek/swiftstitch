import type { HybridObject, Int64 } from 'react-native-nitro-modules'

export interface Counter extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  increment(): void
  reset(): void
  value(): Int64
  add(delta: Int64): Int64
}
