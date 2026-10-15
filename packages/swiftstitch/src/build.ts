import { join, resolve } from 'node:path'

// Three steps, run from the module directory (the one holding nitro.json).
// See the alongside-pass plan, contract C6, for the exact command shapes.

export interface Step {
  name: 'input-emit' | 'nitrogen' | 'alongside'
  command: string
  args: string[]
}

export interface PlanContext {
  hasSwiftSources: boolean
  moduleDir: string
  inputBin?: string // default: 'nitrogen-swift-input'
  embeddedBin?: string // default: 'nitrogen-swift-embedded'
}

export interface BuildOptions extends PlanContext {}

const DEFAULT_INPUT_BIN = 'nitrogen-swift-input'
const DEFAULT_EMBEDDED_BIN = 'nitrogen-swift-embedded'

/**
 * Pure: no I/O. `hasSwiftSources` is a caller-computed input rather than
 * something this function detects itself, so it is trivial to unit test.
 *
 * The path handed to `alongside` is always absolute. Every step is spawned
 * with `cwd: moduleDir`, so a *relative* `moduleDir` baked into an argument
 * would be applied twice, once by the cwd and once by the child resolving the
 * argument against it, and `alongside` would fail on a doubled path that
 * names a nitro.json nobody wrote. `--out-dir` and `--ir-dir` are left off
 * entirely: `alongside` derives both from nitro.json's own directory.
 */
export function planSteps(ctx: PlanContext): Step[] {
  const moduleDir = resolve(ctx.moduleDir)
  const steps: Step[] = []

  // Absence means the author hand-writes their `.nitro.ts`. Skip,
  // do not error.
  if (ctx.hasSwiftSources) {
    steps.push({
      name: 'input-emit',
      command: ctx.inputBin ?? DEFAULT_INPUT_BIN,
      args: ['emit'],
    })
  }

  // `bunx`, not `bun`, because `bun nitrogen` would run a package.json
  // script and `bunx` runs the installed binary.
  steps.push({ name: 'nitrogen', command: 'bunx', args: ['nitrogen'] })

  // Always runs. It is a no-op with no `swiftstitch` block in nitro.json,
  // which is exactly the iOS-only author's case.
  steps.push({
    name: 'alongside',
    command: ctx.embeddedBin ?? DEFAULT_EMBEDDED_BIN,
    args: ['alongside', '--nitro-json', join(moduleDir, 'nitro.json')],
  })

  return steps
}

interface NitroJSONSwiftStitch {
  swiftstitch?: {
    userSwiftDir?: string
  }
}

/**
 * Mirrors `swift/HybridObjectExtractor`'s convention: a flat (non-recursive)
 * `Hybrid*.swift` glob. A missing or unreadable directory is not an error
 * here. It means there is nothing to emit from, same as
 * `nitrogen-swift-input`'s own `discoverDefaultInputs`.
 */
async function hasHybridSwiftFiles(swiftDir: string): Promise<boolean> {
  try {
    const glob = new Bun.Glob('Hybrid*.swift')
    for await (const _match of glob.scan({ cwd: swiftDir })) {
      return true
    }
    return false
  } catch {
    return false
  }
}

/**
 * Reads `swiftstitch.userSwiftDir` from `<moduleDir>/nitro.json` and checks
 * whether it contains any `Hybrid*.swift` files. No `swiftstitch` block at
 * all (or no nitro.json yet) means `false`, not an error. The `alongside`
 * step is what raises real misconfiguration, since it always runs and is
 * the authority on the block's shape.
 */
async function detectSwiftSources(moduleDir: string): Promise<boolean> {
  const nitroJSONPath = join(moduleDir, 'nitro.json')
  const nitroJSONFile = Bun.file(nitroJSONPath)
  if (!(await nitroJSONFile.exists())) return false

  let nitroJSON: NitroJSONSwiftStitch
  try {
    nitroJSON = await nitroJSONFile.json()
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err)
    throw new Error(`swiftstitch: ${nitroJSONPath} is not valid JSON: ${reason}`)
  }

  const userSwiftDir = nitroJSON.swiftstitch?.userSwiftDir
  if (!userSwiftDir) return false

  return hasHybridSwiftFiles(join(moduleDir, userSwiftDir))
}

/**
 * Resolves a step's binary to an absolute path, or throws a message naming
 * it. Only `input-emit` and `alongside` go through here. Neither
 * `nitrogen-swift-input` nor `nitrogen-swift-embedded` is published for
 * v0.2, so a bare-name miss is expected until a caller passes
 * `--input-bin`/`--embedded-bin` (or builds and installs them on PATH).
 * `bunx` (the `nitrogen` step) is not resolved this way, because it ships with bun.
 */
function resolveBinary(name: string, moduleDir: string): string {
  const resolved = Bun.which(name, { cwd: moduleDir })
  if (!resolved) {
    throw new Error(
      `swiftstitch: could not find \`${name}\` on PATH. Neither ` +
        '`nitrogen-swift-input` nor `nitrogen-swift-embedded` is published yet ' +
        '(v0.2). Build it from source (`swift build -c release` in its ' +
        'package) and pass the path via --input-bin/--embedded-bin, or put it ' +
        'on PATH.'
    )
  }
  return resolved
}

/**
 * Computes `hasSwiftSources`, plans the steps, and runs each in `moduleDir`
 * in order: `input-emit` if planned, then `nitrogen`, then `alongside`. It fails
 * fast on the first non-zero exit and prints that command's stderr.
 */
export async function runBuild(opts: BuildOptions): Promise<void> {
  // Resolved once, up front: `moduleDir` is used both as the spawn cwd and to
  // build the `alongside` path arguments, and a relative value applied in both
  // roles would compound. See `planSteps`.
  const moduleDir = resolve(opts.moduleDir)
  const hasSwiftSources = await detectSwiftSources(moduleDir)
  const steps = planSteps({ ...opts, moduleDir, hasSwiftSources })

  for (const step of steps) {
    const command = step.name === 'nitrogen' ? step.command : resolveBinary(step.command, moduleDir)

    const proc = Bun.spawn([command, ...step.args], {
      cwd: moduleDir,
      stdin: 'inherit',
      stdout: 'inherit',
      stderr: 'pipe',
    })

    const [exitCode, stderr] = await Promise.all([proc.exited, proc.stderr.text()])

    if (exitCode !== 0) {
      if (stderr) process.stderr.write(stderr)
      throw new Error(`swiftstitch build: \`${step.name}\` (${command}) exited ${exitCode}`)
    }
  }
}
