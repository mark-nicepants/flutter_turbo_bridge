# AGENTS.md — `devtools_ui/`

> Local guide for AI agents working on the DevTools web UI. See the
> repo-root `AGENTS.md` and `packages/turbo_bridge/AGENTS.md` for
> upstream rules.

## What this is

The TypeScript source for the DevTools UI shipped with
`turbo_bridge`. Built with **Vite + TypeScript + Tailwind v4** and
bundled into a **single self-contained `index.html`** via
`vite-plugin-singlefile`. The output is written into the parent Dart
package at `../lib/src/devtools/web/index.html` and shipped as a
Flutter asset — consumers don't run npm.

## Layout

```
devtools_ui/
├── index.html          # Vite entry — tiny shell that loads /src/main.ts
├── package.json
├── tsconfig.json
├── vite.config.ts      # Output goes to ../lib/src/devtools/web/
└── src/
    ├── main.ts         # Boot + state + per-section updaters
    ├── api.ts          # fetch wrapper + payload → TimelineEvent mappers
    ├── types.ts        # EventCategory + TimelineEvent + CategoryDef
    ├── styles.css      # Tailwind v4 entry (@import "tailwindcss")
    ├── mock.ts         # Dev-mode fake device (only loaded when DEV)
    └── vite-env.d.ts   # /// <reference types="vite/client" />
```

## Build / dev

```bash
# First time:
npm install

# Develop with Vite HMR + the fake "mock device":
npm run dev               # → http://127.0.0.1:5173

# Typecheck only (CI-grade strictness, noUnusedLocals on):
npm run typecheck

# Production build → ../lib/src/devtools/web/index.html
npm run build
```

From the repo root, the equivalent of `npm run build` is
`melos run build:devtools`.

**Node version**: 20.19+ or 22.12+ (Vite 7 requirement). If `npm run
build` complains about Node, use the homebrew node binary explicitly:
```bash
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run build
```

## Conventions

### Single-file output

`vite-plugin-singlefile` inlines all JS + CSS into one `index.html`.
There is intentionally no `/assets/foo.js` to serve. Don't add new
runtime asset references (`<link rel="icon" href="…">`, `import x from
'./foo.svg'`) without confirming the plugin can inline them — most
imports work, but external `<link rel="stylesheet">` to non-bundled
files will not.

### Incremental DOM updates

`main.ts` is built around a single `update()` function that mutates
existing DOM nodes via caches stashed on a module-level `ui` object.
**Do not** introduce a "render everything fresh" path — it kills
scroll position, text selection, focus, and drag state.

When you add a new visual element:
1. Build the persistent shell in `mount(root)` once.
2. Stash the node reference on the `ui` struct.
3. Mutate inline styles / classes / textContent in the relevant
   `update*()` function. Don't `replaceChildren()` on a parent unless
   absolutely necessary (axis labels are fine; row pills are not).
4. For repeated items (pills, list rows, minimap marks) use a
   `Map<string, HTMLElement>` cache keyed by event id, and only
   create / destroy elements when the underlying set changes.

### Minimal-update rule (be lazy in `update*()`)

**Default to doing nothing.** Every `update*()` function runs on every
state change — including ones that have nothing to do with that
section. Before you mutate anything, ask "did the input I render from
actually change?" and skip the work if not. The cost of
over-rendering isn't just CPU — it destroys interactive UI state
that depends on DOM identity.

Things that break when a parent is rebuilt mid-interaction:

- a **native `<select>`** with its dropdown open (it closes)
- text **selection** that crosses the rebuilt subtree (it clears)
- the **caret** position inside an `<input>` or `<textarea>`
- **focus** (moves to `<body>`)
- in-flight **CSS transitions** (snap to the end state)
- the user's current **scroll position** within the rebuilt subtree

Concrete patterns that work:

- **Lazy / once-only build** for popups and panels:
  ```ts
  function updateSettings() {
    const layer = ui!.settingsLayerEl;
    if (!state.settingsOpen) { layer.classList.add('hidden'); return; }
    if (layer.children.length === 0) layer.appendChild(renderSettings());
    layer.classList.remove('hidden');
  }
  ```
