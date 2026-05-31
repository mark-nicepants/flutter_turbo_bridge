import type { TimelineEvent, EventStatus } from './types';

const HEADERS = { 'x-turbo-devtools': '1' };

export async function api<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch('api/' + path, {
    ...init,
    headers: { ...HEADERS, ...(init.headers ?? {}) },
  });
  if (!res.ok) {
    throw new Error(`${path} → ${res.status}`);
  }
  return (await res.json()) as T;
}

/** Convert backend `requests` entry (turbo_bridge JSON API call from
 *  MCP / DevTools / external clients) into a TimelineEvent on the
 *  dedicated `bridge` row. */
export function fromRequest(e: any): TimelineEvent {
  const status: EventStatus =
    e.status >= 500 ? 'failed' : e.status >= 400 ? 'warn' : 'ok';
  return {
    id: `bridge:${e.id}`,
    category: 'bridge',
    timestamp: new Date(e.timestamp).getTime(),
    durationMs: e.durationMs,
    label: `${e.method} ${e.path}`,
    status,
    raw: e,
  };
}

/** Convert backend `network` entry (app-side HTTP) into a TimelineEvent. */
export function fromNetwork(e: any): TimelineEvent {
  const status: EventStatus =
    e.error || (e.status && e.status >= 500)
      ? 'failed'
      : e.status >= 400
        ? 'warn'
        : 'ok';
  return {
    id: `network:app:${e.id}`,
    category: 'network',
    timestamp: new Date(e.timestamp).getTime(),
    durationMs: e.durationMs,
    label: `${e.method} ${e.url}`,
    status,
    raw: e,
  };
}

/** Convert backend `log` entry into either a `log` or `error` TimelineEvent. */
export function fromLog(e: any): TimelineEvent {
  const isError = e.level === 'error';
  const status: EventStatus =
    e.level === 'error' ? 'failed' : e.level === 'warn' ? 'warn' : 'ok';
  return {
    id: `log:${e.id}`,
    category: isError ? 'error' : 'log',
    timestamp: new Date(e.timestamp).getTime(),
    label: e.category ? `${e.category}: ${e.message}` : e.message,
    status,
    raw: e,
  };
}

export function fromNavigation(e: any): TimelineEvent {
  return {
    id: `nav:${e.id}`,
    category: 'navigation',
    timestamp: new Date(e.timestamp).getTime(),
    label: e.route,
    status: 'ok',
    raw: e,
  };
}
