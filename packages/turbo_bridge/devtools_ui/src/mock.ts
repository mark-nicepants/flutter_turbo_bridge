export {};

// Dev-only mock device. Loaded by `main.ts` when `import.meta.env.DEV`
// is true. Patches `window.fetch` and `window.EventSource` to serve
// canned data and stream plausible events on a timer so the UI can be
// developed without a Flutter app attached.

interface MockState {
  start: number;
  nextId: number;
  history: {
    requests: any[];
    network: any[];
    logs: any[];
    navigation: any[];
  };
  listeners: Map<string, Set<(data: any) => void>>;
}

const mock: MockState = {
  start: Date.now(),
  nextId: 1,
  history: { requests: [], network: [], logs: [], navigation: [] },
  listeners: new Map(),
};

function emit(type: string, payload: any) {
  const ev = {
    type,
    timestamp: new Date().toISOString(),
    payload,
  };
  const set = mock.listeners.get(type);
  if (set) for (const fn of set) fn(ev);
}

// ---------- Canned generators ----------

const ROUTES = ['/home', '/feed', '/cart', '/checkout', '/profile', '/settings'];
const LOG_CATS = ['lifecycle', 'auth', 'storage', 'render', 'analytics'];
const LOG_MESSAGES: Record<string, string[]> = {
  lifecycle: ['App started', 'App resumed', 'App paused'],
  auth: ['User signed in', 'Refreshed token', 'Session expired'],
  storage: ['Loaded shared prefs', 'Migrated DB to v3', 'Cache hit'],
  render: ['Slow image decode', 'Rebuilt 14 widgets', 'Frame skipped'],
  analytics: ['screen_view', 'click_purchase', 'scroll_depth_50'],
};
const URLS = [
  'https://api.example.com/feed',
  'https://api.example.com/users/me',
  'https://api.example.com/cart',
  'https://api.example.com/cart/add',
  'https://api.example.com/checkout/start',
  'https://cdn.example.com/static/banner.jpg',
  'https://api.example.com/products/42',
];

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)] as T;
}

function fakeRequest(): any {
  const method = pick(['GET', 'GET', 'GET', 'POST', 'PUT', 'DELETE']);
  const paths = ['/screenshot', '/tree', '/health', '/info', '/find', '/tap'];
  const path = pick(paths);
  const r = Math.random();
  const status = r < 0.85 ? 200 : r < 0.95 ? 404 : 500;
  return {
    id: mock.nextId++,
    timestamp: new Date().toISOString(),
    method,
    path,
    status,
    durationMs: Math.round(2 + Math.random() * 80),
    remoteAddress: '127.0.0.1',
  };
}

function fakeNetwork(): any {
  const url = pick(URLS);
  const method = pick(['GET', 'GET', 'GET', 'POST', 'PUT']);
  const r = Math.random();
  const status = r < 0.8 ? 200 : r < 0.9 ? 201 : r < 0.95 ? 401 : 500;
  const duration = Math.round(30 + Math.random() * 280);
  return {
    id: mock.nextId++,
    timestamp: new Date().toISOString(),
    method,
    url,
    status,
    durationMs: duration,
    requestHeaders: {
      authorization: 'Bearer eyJraWQiOiJtb2NrIn0.***',
      'content-type': 'application/json',
      'user-agent': 'demo/1.0 (mock device)',
    },
    requestBody: method === 'GET'
      ? null
      : JSON.stringify({ payload: 'demo', ts: Date.now() }),
    responseHeaders: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      'x-request-id': `req_${mock.nextId}`,
    },
    responseBody: JSON.stringify({ ok: status < 400, status }, null, 0),
    responseBodySize: 24,
  };
}

function fakeLog(): any {
  const levels = ['debug', 'info', 'info', 'info', 'warn', 'error'];
  const level = pick(levels);
  const category = pick(LOG_CATS);
  const message = pick(LOG_MESSAGES[category] ?? ['something happened']);
  return {
    id: mock.nextId++,
    timestamp: new Date().toISOString(),
    level,
    message,
    category,
  };
}

function fakeNavigation(prevRoute: string | null): any {
  let route = pick(ROUTES);
  while (route === prevRoute && ROUTES.length > 1) route = pick(ROUTES);
  return {
    id: mock.nextId++,
    timestamp: new Date().toISOString(),
    route,
    from: prevRoute ?? undefined,
    action: 'push',
  };
}

// ---------- Seed history ----------

(function seed() {
  // Backfill ~10 seconds of activity so the timeline isn't empty.
  let prev: string | null = null;
  for (let i = 0; i < 12; i++) {
    const r = fakeRequest();
    mock.history.requests.push(r);
  }
  for (let i = 0; i < 8; i++) mock.history.network.push(fakeNetwork());
  for (let i = 0; i < 18; i++) mock.history.logs.push(fakeLog());
  for (let i = 0; i < 4; i++) {
    const n = fakeNavigation(prev);
    mock.history.navigation.push(n);
    prev = n.route;
  }
})();

