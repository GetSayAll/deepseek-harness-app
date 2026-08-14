import { createHash } from 'node:crypto'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'

const helper = fileURLToPath(new URL('../../scripts/derive_sparkle_public_key.mjs', import.meta.url))
const seed = Buffer.from('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60', 'hex')
const expectedPublicKey = Buffer.from('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex')

function runHelper(contents: string | Buffer) {
  const root = mkdtempSync(join(tmpdir(), 'dsh-sparkle-public-key-'))
  try {
    const keyFile = join(root, 'private-key')
    writeFileSync(keyFile, contents, { mode: 0o600 })
    return spawnSync(process.execPath, [helper, keyFile], { encoding: 'utf8' })
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

describe('Sparkle public-key derivation', () => {
  it('derives the RFC 8032 public key from a 32-byte Sparkle seed', () => {
    const result = runHelper(`\n${seed.toString('base64')}\n`)
    expect(result.status).toBe(0)
    expect(result.stdout).toBe(`${expectedPublicKey.toString('base64')}\n`)
    expect(result.stderr).toBe('')
  })

  it('reads the public key from Sparkle legacy 96-byte key data', () => {
    const expandedPrivateKey = createHash('sha512').update(seed).digest()
    expandedPrivateKey[0] &= 248
    expandedPrivateKey[31] &= 63
    expandedPrivateKey[31] |= 64
    const result = runHelper(Buffer.concat([expandedPrivateKey, expectedPublicKey]).toString('base64'))
    expect(result.status).toBe(0)
    expect(result.stdout).toBe(`${expectedPublicKey.toString('base64')}\n`)
    expect(result.stderr).toBe('')
  })

  it('rejects non-canonical base64 without echoing private input', () => {
    const privateInput = 'not-a-private-key'
    const result = runHelper(privateInput)
    expect(result.status).not.toBe(0)
    expect(result.stdout).toBe('')
    expect(result.stderr).not.toContain(privateInput)
  })

  it('rejects decoded lengths other than the two Sparkle formats', () => {
    const result = runHelper(Buffer.alloc(64).toString('base64'))
    expect(result.status).not.toBe(0)
    expect(result.stdout).toBe('')
    expect(result.stderr).toContain('32 or 96 bytes')
  })
})
