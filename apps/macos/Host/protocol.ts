/** Process-local NDJSON carrier used by the native macOS client. */

import { randomUUID } from 'node:crypto'
import type { ApiProxy, ClientResponse } from '@deepseek-ai/dsh-host-apiproxy'
import { RpcId, toFetchHandler } from '@deepseek-ai/dsh-host-apiproxy'

/** Native carrier protocol version. */
export const NATIVE_PROTOCOL_VERSION = 0

/** Capabilities implemented by this carrier version. */
export const NATIVE_CAPABILITIES = ['rpc.unary', 'rpc.respond', 'events.mux', 'events.host'] as const

/** Input frame accepted from the Swift client. */
export type NativeInputFrame =
  | { id: string; type: 'hello'; protocolVersion: number }
  | { id: string; type: 'request'; method: string; payload: unknown }
  | { id: string; type: 'respond'; rpcId: string; result: ClientResponse['result'] }
  | { id: string; type: 'shutdown' }

/** Output frame emitted to the Swift client. */
export type NativeOutputFrame =
  | {
    id: string
    type: 'hello'
    protocolVersion: number
    appVersion: string
    capabilities: readonly string[]
  }
  | { id: string; type: 'response'; value?: unknown; error?: { code: string; message: string } }
  | { type: 'event'; stream: 'mux' | 'host'; value: unknown }

/** Result of handling one native input frame. */
export interface NativeDispatchResult {
  response: NativeOutputFrame
  shutdown: boolean
}

/** Dependencies needed by the native frame dispatcher. */
export interface NativeDispatcherOptions {
  appVersion: string
  api: ApiProxy
}

/** Create the transport dispatcher over one booted Harness API gateway. */
export function createNativeDispatcher(options: NativeDispatcherOptions): (frame: NativeInputFrame) => Promise<NativeDispatchResult> {
  const carrier = toFetchHandler(options.api)
  return async (frame) => {
    switch (frame.type) {
      case 'hello':
        if (frame.protocolVersion !== NATIVE_PROTOCOL_VERSION) {
          return {
            response: {
              id: frame.id,
              type: 'response',
              error: {
                code: 'incompatible-version',
                message: `native protocol ${String(frame.protocolVersion)} is not supported; expected ${String(NATIVE_PROTOCOL_VERSION)}`,
              },
            },
            shutdown: false,
          }
        }
        return {
          response: {
            id: frame.id,
            type: 'hello',
            protocolVersion: NATIVE_PROTOCOL_VERSION,
            appVersion: options.appVersion,
            capabilities: NATIVE_CAPABILITIES,
          },
          shutdown: false,
        }
      case 'request': {
        const rpcId = randomUUID()
        const request = new Request(`http://native.dsh/api/${encodeURIComponent(frame.method)}`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            type: 'client-request',
            rpcId,
            method: frame.method,
            payload: frame.payload,
          }),
        })
        const response = await carrier.fetch(request)
        if (!response.ok) {
          return {
            response: {
              id: frame.id,
              type: 'response',
              error: { code: 'carrier-failure', message: await response.text() },
            },
            shutdown: false,
          }
        }
        return {
          response: { id: frame.id, type: 'response', value: await response.json() },
          shutdown: false,
        }
      }
      case 'respond':
        return {
          response: {
            id: frame.id,
            type: 'response',
            value: await options.api.respond({
              type: 'client-response',
              rpcId: RpcId(frame.rpcId),
              result: frame.result,
            }),
          },
          shutdown: false,
        }
      case 'shutdown':
        return {
          response: { id: frame.id, type: 'response', value: {} },
          shutdown: true,
        }
      default:
        frame satisfies never
        throw new Error('unhandled native input frame')
    }
  }
}

/** Parse and minimally validate one incoming NDJSON line. */
export function parseNativeInput(line: string): NativeInputFrame {
  const value: unknown = JSON.parse(line)
  if (value === null || typeof value !== 'object') throw new Error('frame must be an object')
  const frame = value as Record<string, unknown>
  if (typeof frame.id !== 'string' || typeof frame.type !== 'string') {
    throw new Error('frame must contain string id and type fields')
  }
  switch (frame.type) {
    case 'hello':
      if (typeof frame.protocolVersion !== 'number') throw new Error('hello.protocolVersion must be a number')
      return { id: frame.id, type: 'hello', protocolVersion: frame.protocolVersion }
    case 'request':
      if (typeof frame.method !== 'string') throw new Error('request.method must be a string')
      return { id: frame.id, type: 'request', method: frame.method, payload: frame.payload }
    case 'respond': {
      if (typeof frame.rpcId !== 'string') throw new Error('respond.rpcId must be a string')
      if (frame.result === null || typeof frame.result !== 'object') throw new Error('respond.result must be an object')
      const result = frame.result as Record<string, unknown>
      if (typeof result.ok !== 'boolean') throw new Error('respond.result.ok must be a boolean')
      if (!result.ok) {
        if (result.error === null || typeof result.error !== 'object') throw new Error('respond.result.error must be an object')
        const error = result.error as Record<string, unknown>
        if (typeof error.code !== 'string' || typeof error.message !== 'string'
          || error.details === null || typeof error.details !== 'object') {
          throw new Error('respond.result.error must contain code, message, and details')
        }
      }
      return { id: frame.id, type: 'respond', rpcId: frame.rpcId, result: frame.result as ClientResponse['result'] }
    }
    case 'shutdown':
      return { id: frame.id, type: 'shutdown' }
    default:
      throw new Error(`unsupported frame type ${JSON.stringify(frame.type)}`)
  }
}

/** Forward the standard Host streams through process event frames. */
export function startNativeEventStreams(
  api: ApiProxy,
  signal: AbortSignal,
  emit: (frame: NativeOutputFrame) => void,
): Promise<void>[] {
  const forward = async (
    stream: 'mux' | 'host',
    frames: AsyncIterable<{ rpcId: string; payload: unknown }>,
  ): Promise<void> => {
    for await (const frame of frames) {
      const payload = frame.payload as { type?: unknown }
      emit({
        type: 'event',
        stream,
        value: {
          type: 'server-request',
          rpcId: frame.rpcId,
          method: typeof payload.type === 'string' ? payload.type : 'stream/error',
          payload: frame.payload,
        },
      })
    }
  }
  return [
    forward('mux', api.events.mux({ rpcId: RpcId(randomUUID()), payload: {} }, signal)),
    forward('host', api.events.host({ rpcId: RpcId(randomUUID()), payload: {} }, signal)),
  ]
}
