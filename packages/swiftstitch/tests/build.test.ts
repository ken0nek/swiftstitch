import { test, expect } from 'bun:test'
import { isAbsolute, resolve } from 'node:path'
import { planSteps } from '../src/build'

test('skips input emit when there is no userSwiftDir', () => {
  const steps = planSteps({ hasSwiftSources: false, moduleDir: '/m' })
  expect(steps.map(s => s.name)).toEqual(['nitrogen', 'alongside'])
})

test('runs all three when Swift sources are present', () => {
  const steps = planSteps({ hasSwiftSources: true, moduleDir: '/m' })
  expect(steps.map(s => s.name)).toEqual(['input-emit', 'nitrogen', 'alongside'])
})

test('alongside always runs — it self-no-ops without a swiftstitch block', () => {
  for (const hasSwiftSources of [true, false]) {
    expect(planSteps({ hasSwiftSources, moduleDir: '/m' }).some(s => s.name === 'alongside')).toBe(true)
  }
})

// Regression: a relative moduleDir used to be applied twice — once as the
// spawn cwd, once by `alongside` resolving the relative argument against that
// cwd — so `alongside` failed on a doubled path naming no real nitro.json.
test('alongside paths are absolute even when moduleDir is relative', () => {
  const steps = planSteps({ hasSwiftSources: true, moduleDir: 'example/math-module' })
  const alongside = steps.find(s => s.name === 'alongside')!

  const valueOf = (flag: string) => alongside.args[alongside.args.indexOf(flag) + 1]
  const nitroJSON = valueOf('--nitro-json')

  expect(isAbsolute(nitroJSON)).toBe(true)
  expect(nitroJSON).toEqual(resolve('example/math-module', 'nitro.json'))
})

// `alongside` defaults its output to `<nitro.json dir>/swiftstitch/generated`.
// Passing a path here would only be a second place for it to drift.
test('alongside is not handed an output directory', () => {
  const steps = planSteps({ hasSwiftSources: true, moduleDir: '/m' })
  const alongside = steps.find(s => s.name === 'alongside')!
  expect(alongside.args).toEqual(['alongside', '--nitro-json', '/m/nitro.json'])
})