- **Signature gate** for re-renders (see `updateModal` —
  `modalEventId|modalTab` only rebuilds when the signature changes).
- **In-place mutation** of textContent / `classList.toggle` /
  inline styles when only a small fact changed.
- **Per-id caches** (timeline tracks, minimap marks, event-list rows)
  so existing nodes survive across updates.

Rules of thumb:

- If you find yourself writing `replaceChildren(...)` in `update*`,
  pause. Is this section actually changing? Can you write a signature
  string and bail when it hasn't?
- If the section contains form inputs (`<select>`, `<input>`, focus
  targets) the bar is even higher — never rebuild while the popup is
  visible.
- When state writes don't affect a section, that section should be a
  no-op. Hot paths like SSE log streams hit `update()` many times a
  second; each `update*` should detect "nothing for me" cheaply.

### State changes go through `scheduleUpdate()`

Never call `update()` directly. `scheduleUpdate()` coalesces multiple
state changes into one `requestAnimationFrame` callback. This is what
keeps the UI smooth under bursty SSE streams.

### Listeners attached at module scope, not per-render

Module-level `mousemove` / `mouseup` listeners read a module-level
drag state struct (e.g. `minimapDrag`). Do not attach
`window.addEventListener('mousemove', …)` inside any render function
— that leaks a handler per render. Local element listeners (`button.
addEventListener('click', …)`) are fine because the elements
themselves are persistent.

### Mock device (dev only)

`mock.ts` is loaded via `if (import.meta.env.DEV) await
import('./mock')` at the top of `main.ts`. The DEV check is
statically replaced by Vite, so the module is **tree-shaken out of
production builds** (verified by grepping the bundled `index.html`
for `'mock device'`). Anything you put in `mock.ts` is free —
production users will never download it.

If you want a feature flag that ships to prod, use a different
mechanism (URL hash, localStorage, etc.).

### Color & status

- Status palette: `ok` → emerald, `warn` → yellow, `failed` → rose.
- Categories that aren't HTTP-shaped (logs) use a level palette
  defined in `logLevelBarCls`. App-side network events use `ok/warn/
  failed` via `pillColorCls`. Bridge-API events use `bridgePillColorCls`
  (muted slate) so they're visually subordinate.
- Use the helper functions — don't sprinkle hex colors in
  components.

### Network detail modal lazy-fetches detail

The `/api/devtools/{requests,network}` list endpoints return summary
fields only. When the user opens the modal for a network event, we
call `hydrateNetworkDetail(ev)` which hits the matching `:id` detail
endpoint and merges full headers/body into `ev.raw`. The modal
rebuild gate (`modalEventId` / `modalTabRendered`) is invalidated so
the rebuild reflects the fresh data. If you add a new modal tab,
make sure you reset both fields when changing tab.

## Conventions for new tabs in the network modal

The tab order is fixed: Response, Request, Timing, cURL, Raw. If you
add a new tab:

1. Add it to the `state.modalTab` union in `main.ts` AND to
   `renderNetworkBody()`'s tab list AND to the `switch` in
   `renderNetworkBody()`.
2. Render a `renderXxxSection(raw)` helper that takes only the
   event's raw map (so it survives the lazy hydration without
   stashed closures).
3. If the tab leaks any secret-shaped data, mask via
   `maskHeaderValue` (or its equivalent) — the existing
   convention is `##TOKEN##` / `##VALUE##`.

## TypeScript settings

- `strict: true`
- `noUnusedLocals: true`
- `noUnusedParameters: true`
- `noFallthroughCasesInSwitch: true`

If you don't want to use a parameter, prefix it with `_`. If you
shadow a global (like `el` for our DOM helper), the linter may
complain — pick a different name rather than disabling the rule.

## When you finish

1. `npm run typecheck` — must pass.
2. `npm run build` — must succeed.
3. Verified visually in `npm run dev` against the mock device
   (or against a real benchmark app on `:8889`).
4. **Committed the regenerated `../lib/src/devtools/web/index.html`**
   alongside the source change.
