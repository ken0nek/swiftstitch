import type { HybridObject } from 'react-native-nitro-modules'

export interface SimpleMath extends HybridObject<{ ios: 'swift'; android: 'c++' }> {
  add(a: number, b: number): number
  multiply(a: number, b: number): number
}
