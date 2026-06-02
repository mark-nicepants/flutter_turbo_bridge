# Plan: in-flight network requests on the DevTools timeline

> **Status: implemented.** `NetworkLog.start()` now emits an in-flight
> entry immediately and `complete()`/`fail()` mutate + re-emit it; the
> DevTools UI renders in-flight calls as a growing, pulsing yellow bar.
> The notes below are kept as the design record.

Originally a network call only appeared on the timeline once the response
(or error) arrived — the start timestamp + duration were recorded only at
`record()` time. This meant a 30s API call was invisible for 30s.

Goal: surface the request the moment it starts, render it as a growing
bar that ends when the response lands.

## Today

```
NetworkLog.record(...)         // single shot at completion
  → emit DevToolsEvent('network', summaryJson)
  → ring buffer entry
```

`NetworkLog.start(...)` / `InFlightNetworkCall` already exist and are
used by the dio + http_interceptor adapters, but `start()` buffers the
request fields in the handle and emits nothing — the entry only appears
when `.complete()` / `.fail()` triggers `record()`.

## Target

Two emissions per call:

1. **start** — when `NetworkLog.start()` is called.
   - Allocates the id immediately, emits a `network` SSE event with
     `status: undefined`, `durationMs: undefined`, `inFlight: true`.
   - Adds an entry to the ring buffer right away. Subsequent fetches of
     `/devtools/network` see in-flight calls in `entries`.

2. **end** — when `.complete()` / `.fail()` runs.
   - Mutates the existing entry (same id) with status / response body /
     duration / error.
   - Emits a `network` SSE event with the final fields and
     `inFlight: false`.

The frontend upserts by id (already does today via
`upsert(fromNetwork(e))`), so the second event replaces the first.

## Data model changes (`network_log.dart`)

`NetworkCall` gains:
- `bool inFlight` — true between start and complete/fail.
- `DateTime? endedAt` — set on complete/fail.
- Keep `durationMs` but allow it to be missing while in flight.

`NetworkLog.start()` becomes the canonical entry path:
- Allocates `id = _nextId++`, creates a mutable `NetworkCall` with
  `inFlight: true`, pushes onto the ring buffer, emits
  `DevToolsEvent('network', entry.toSummaryJson())`.
- Returns `InFlightNetworkCall` holding the entry id (not a copy of
  request fields).

`InFlightNetworkCall.complete()` / `.fail()`:
- Look up the entry in the log by id and mutate it (status, body,
  headers, endedAt, durationMs, inFlight=false).
- Re-emit `DevToolsEvent('network', entry.toSummaryJson())`.

`NetworkLog.record()` stays as a convenience for non-interceptor call
sites — it internally calls `start()` then immediately resolves.

### Mutating ring-buffer entries vs. immutable

Today `NetworkCall` is immutable. Switching its body fields to mutable
means snapshots taken via `byId()` see live updates — desired here.
Alternative: keep `NetworkCall` immutable and store
`Map<int, _MutableInFlight>` next to the buffer, then replace the
entry in place. Pick mutable; simpler and the field is already
internal.

## Wire protocol (SSE `event: network`)

```jsonc
// in flight
{ "id": 42, "method": "GET", "url": "...", "timestamp": "...",
  "inFlight": true }

// completed (same id, replaces the prior row in the UI)
{ "id": 42, "method": "GET", "url": "...", "timestamp": "...",
  "status": 200, "durationMs": 412, "inFlight": false }
```

`toSummaryJson()` adds `'inFlight'`. Old clients ignore it.

`toDetailJson()` (the `/devtools/network/:id` endpoint) returns whatever
fields exist; the UI already tolerates missing headers/body.

## Frontend rendering (`devtools_ui/src/main.ts`)

`TimelineEvent.durationMs` is what drives the duration bar. While
in-flight we want the bar to extend to "now", not 0 width.

In `fromNetwork(p)` (the SSE→TimelineEvent mapper):
- If `p.inFlight`, set `durationMs = Date.now() - timestamp` and a flag
  `ev.inFlight = true`.
- If `!p.inFlight`, set `durationMs = p.durationMs` as today.

Track painting (the bar inside the network row) needs the in-flight
case to look "live":
- Render a striped or pulsing bar (Tailwind: `animate-pulse` + a fixed
  zinc color), no status dot yet.
- Width = `(Date.now() - timestamp) / windowDuration * trackWidth`,
  clipped to the right edge.

The smooth follow ticker already re-renders ~30fps when follow is on,
so live bars grow naturally. When follow is off but in-flight events
exist, add a separate low-frequency tick (every 500ms) so the bar
still grows; or accept that it freezes until follow resumes.

## Edge cases

- **Cancel.** `InFlightNetworkCall.cancel()` should remove the entry
  from the buffer and emit a "removed" event (or emit a final
  `inFlight: false, error: 'cancelled'` so the UI keeps it visible —
  TBD; lean toward keeping for observability).
- **Eviction while in flight.** Ring-buffer cap (300) can evict an
  in-flight entry. `complete()` then has nothing to mutate. Detect by
  id-lookup miss and either:
  - Drop silently (simplest), or
  - Re-add the call so the result still shows up.
  Pick "drop silently" — explicit, predictable, and the ring cap is
  already a "we will lose old data" contract.
- **Long-lived streaming responses** (SSE clients themselves, large
  downloads). `complete()` might never come. Add a configurable
  `maxInFlightDuration` (e.g. 60s) after which we mark
  `error: 'timeout'` on the entry, just so the row stops growing.
- **Clock skew.** Frontend uses its own `Date.now()` for the growing
  bar. Backend `timestamp` is wall-clock UTC. Acceptable drift; the
  bar reaches its final width when the server-reported `durationMs`
  arrives.

## Tests

New unit tests in `test/devtools_test.dart`:
1. `start()` immediately pushes a buffer entry with `inFlight: true`.
2. `complete()` mutates the same entry, sets `inFlight: false` +
   `durationMs`.
3. `fail()` mutates the entry with `error` + `inFlight: false`.
4. Two emissions on the bus: one from `start`, one from `complete`.
5. Eviction: when the ring buffer cap evicts an in-flight entry, a
   later `complete()` is a no-op (no exception).

## Migration

- `NetworkLog.record()` keeps its current signature; semantics become
  "start + complete in one call". Existing call sites unchanged.
- `InFlightNetworkCall` instance API unchanged. Existing dio +
  http_interceptor adapters work without changes (they already use
  `start` → `complete`/`fail`).

## Out of scope

- Server-side streaming progress (`bytes received / total`) — would
  need a third emission type.
- WebSocket frame timeline — separate feature.
