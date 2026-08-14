import { describe, expect, it, vi } from 'vitest'
import type { ApiProxy } from '@deepseek-ai/dsh-host-apiproxy'
import { RpcId } from '@deepseek-ai/dsh-host-apiproxy'
import { SessionId } from '@deepseek-ai/dsh-session'
import { createNativeDispatcher, parseNativeInput, startNativeEventStreams } from '../../Host/protocol.ts'

function apiWithDescription(): ApiProxy {
  return {
    host: {
      describe: vi.fn(async request => ({
        rpcId: request.rpcId,
        result: {
          ok: true,
          value: { version: '0.1.0', cwd: '/tmp', attachedSessions: 0, canOpenPath: true },
        },
      })),
    },
    credentials: {
      describe: vi.fn(async request => ({
        rpcId: request.rpcId,
        result: {
          ok: true,
          value: { credentials: { DEEPSEEK_API_KEY: { configured: false, writable: true } } },
        },
      })),
      set: vi.fn(async request => ({ rpcId: request.rpcId, result: { ok: true, value: {} } })),
      unset: vi.fn(async request => ({ rpcId: request.rpcId, result: { ok: true, value: {} } })),
    },
    respond: vi.fn(async () => ({ accepted: true })),
  } as unknown as ApiProxy
}

describe('native sidecar protocol', () => {
  it('negotiates version zero', async () => {
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api: apiWithDescription() })
    const result = await dispatch(parseNativeInput('{"id":"h","type":"hello","protocolVersion":0}'))

    expect(result).toEqual({
      response: {
        id: 'h', type: 'hello', protocolVersion: 0, appVersion: '0.1.0',
        capabilities: ['rpc.unary', 'rpc.respond', 'events.mux', 'events.host'],
      },
      shutdown: false,
    })
  })

  it('rejects an incompatible client version', async () => {
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api: apiWithDescription() })
    const result = await dispatch({ id: 'h', type: 'hello', protocolVersion: 1 })

    expect(result.response).toMatchObject({
      id: 'h', type: 'response', error: { code: 'incompatible-version' },
    })
  })

  it('carries host.describe through the standard API envelope', async () => {
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api: apiWithDescription() })
    const result = await dispatch({ id: 'r', type: 'request', method: 'host.describe', payload: {} })

    expect(result.response).toMatchObject({
      id: 'r',
      type: 'response',
      value: {
        type: 'server-response',
        result: { ok: true, value: { cwd: '/tmp', canOpenPath: true } },
      },
    })
  })

  it('acknowledges shutdown', async () => {
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api: apiWithDescription() })
    const result = await dispatch({ id: 's', type: 'shutdown' })

    expect(result.shutdown).toBe(true)
  })

  it('carries credential status without returning a value', async () => {
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api: apiWithDescription() })
    const result = await dispatch({
      id: 'c', type: 'request', method: 'credentials.describe',
      payload: { refs: ['DEEPSEEK_API_KEY'] },
    })

    expect(result.response).toMatchObject({
      id: 'c',
      value: {
        result: {
          ok: true,
          value: { credentials: { DEEPSEEK_API_KEY: { configured: false, writable: true } } },
        },
      },
    })
    expect(JSON.stringify(result.response)).not.toContain('sk-')
  })

  it('carries a credential value only toward credentials.set', async () => {
    const api = apiWithDescription()
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api })
    await dispatch({
      id: 'c', type: 'request', method: 'credentials.set',
      payload: { ref: 'DEEPSEEK_API_KEY', value: 'test-secret' },
    })

    expect(api.credentials.set).toHaveBeenCalledWith(expect.objectContaining({
      payload: { ref: 'DEEPSEEK_API_KEY', value: 'test-secret' },
    }))
  })

  it('echoes a client response rpc id through ApiProxy.respond', async () => {
    const api = apiWithDescription()
    const dispatch = createNativeDispatcher({ appVersion: '0.1.0', api })
    const result = await dispatch(parseNativeInput(JSON.stringify({
      id: 'a', type: 'respond', rpcId: 'pending-1',
      result: { ok: true, value: { outcome: 'allowed-once' } },
    })))

    expect(api.respond).toHaveBeenCalledWith({
      type: 'client-response', rpcId: 'pending-1',
      result: { ok: true, value: { outcome: 'allowed-once' } },
    })
    expect(result.response).toEqual({ id: 'a', type: 'response', value: { accepted: true } })
  })

  it('forwards standard event frames without translating their payload', async () => {
    const abort = new AbortController()
    const api = apiWithDescription()
    const sessionId = SessionId('s')
    api.events = {
      mux: async function* () {
        yield { rpcId: RpcId('mux-1'), payload: { type: 'session/subscribed', sessionId, lastSeq: -1 } }
      },
      host: async function* () {
        yield { rpcId: RpcId('host-1'), payload: { type: 'host/session-status', sessionId, running: true } }
      },
    }
    const emitted: unknown[] = []

    await Promise.all(startNativeEventStreams(api, abort.signal, frame => emitted.push(frame)))

    expect(emitted).toEqual([
      {
        type: 'event', stream: 'mux', value: {
          type: 'server-request', rpcId: 'mux-1', method: 'session/subscribed',
          payload: { type: 'session/subscribed', sessionId: 's', lastSeq: -1 },
        },
      },
      {
        type: 'event', stream: 'host', value: {
          type: 'server-request', rpcId: 'host-1', method: 'host/session-status',
          payload: { type: 'host/session-status', sessionId: 's', running: true },
        },
      },
    ])
  })
})
