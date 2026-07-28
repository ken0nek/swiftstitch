#!/usr/bin/env bun
import { runBuild } from './build'

const usage =
  'usage: swiftstitch build [--module-dir <dir>] [--input-bin <path>] [--embedded-bin <path>]'

async function main(argv: string[]): Promise<void> {
  const [command, ...rest] = argv
  if (command !== 'build') {
    console.error(usage)
    process.exit(1)
  }

  let moduleDir = process.cwd()
  let inputBin: string | undefined
  let embeddedBin: string | undefined

  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i]
    switch (arg) {
      case '--module-dir':
        moduleDir = rest[++i]
        break
      case '--input-bin':
        inputBin = rest[++i]
        break
      case '--embedded-bin':
        embeddedBin = rest[++i]
        break
      default:
        console.error(`swiftstitch: unknown argument \`${arg}\`\n${usage}`)
        process.exit(1)
    }
  }

  // `hasSwiftSources` is ignored — `runBuild` recomputes it from
  // `moduleDir`'s nitro.json. It's only present here to satisfy
  // `BuildOptions`, which is `PlanContext` verbatim.
  await runBuild({ hasSwiftSources: false, moduleDir, inputBin, embeddedBin })
}

if (import.meta.main) {
  main(process.argv.slice(2)).catch(err => {
    console.error(err instanceof Error ? err.message : String(err))
    process.exit(1)
  })
}
