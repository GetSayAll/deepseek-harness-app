#!/usr/bin/env node

import { createPrivateKey, createPublicKey } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { TextDecoder } from 'node:util'

const PKCS8_ED25519_SEED_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex')
const SPKI_ED25519_PUBLIC_PREFIX = Buffer.from('302a300506032b6570032100', 'hex')

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

if (process.argv.length !== 3) fail('usage: derive_sparkle_public_key.mjs <private-key-file>')

let encodedSecret
try {
  encodedSecret = new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(process.argv[2])).trim()
} catch {
  fail('unable to read Sparkle private key file')
}

const secret = Buffer.from(encodedSecret, 'base64')
if (secret.toString('base64') !== encodedSecret) fail('Sparkle private key file is not canonical base64')

let publicKey
if (secret.length === 32) {
  const privateKeyDer = Buffer.concat([PKCS8_ED25519_SEED_PREFIX, secret])
  try {
    const privateKey = createPrivateKey({ key: privateKeyDer, format: 'der', type: 'pkcs8' })
    const publicKeyDer = createPublicKey(privateKey).export({ format: 'der', type: 'spki' })
    if (!publicKeyDer.subarray(0, SPKI_ED25519_PUBLIC_PREFIX.length).equals(SPKI_ED25519_PUBLIC_PREFIX)
      || publicKeyDer.length !== SPKI_ED25519_PUBLIC_PREFIX.length + 32) {
      fail('unable to derive Sparkle public key')
    }
    publicKey = Buffer.from(publicKeyDer.subarray(SPKI_ED25519_PUBLIC_PREFIX.length))
  } catch {
    fail('unable to derive Sparkle public key')
  } finally {
    privateKeyDer.fill(0)
  }
} else if (secret.length === 96) {
  publicKey = Buffer.from(secret.subarray(64))
} else {
  fail('Sparkle private key must decode to 32 or 96 bytes')
}

secret.fill(0)
process.stdout.write(`${publicKey.toString('base64')}\n`)
