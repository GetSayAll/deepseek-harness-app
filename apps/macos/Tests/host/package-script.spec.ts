import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const PACKAGE_SCRIPT = new URL('../../scripts/package_app.sh', import.meta.url)

describe('macOS package build faces', () => {
  it('builds the Client face before deploying the runtime closure', () => {
    const script = readFileSync(PACKAGE_SCRIPT, 'utf8')
    const hostBuild = script.indexOf('pnpm "${PNPM_REPOSITORY_ARGS[@]}" run build:lib:host')
    const clientBuild = script.indexOf('pnpm "${PNPM_REPOSITORY_ARGS[@]}" run build:lib:client')
    const deploy = script.indexOf('pnpm --config.node-linker=hoisted --config.package-import-method=copy')

    expect(hostBuild).toBeGreaterThanOrEqual(0)
    expect(clientBuild).toBeGreaterThan(hostBuild)
    expect(clientBuild).toBeLessThan(deploy)
  })
})
