package com.margelo.nitro.counter

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip

@Keep
@DoNotStrip
class HybridCounter : HybridCounterSpec() {
  private var current: Long = 0L

  override fun increment() {
    current += 1L
  }

  override fun reset() {
    current = 0L
  }

  override fun value(): Long = current

  override fun add(delta: Long): Long {
    current += delta
    return current
  }
}
