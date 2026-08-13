#!/usr/bin/env node
/** Boot the real Harness host and expose its API gateway over stdin/stdout NDJSON. */

import { createInterface } from 'node:readline'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { loadLayeredEnv } from '@deepseek-ai/dsh-app-boot'
import { runProfile } from '@deepseek-ai/dsh/profile-boot'
import {
  createNativeDispatcher, parseNativeInput, startNativeEventStreams, type NativeOutputFrame,
} from './protocol.ts'

const overlay = fileURLToPath(new URL('./native.overlay.yml', import.meta.url))
const manifest = JSON.parse(
  readFileSync(fileURLToPath(new URL('../package.json', import.meta.url)), 'utf8'),
) as { version: string }

const writeFrame = (frame: NativeOutputFrame): void => {
  process.stdout.write(`${JSON.stringify(frame)}\n`)
}

// stdout is the protocol channel. Route ordinary diagnostics away from it.
console.log = (...values: unknown[]) => { console.error(...values) }
console.info = (...values: unknown[]) => { console.error(...values) }

const booted = await runProfile({
  environment: loadLayeredEnv('dsh-macos'),
  profile: process.env.DSH_MACOS_PROFILE ?? 'web',
  patchFiles: [overlay],
  args: [],
})
const dispatch = createNativeDispatcher({ appVersion: manifest.version, api: booted.ctx.apiProxy })
const streamAbort = new AbortController()
const streamTasks = startNativeEventStreams(booted.ctx.apiProxy, streamAbort.signal, writeFrame)
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })

let stopping = false
for await (const line of lines) {
  if (line.trim() === '') continue
  let id = 'invalid-frame'
  try {
    const frame = parseNativeInput(line)
    id = frame.id
    const result = await dispatch(frame)
    writeFrame(result.response)
    if (!result.shutdown) continue
    stopping = true
    lines.close()
    streamAbort.abort()
    await booted.shutdown.shutdown(0)
    await Promise.allSettled(streamTasks)
    break
  } catch (error) {
    writeFrame({
      id,
      type: 'response',
      error: { code: 'invalid-frame', message: error instanceof Error ? error.message : String(error) },
    })
  }
}

if (!stopping) {
  streamAbort.abort()
  await booted.shutdown.shutdown(0)
  await Promise.allSettled(streamTasks)
}