// ---------- Patch fetch ----------

const realFetch = window.fetch.bind(window);

window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input.toString();
  // Only intercept the bridge's API paths.
  const apiMatch = url.match(/api\/(.+)$/);
  if (!apiMatch) return realFetch(input, init);
  const path = apiMatch[1].split('?')[0];

  const json = (body: any, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'content-type': 'application/json' },
    });

  switch (path) {
    case 'health':
      return json({ status: 'ok' });
    case 'info':
      return json({
        screenWidth: 390,
        screenHeight: 844,
        pixelRatio: 3,
        platform: 'mock',
        darkMode: true,
        bridgeVersion: 'dev-mock',
      });
    case 'devtools/requests':
      return json({ entries: mock.history.requests });
    case 'devtools/network':
      return json({ entries: mock.history.network });
    case 'devtools/logs':
      return json({ entries: mock.history.logs });
    case 'devtools/navigation':
      return json({ entries: mock.history.navigation });
  }
  if (path.startsWith('devtools/requests/')) {
    const id = parseInt(path.slice('devtools/requests/'.length), 10);
    const e = mock.history.requests.find((x) => x.id === id);
    return e ? json(e) : json({ error: 'not found' }, 404);
  }
  if (path.startsWith('devtools/network/')) {
    const id = parseInt(path.slice('devtools/network/'.length), 10);
    const e = mock.history.network.find((x) => x.id === id);
    return e ? json(e) : json({ error: 'not found' }, 404);
  }
  return realFetch(input, init);
};

// ---------- Patch EventSource ----------

class MockEventSource {
  readonly url: string;
  readonly readyState = 1;
  onerror: ((e: Event) => void) | null = null;
  onopen: ((e: Event) => void) | null = null;
  onmessage: ((e: MessageEvent) => void) | null = null;
  private subs = new Map<string, Set<(e: MessageEvent) => void>>();
  private timeoutId: number | undefined;

  constructor(url: string) {
    this.url = url;
    setTimeout(() => this.onopen?.(new Event('open')), 0);
    // Variable cadence: real devices emit bursts of activity (a frame
    // build kicks off many logs + a few network calls almost
    // simultaneously) interleaved with quieter stretches.
    this.scheduleNext();
  }

  private scheduleNext() {
    // 70% of the time we emit within 30-150ms (burst). 25% within
    // 150-600ms. 5% within 600-1500ms (idle stretch).
    const r = Math.random();
    let delay: number;
    if (r < 0.7) delay = 30 + Math.random() * 120;
    else if (r < 0.95) delay = 150 + Math.random() * 450;
    else delay = 600 + Math.random() * 900;
    this.timeoutId = window.setTimeout(() => {
      this.tick();
      this.scheduleNext();
    }, delay);
  }

  addEventListener(type: string, listener: (e: MessageEvent) => void) {
    if (!this.subs.has(type)) this.subs.set(type, new Set());
    this.subs.get(type)!.add(listener);
    if (!mock.listeners.has(type)) mock.listeners.set(type, new Set());
    mock.listeners.get(type)!.add((data) => {
      const me = new MessageEvent(type, { data: JSON.stringify(data) });
      listener(me);
    });
  }

  removeEventListener(type: string, listener: (e: MessageEvent) => void) {
    this.subs.get(type)?.delete(listener);
  }

  close() {
    if (this.timeoutId) window.clearTimeout(this.timeoutId);
  }

  private tick() {
    // Roll a category, weighted toward logs (most apps emit far more
    // logs than network calls or navigation).
    const r = Math.random();
    let prevRoute =
      mock.history.navigation[mock.history.navigation.length - 1]?.route ??
      null;
    // Occasional micro-burst: emit 2-5 events at once.
    const burstSize =
      Math.random() < 0.15 ? 2 + Math.floor(Math.random() * 4) : 1;
    for (let i = 0; i < burstSize; i++) {
      const k = Math.random();
      if (k < 0.55) {
        const lg = fakeLog();
        mock.history.logs.push(lg);
        emit('log', lg);
      } else if (k < 0.75) {
        const req = fakeRequest();
        mock.history.requests.push(req);
        emit('request', req);
      } else if (k < 0.95) {
        const n = fakeNetwork();
        mock.history.network.push(n);
        emit('network', n);
      } else {
        const nav = fakeNavigation(prevRoute);
        mock.history.navigation.push(nav);
        emit('navigation', nav);
        prevRoute = nav.route;
      }
    }
    void r;
  }
}

(window as any).EventSource = MockEventSource;

// eslint-disable-next-line no-console
console.info(
  '%c[turbo_bridge devtools]%c mock device attached',
  'color:#06b6d4;font-weight:600',
  'color:#a1a1aa',
);
