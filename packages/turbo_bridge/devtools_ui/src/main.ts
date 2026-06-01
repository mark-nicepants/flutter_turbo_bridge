import './styles.css';
import {
  api,
  fromRequest,
  fromNetwork,
  fromLog,
  fromNavigation,
} from './api';
import type { CategoryDef, EventCategory, TimelineEvent } from './types';

if (import.meta.env.DEV) {
  await import('./mock');
}

// ============================================================
// State
// ============================================================

const CATEGORIES: CategoryDef[] = [
  {
    key: 'network',
    label: 'Network',
    iconSvg:
      '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M2 4a1 1 0 011-1h10a1 1 0 011 1v1H2V4zm0 3h12v1H2V7zm0 3h12v3a1 1 0 01-1 1H3a1 1 0 01-1-1v-3z"/></svg>',
  },
  {
    key: 'log',
    label: 'Logs',
    iconSvg:
      '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M3 2h10v2H3V2zm0 4h10v2H3V6zm0 4h7v2H3v-2z"/></svg>',
  },
  {
    key: 'navigation',
    label: 'Navigation',
    iconSvg:
      '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M4 3a3 3 0 016 0v2H4V3zm6 4v3a3 3 0 11-6 0V7h6z"/></svg>',
  },
  {
    key: 'error',
    label: 'Errors',
    iconSvg:
      '<svg viewBox="0 0 16 16" class="size-3.5"><circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="1.5" fill="none"/><path fill="currentColor" d="M7.25 4h1.5l-.2 4.5h-1.1l-.2-4.5zm.75 5.5a1 1 0 110 2 1 1 0 010-2z"/></svg>',
  },
  {
    key: 'bridge',
    label: 'Bridge API',
    iconSvg:
      '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M2 5h12v2H2V5zm0 4h12v2H2V9zm2-7h2v2H4V2zm6 11h2v1h-2v-1z"/><path fill="currentColor" d="M3 7v2H2V7h1zm11 0v2h-1V7h1z"/></svg>',
  },
];
const CATEGORY_KEYS: EventCategory[] = CATEGORIES.map((c) => c.key);
// Categories enabled by default. We exclude the bridge row because
// most users care about app behavior, not the JSON-API chatter from
// MCP clients / the DevTools UI itself.
const DEFAULT_ENABLED: EventCategory[] = ['network', 'log', 'navigation', 'error'];

interface State {
  events: TimelineEvent[];
  enabledCategories: Set<EventCategory>;
  statusFilter: 'all' | 'ok' | 'failed';
  windowStart: number;
  windowDuration: number;
  follow: boolean;
  // Retention: events older than (Date.now() - retentionMs) are dropped.
  // 0 disables retention. Surfaced as a dropdown in the header.
  retentionMs: number;
  modalEvent: TimelineEvent | null;
  modalTab: 'request' | 'response' | 'curl';
  // Persistent settings — loaded from localStorage on boot, written
  // back on every change.
  settings: PersistedSettings;
  settingsOpen: boolean;
}

interface PersistedSettings {
  /** Editor to open `vscode://`-style links with. */
  ide: IdeKey;
}

type IdeKey = 'vscode' | 'vscode-insiders' | 'cursor' | 'idea' | 'zed' | 'none';

interface IdeDef {
  key: IdeKey;
  label: string;
  /** Build a URL from an absolute file path + 1-based line/col. Return
   *  null if this IDE can't handle the given path (e.g. `package:`). */
  buildUrl: (absolutePath: string, line: number, col: number) => string | null;
}

const IDES: IdeDef[] = [
  {
    key: 'vscode',
    label: 'VS Code',
    buildUrl: (p, l, c) => `vscode://file${p}:${l}:${c}`,
  },
  {
    key: 'vscode-insiders',
    label: 'VS Code Insiders',
    buildUrl: (p, l, c) => `vscode-insiders://file${p}:${l}:${c}`,
  },
  {
    key: 'cursor',
    label: 'Cursor',
    buildUrl: (p, l, c) => `cursor://file${p}:${l}:${c}`,
  },
  {
    key: 'idea',
    label: 'IntelliJ IDEA / WebStorm / Android Studio',
    // JetBrains IDEs (idea, webstorm, pycharm, android-studio, …) all
    // accept this query-string format via the built-in `idea://` URL
    // handler that ships with the Toolbox helper.
    buildUrl: (p, l, c) =>
      `idea://open?file=${encodeURIComponent(p)}&line=${l}&column=${c}`,
  },
  {
    key: 'zed',
    label: 'Zed',
    buildUrl: (p, l, c) => `zed://file${p}:${l}:${c}`,
  },
  {
    key: 'none',
    label: 'No deep link (copy path only)',
    buildUrl: () => null,
  },
];

const SETTINGS_STORAGE_KEY = 'turbo_bridge_devtools_settings_v1';

function loadSettings(): PersistedSettings {
  const fallback: PersistedSettings = { ide: 'vscode' };
  try {
    const raw = localStorage.getItem(SETTINGS_STORAGE_KEY);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as Partial<PersistedSettings>;
    const ide = parsed.ide && IDES.some((i) => i.key === parsed.ide)
      ? (parsed.ide as IdeKey)
      : fallback.ide;
    return { ide };
  } catch {
    return fallback;
  }
}

function saveSettings(s: PersistedSettings) {
  try {
    localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify(s));
  } catch {
    // private browsing / quota — silently ignore.
  }
}

const DEFAULT_WINDOW_MS = 10_000;
const MIN_WINDOW_MS = 250;
const MAX_WINDOW_MS = 30 * 60_000;

const RETENTION_OPTIONS: { label: string; ms: number }[] = [
  { label: '10s', ms: 10_000 },
  { label: '30s', ms: 30_000 },
  { label: '1m', ms: 60_000 },
  { label: '5m', ms: 5 * 60_000 },
  { label: '30m', ms: 30 * 60_000 },
  { label: '∞', ms: 0 },
];

const state: State = {
  events: [],
  enabledCategories: new Set(DEFAULT_ENABLED),
  statusFilter: 'all',
  windowStart: Date.now() - DEFAULT_WINDOW_MS,
  windowDuration: DEFAULT_WINDOW_MS,
  follow: true,
  retentionMs: 30_000,
  modalEvent: null,
  modalTab: 'request',
  settings: loadSettings(),
  settingsOpen: false,
};

// ============================================================
// Helpers
// ============================================================

const el = <K extends keyof HTMLElementTagNameMap>(
  tag: K,
  cls = '',
  inner: string | null = '',
): HTMLElementTagNameMap[K] => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (inner != null && inner !== '') e.innerHTML = inner;
  return e;
};

function fmtAbs(ms: number): string {
  if (!Number.isFinite(ms)) return '—';
  return new Date(ms).toLocaleTimeString();
}

// Same as `fmtAbs` but with the millisecond suffix so timestamps in
// the event list can be ordered visually within a single second.
function fmtAbsMs(ms: number): string {
  if (!Number.isFinite(ms)) return '—';
  const d = new Date(ms);
  return `${d.toLocaleTimeString()}.${`${d.getMilliseconds()}`.padStart(3, '0')}`;
}

function fmtAxisTime(t: number, wDur: number): string {
  if (!Number.isFinite(t)) return '—';
  if (wDur < 2000) {
    const d = new Date(t);
    return `${d.toLocaleTimeString()}.${`${d.getMilliseconds()}`.padStart(3, '0')}`;
  }
  return new Date(t).toLocaleTimeString();
}

function escapeHtml(s: string): string {
  return s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

function fullRange(): { min: number; max: number } {
  if (state.events.length === 0) {
    const t = Date.now();
    return { min: t - DEFAULT_WINDOW_MS, max: t };
  }
  let min = Infinity;
  let max = -Infinity;
  for (const e of state.events) {
    if (e.timestamp < min) min = e.timestamp;
    const end = e.timestamp + (e.durationMs ?? 0);
    if (end > max) max = end;
  }
  return { min, max };
}

function maybeFollow() {
  if (!state.follow) return;
  // Use wall-clock "now" rather than the timestamp of the latest event,
  // so the window keeps gliding even when nothing is happening. The
  // follow ticker (`ensureFollowTicker`) keeps this updating between
  // events; this call covers the path where new events trigger upsert().
  state.windowStart = Date.now() - state.windowDuration;
  ensureFollowTicker();
}

// Smooth follow ticker: while `state.follow` is true, advance the
// window every ~33ms (≈30fps) so the right edge stays pinned to "now"
// even when no new events are arriving. Self-stops once follow flips
// off, restarts whenever maybeFollow runs.
let followRafId = 0;
let lastFollowFrame = 0;
const FOLLOW_TICK_MS = 33;
function tickFollow(t: number) {
  followRafId = 0;
  if (!state.follow) return;
  if (t - lastFollowFrame >= FOLLOW_TICK_MS) {
    lastFollowFrame = t;
    state.windowStart = Date.now() - state.windowDuration;
    scheduleUpdate();
  }
  followRafId = requestAnimationFrame(tickFollow);
}
function ensureFollowTicker() {
  if (followRafId || !state.follow) return;
  lastFollowFrame = 0;
  followRafId = requestAnimationFrame(tickFollow);
}

function windowEnd(): number {
  return state.windowStart + state.windowDuration;
}

function passesFilters(ev: TimelineEvent): boolean {
  if (!state.enabledCategories.has(ev.category)) return false;
  if (state.statusFilter === 'ok' && ev.status !== 'ok') return false;
  if (state.statusFilter === 'failed' && ev.status === 'ok') return false;
  const end = ev.timestamp + (ev.durationMs ?? 0);
  if (end < state.windowStart || ev.timestamp > windowEnd()) return false;
  return true;
}

function statusDotCls(status: TimelineEvent['status']): string {
  return status === 'ok'
    ? 'bg-emerald-400'
    : status === 'warn'
      ? 'bg-yellow-400'
      : 'bg-rose-400';
}

function pillColorCls(status: TimelineEvent['status']): string {
  switch (status) {
    case 'ok':
      return 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30';
    case 'warn':
      return 'bg-yellow-500/15 text-yellow-300 ring-yellow-500/30';
    case 'failed':
      return 'bg-rose-500/15 text-rose-300 ring-rose-500/30';
  }
}

// Bridge-API pills use a muted slate palette so they're visually
// distinct from app-emitted network calls.
function bridgePillColorCls(status: TimelineEvent['status']): string {
  switch (status) {
    case 'ok':
      return 'bg-slate-500/15 text-slate-300 ring-slate-500/30';
    case 'warn':
      return 'bg-yellow-500/15 text-yellow-300 ring-yellow-500/30';
    case 'failed':
      return 'bg-rose-500/15 text-rose-300 ring-rose-500/30';
  }
}

function logLevelBarCls(raw: Record<string, unknown>): string {
  const lvl = (raw['level'] as string | undefined) ?? 'info';
  switch (lvl) {
    case 'trace':
      return 'bg-zinc-500';
    case 'debug':
      return 'bg-sky-400';
    case 'info':
      return 'bg-emerald-400';
    case 'warn':
      return 'bg-yellow-400';
    case 'error':
      return 'bg-rose-400';
    default:
      return 'bg-zinc-400';
  }
}

function miniColorCls(ev: TimelineEvent): string {
  if (ev.status === 'failed') return 'bg-rose-400';
  if (ev.status === 'warn') return 'bg-yellow-400';
  switch (ev.category) {
    case 'network':
      return 'bg-emerald-400/80';
    case 'log':
      return 'bg-sky-400/80';
    case 'navigation':
      return 'bg-cyan-400/80';
    case 'error':
      return 'bg-rose-400';
    case 'bridge':
      return 'bg-slate-400/70';
  }
}

function isHttpEvent(ev: TimelineEvent): boolean {
  return ev.category === 'network' || ev.category === 'bridge';
}

function categoryRowTopPx(cat: EventCategory): number {
  // Five strips inside the 48px minimap track, 8px apart.
  switch (cat) {
    case 'network':
      return 4;
    case 'log':
      return 12;
    case 'navigation':
      return 20;
    case 'error':
      return 28;
    case 'bridge':
      return 36;
  }
}

// ============================================================
// UI: persistent DOM references built once at mount()
// ============================================================

interface UI {
  root: HTMLElement;

  // Header — persistent refs so we never re-create chips/dropdowns
  // out from under the user's pointer.
  header: {
    el: HTMLElement;
    okBtn: HTMLButtonElement;
    failedBtn: HTMLButtonElement;
    windowLabel: HTMLElement;
    showAllBtn: HTMLButtonElement;
    followBtn: HTMLButtonElement;
    retentionSelect: HTMLSelectElement;
  };

  // Timeline labels + tracks.
  labelEls: Record<EventCategory, HTMLElement>;
  trackEls: Record<EventCategory, HTMLElement>;
  pillsByCategory: Record<EventCategory, Map<string, HTMLElement>>;
  axisEl: HTMLElement;

  // Minimap.
  minimapTrackEl: HTMLElement;
  minimapMarksById: Map<string, HTMLElement>;
  minimapViewportEl: HTMLElement;

  // Event list (scroll-preserving).
  eventListEl: HTMLElement;
  eventListEmptyEl: HTMLElement;
  eventRowsById: Map<string, HTMLElement>;

  // Modal lives in a separate layer (overlay div); show/hide instead of
  // recreating each update.
  modalLayerEl: HTMLElement;

  // Settings popup layer — anchored top-right under the gear.
  settingsLayerEl: HTMLElement;
}

let ui: UI | null = null;

const LABEL_WIDTH = 160;

function mount(root: HTMLElement) {
  root.classList.add(
    'flex',
    'flex-col',
    'h-full',
    'bg-zinc-950',
    'text-zinc-100',
  );

  const headerEl = el(
    'header',
    'flex items-center gap-3 px-4 h-12 border-b border-zinc-800 bg-zinc-900/40 backdrop-blur shrink-0',
  );
  headerEl.appendChild(
    el(
      'div',
      'font-semibold tracking-tight text-sm text-zinc-100 mr-4',
      'turbo_bridge <span class="text-zinc-500 font-normal">·</span> DevTools',
    ),
  );
  const okBtn = buildStatusChip('ok', 'OK', 'bg-emerald-400');
  const failedBtn = buildStatusChip('failed', 'FAILED', 'bg-rose-400');
  headerEl.appendChild(okBtn);
  headerEl.appendChild(failedBtn);
  headerEl.appendChild(el('div', 'flex-1'));

  const winChip = el(
    'div',
    'flex items-center gap-2 text-[11px] uppercase tracking-wider text-zinc-400',
  );
  const windowLabel = el('span', 'font-mono tabular-nums');
  winChip.appendChild(windowLabel);

  const showAllBtn = el(
    'button',
    'h-7 px-3 rounded-full ring-1 text-[11px] uppercase tracking-wider transition-colors bg-transparent text-zinc-400 ring-zinc-700 hover:text-zinc-200 hover:ring-zinc-500',
    'show all',
  ) as HTMLButtonElement;
  showAllBtn.title = 'Zoom out to cover the full retained history';
  showAllBtn.addEventListener('click', () => {
    const { min, max } = fullRange();
    state.windowStart = min;
    state.windowDuration = Math.max(MIN_WINDOW_MS, max - min);
    state.follow =
      state.windowStart + state.windowDuration >= max - 50;
    scheduleUpdate();
  });
  winChip.appendChild(showAllBtn);

  const followBtn = el(
    'button',
    'h-7 px-3 rounded-full ring-1 text-[11px] uppercase tracking-wider transition-colors',
  ) as HTMLButtonElement;
  followBtn.addEventListener('click', () => {
    state.follow = !state.follow;
    if (state.follow) maybeFollow();
    scheduleUpdate();
  });
  winChip.appendChild(followBtn);
  headerEl.appendChild(winChip);

  const retentionWrap = el(
    'label',
    'flex items-center gap-1.5 text-[11px] uppercase tracking-wider text-zinc-500',
  );
  retentionWrap.appendChild(el('span', '', 'keep'));
  const retentionSelect = el(
    'select',
    'h-7 px-2 rounded-md ring-1 ring-zinc-700 bg-zinc-900 text-zinc-200 text-[11px] uppercase tracking-wider hover:ring-zinc-500 focus:outline-none focus:ring-zinc-400 cursor-pointer',
  ) as HTMLSelectElement;
  for (const opt of RETENTION_OPTIONS) {
    const o = document.createElement('option');
    o.value = String(opt.ms);
    o.textContent = opt.label;
    if (opt.ms === state.retentionMs) o.selected = true;
    retentionSelect.appendChild(o);
  }
  retentionSelect.addEventListener('change', () => {
    state.retentionMs = parseInt(retentionSelect.value, 10) || 0;
    prune();
    scheduleUpdate();
  });
  retentionWrap.appendChild(retentionSelect);
  headerEl.appendChild(retentionWrap);

  const dev = (import.meta as any).env?.DEV;
  const indicator = el('div', 'flex items-center gap-2 text-xs text-zinc-400');
  indicator.innerHTML = dev
    ? '<span class="size-1.5 rounded-full bg-amber-400 animate-pulse"></span>mock device'
    : '<span class="size-1.5 rounded-full bg-emerald-400 animate-pulse"></span>live';
  headerEl.appendChild(indicator);

  // Gear button — opens the settings popup.
  const gearBtn = el(
    'button',
    'shrink-0 text-zinc-500 hover:text-zinc-200 rounded-md p-1.5 ring-1 ring-transparent hover:ring-zinc-700 transition-colors',
    '<svg viewBox="0 0 16 16" class="size-4"><path fill="currentColor" d="M8 2a1 1 0 011 1v.6a4.5 4.5 0 011.7.7l.5-.3a1 1 0 011.3.4l.5.9a1 1 0 01-.4 1.3l-.5.3a4.5 4.5 0 010 2l.5.3a1 1 0 01.4 1.3l-.5.9a1 1 0 01-1.3.4l-.5-.3a4.5 4.5 0 01-1.7.7V13a1 1 0 11-2 0v-.6a4.5 4.5 0 01-1.7-.7l-.5.3a1 1 0 01-1.3-.4l-.5-.9a1 1 0 01.4-1.3l.5-.3a4.5 4.5 0 010-2l-.5-.3a1 1 0 01-.4-1.3l.5-.9a1 1 0 011.3-.4l.5.3a4.5 4.5 0 011.7-.7V3a1 1 0 011-1zm0 4a2 2 0 100 4 2 2 0 000-4z"/></svg>',
  ) as HTMLButtonElement;
  gearBtn.title = 'Settings';
  gearBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    state.settingsOpen = !state.settingsOpen;
    scheduleUpdate();
  });
  headerEl.appendChild(gearBtn);

  root.appendChild(headerEl);

  // -- Timeline section ----------------------------------------------------
  const timelineSection = el(
    'section',
    'border-b border-zinc-800 bg-zinc-950 select-none shrink-0',
  );

  const timelineMain = el('div', 'flex');
  const labelCol = el('div', 'flex flex-col flex-none');
  labelCol.style.width = `${LABEL_WIDTH}px`;
  const tracksCol = el(
    'div',
    'flex-1 min-w-0 relative overflow-hidden',
  );

  const labelEls: Record<EventCategory, HTMLElement> = {} as never;
  const trackEls: Record<EventCategory, HTMLElement> = {} as never;
  const pillsByCategory: Record<EventCategory, Map<string, HTMLElement>> =
    {} as never;
  for (const cat of CATEGORIES) {
    labelEls[cat.key] = buildRowLabel(cat);
    labelCol.appendChild(labelEls[cat.key]);
    trackEls[cat.key] = el(
      'div',
      'relative h-9 border-b border-zinc-800/60 overflow-hidden',
    );
    tracksCol.appendChild(trackEls[cat.key]);
    pillsByCategory[cat.key] = new Map();
  }

  // Axis label and bar
  labelCol.appendChild(
    el(
      'div',
      'h-6 flex items-center justify-end pr-3 text-[10px] uppercase tracking-wider text-zinc-500 border-t border-zinc-800',
      'time',
    ),
  );
  const axisEl = el(
    'div',
    'relative h-6 border-t border-zinc-800 text-[10px] text-zinc-500 font-mono overflow-hidden',
  );
  tracksCol.appendChild(axisEl);

  timelineMain.appendChild(labelCol);
  timelineMain.appendChild(tracksCol);
  timelineSection.appendChild(timelineMain);

  attachWheelZoom(tracksCol);

  // -- Minimap ------------------------------------------------------------
  const minimap = el(
    'div',
    'flex border-t border-zinc-800 bg-zinc-900/40 shrink-0',
  );
  const miniLabel = el(
    'div',
    'flex items-center justify-end pr-3 text-[10px] uppercase tracking-wider text-zinc-500',
    'overview',
  );
  miniLabel.style.width = `${LABEL_WIDTH}px`;
  miniLabel.style.flex = 'none';
  minimap.appendChild(miniLabel);

  const minimapTrackEl = el(
    'div',
    'flex-1 min-w-0 relative h-12 cursor-grab select-none overflow-hidden',
  );
  // Background ticks (static — never need updating).
  for (let i = 1; i < 6; i++) {
    const tick = el(
      'div',
      'absolute top-0 bottom-0 border-l border-zinc-800/60 pointer-events-none',
    );
    tick.style.left = `${(i / 6) * 100}%`;
    minimapTrackEl.appendChild(tick);
  }
  const minimapViewportEl = el(
    'div',
    'absolute top-0 bottom-0 bg-cyan-500/10 border-x border-cyan-400/70 cursor-grab',
  );
  minimapTrackEl.appendChild(minimapViewportEl);
  minimap.appendChild(minimapTrackEl);
  timelineSection.appendChild(minimap);
  attachMinimapHandlers(minimapTrackEl, minimapViewportEl);

  root.appendChild(timelineSection);

  // -- Event list ---------------------------------------------------------
  const eventListWrap = el(
    'section',
    'flex-1 min-h-0 overflow-auto',
  );
  const eventListEmptyEl = el(
    'div',
    'px-4 py-10 text-center text-zinc-500 text-sm hidden',
    'No events match the current filters.',
  );
  const eventListEl = el('div', 'divide-y divide-zinc-800/60');
  eventListWrap.appendChild(eventListEmptyEl);
  eventListWrap.appendChild(eventListEl);
  root.appendChild(eventListWrap);

  // -- Modal layer --------------------------------------------------------
  const modalLayerEl = el('div', 'hidden');
  root.appendChild(modalLayerEl);

  const settingsLayerEl = el('div', 'hidden');
  root.appendChild(settingsLayerEl);

  ui = {
    root,
    header: {
      el: headerEl,
      okBtn,
      failedBtn,
      windowLabel,
      showAllBtn,
      followBtn,
      retentionSelect,
    },
    labelEls,
    trackEls,
    pillsByCategory,
    axisEl,
    minimapTrackEl,
    minimapMarksById: new Map(),
    minimapViewportEl,
    eventListEl,
    eventListEmptyEl,
    eventRowsById: new Map(),
    modalLayerEl,
    settingsLayerEl,
  };
}

// ============================================================
// Update — called whenever state changes; mutates the DOM in place
// ============================================================

let pendingFrame = 0;
function scheduleUpdate() {
  if (pendingFrame) return;
  pendingFrame = requestAnimationFrame(() => {
    pendingFrame = 0;
    update();
  });
}

function update() {
  if (!ui) return;
  updateHeader();
  updateRowLabels();
  for (const cat of CATEGORY_KEYS) updateTrack(cat);
  updateAxis();
  updateMinimap();
  updateEventList();
  updateModal();
  updateSettings();
}

// ---------- Header ----------

// Header is built once in mount(); update only mutates the things that
// actually change. Crucially we keep the same <button> / <select> nodes
// across updates so hover, focus, and the open dropdown menu survive
// SSE-driven re-renders.
const STATUS_CHIP_ACTIVE = ['bg-zinc-100', 'text-zinc-900', 'ring-zinc-100'];
const STATUS_CHIP_INACTIVE = [
  'bg-transparent',
  'text-zinc-400',
  'ring-zinc-700',
  'hover:text-zinc-200',
  'hover:ring-zinc-500',
];
const FOLLOW_ACTIVE = [
  'bg-cyan-500/15',
  'text-cyan-300',
  'ring-cyan-500/30',
  'hover:bg-cyan-500/25',
];
const FOLLOW_INACTIVE = [
  'bg-transparent',
  'text-zinc-400',
  'ring-zinc-700',
  'hover:text-zinc-200',
  'hover:ring-zinc-500',
];

function buildStatusChip(
  key: 'ok' | 'failed',
  label: string,
  dotCls: string,
): HTMLButtonElement {
  const btn = el(
    'button',
    'flex items-center gap-1.5 text-[11px] uppercase tracking-wider h-7 px-3 rounded-full ring-1 transition-colors',
  ) as HTMLButtonElement;
  btn.innerHTML = `<span class="size-1.5 rounded-full ${dotCls}"></span>${label}`;
  btn.dataset.key = key;
  btn.addEventListener('click', () => {
    state.statusFilter = state.statusFilter === key ? 'all' : key;
    scheduleUpdate();
  });
  return btn;
}

function setChipActive(btn: HTMLButtonElement, active: boolean) {
  btn.classList.remove(...STATUS_CHIP_ACTIVE, ...STATUS_CHIP_INACTIVE);
  btn.classList.add(...(active ? STATUS_CHIP_ACTIVE : STATUS_CHIP_INACTIVE));
}

function updateHeader() {
  const h = ui!.header;
  setChipActive(h.okBtn, state.statusFilter === 'ok');
  setChipActive(h.failedBtn, state.statusFilter === 'failed');

  const winText = `${(state.windowDuration / 1000).toFixed(
    state.windowDuration < 2000 ? 2 : 1,
  )}s window`;
  if (h.windowLabel.textContent !== winText) h.windowLabel.textContent = winText;

  // Follow button (label + classes).
  const followText = state.follow ? '▶ following' : 'jump to live';
  if (h.followBtn.textContent !== followText) h.followBtn.textContent = followText;
  h.followBtn.classList.remove(...FOLLOW_ACTIVE, ...FOLLOW_INACTIVE);
  h.followBtn.classList.add(...(state.follow ? FOLLOW_ACTIVE : FOLLOW_INACTIVE));

  // Retention <select>: only sync if it differs and the user isn't
  // mid-interaction (sync would close their open dropdown).
  const wantVal = String(state.retentionMs);
  if (h.retentionSelect.value !== wantVal && document.activeElement !== h.retentionSelect) {
    h.retentionSelect.value = wantVal;
  }
}

// ---------- Row labels ----------

function buildRowLabel(cat: CategoryDef): HTMLElement {
  const wrap = el(
    'button',
    'flex items-center gap-2 px-3 text-[11px] uppercase tracking-wider h-9 border-b border-zinc-800/60 transition-colors',
  );
  wrap.title = 'click: toggle · double-click: solo (show only this row)';
  wrap.innerHTML = `<span class="text-zinc-500">${cat.iconSvg}</span><span>${cat.label}</span>`;

  // Defer single-click toggle so we can cancel it if a double-click
  // arrives within the platform double-click interval.
  let pendingClick: number | undefined;
  wrap.addEventListener('click', () => {
    if (pendingClick) window.clearTimeout(pendingClick);
    pendingClick = window.setTimeout(() => {
      pendingClick = undefined;
      if (state.enabledCategories.has(cat.key)) {
        state.enabledCategories.delete(cat.key);
      } else {
        state.enabledCategories.add(cat.key);
      }
      scheduleUpdate();
    }, 220);
  });
  wrap.addEventListener('dblclick', () => {
    if (pendingClick) {
      window.clearTimeout(pendingClick);
      pendingClick = undefined;
    }
    const isAlreadySolo =
      state.enabledCategories.size === 1 &&
      state.enabledCategories.has(cat.key);
    state.enabledCategories.clear();
    if (isAlreadySolo) {
      // Toggle back to "all enabled" when you double-click the soloed row.
      for (const k of CATEGORY_KEYS) state.enabledCategories.add(k);
    } else {
      state.enabledCategories.add(cat.key);
    }
    scheduleUpdate();
  });
  return wrap;
}

function updateRowLabels() {
  for (const cat of CATEGORIES) {
    const el = ui!.labelEls[cat.key];
    const active = state.enabledCategories.has(cat.key);
    el.classList.toggle('text-zinc-200', active);
    el.classList.toggle('text-zinc-600', !active);
    el.classList.toggle('hover:bg-zinc-900', active);
    el.classList.toggle('hover:bg-zinc-900/60', !active);
  }
}

// ---------- Tracks (incremental) ----------

function updateTrack(cat: EventCategory) {
  const track = ui!.trackEls[cat];
  const cache = ui!.pillsByCategory[cat];
  const enabled = state.enabledCategories.has(cat);
  track.classList.toggle('opacity-30', !enabled);

  const wStart = state.windowStart;
  const wDur = state.windowDuration;
  const wEnd = wStart + wDur;

  // Events in this row that intersect the window, sorted by timestamp.
  const visible = state.events
    .filter(
      (e) =>
        e.category === cat &&
        e.timestamp <= wEnd &&
        e.timestamp + (e.durationMs ?? 0) >= wStart,
    )
    .sort((a, b) => a.timestamp - b.timestamp);

  const tFrac = (t: number) => ((t - wStart) / wDur) * 100;
  const visibleIds = new Set(visible.map((e) => e.id));

  // Remove cached elements that are no longer visible.
  for (const [id, node] of cache) {
    if (!visibleIds.has(id)) {
      node.remove();
      cache.delete(id);
    }
  }

  for (let i = 0; i < visible.length; i++) {
    const ev = visible[i]!;
    const next = visible[i + 1];
    const naturalEnd = ev.timestamp + (ev.durationMs ?? 0);
    const clipEnd = next ? Math.min(naturalEnd, next.timestamp) : naturalEnd;
    const leftPct = tFrac(ev.timestamp);
    const widthPct = tFrac(clipEnd) - leftPct;

    let node = cache.get(ev.id);
    if (!node) {
      node = buildPillNode(ev);
      cache.set(ev.id, node);
      track.appendChild(node);
    }

    // Position + clipping update (cheap; just inline styles).
    node.style.left = `${leftPct}%`;
    if (cat === 'log') {
      // Logs are slim 3px colored bars.
      node.style.left = `calc(${leftPct}% - 1px)`;
    } else {
      if (widthPct > 0) {
        node.style.width = `${widthPct}%`;
      } else {
        node.style.width = '';
        node.style.minWidth = '4px';
      }
      if (next) {
        const maxRightPct = tFrac(next.timestamp);
        node.style.maxWidth = `${Math.max(maxRightPct - leftPct, 0.05)}%`;
      } else {
        node.style.maxWidth = '';
      }
    }

    // Selected ring (only when modal is open on this event).
    const selected = state.modalEvent?.id === ev.id;
    node.classList.toggle('ring-2', selected);
    node.classList.toggle('ring-cyan-300', selected);
  }
}

function buildPillNode(ev: TimelineEvent): HTMLElement {
  if (ev.category === 'log') {
    const bar = el(
      'button',
      `absolute top-1.5 bottom-1.5 w-[3px] ${logLevelBarCls(ev.raw)} hover:w-[6px] hover:z-10`,
    );
    bar.title = `${ev.label} · ${ev.raw['level']}`;
    bar.addEventListener('click', (e) => {
      e.stopPropagation();
      openModal(ev);
    });
    return bar;
  }
  const colorCls =
    ev.category === 'bridge' ? bridgePillColorCls(ev.status) : pillColorCls(ev.status);
  const pill = el(
    'button',
    [
      'absolute top-1 bottom-1 text-[11px] font-mono leading-none rounded-md ring-1 px-2 flex items-center truncate hover:z-10 hover:ring-2',
      colorCls,
    ].join(' '),
  );
  pill.innerHTML = `<span class="inline-block size-1 mr-1.5 rounded-full ${statusDotCls(ev.status)} shrink-0"></span><span class="truncate">${escapeHtml(ev.label)}</span>`;
  pill.title = `${ev.label}${ev.durationMs ? ' · ' + ev.durationMs + ' ms' : ''}`;
  pill.addEventListener('click', (e) => {
    e.stopPropagation();
    openModal(ev);
  });
  return pill;
}

// ---------- Axis (full rebuild — small) ----------

function updateAxis() {
  const axisEl = ui!.axisEl;
  axisEl.replaceChildren();
  const wStart = state.windowStart;
  const wDur = state.windowDuration;
  const ticks = 6;
  for (let i = 1; i < ticks; i++) {
    const t = wStart + (i / ticks) * wDur;
    const x = (i / ticks) * 100;
    const tick = el(
      'div',
      'absolute top-0 bottom-0 border-l border-zinc-800/80 pointer-events-none',
    );
    tick.style.left = `${x}%`;
    axisEl.appendChild(tick);
    const label = el(
      'span',
      'absolute top-1 -translate-x-1/2 px-1 bg-zinc-950',
      fmtAxisTime(t, wDur),
    );
    label.style.left = `${x}%`;
    axisEl.appendChild(label);
  }
  axisEl.appendChild(
    el(
      'span',
      'absolute top-1 left-1 text-zinc-600',
      fmtAxisTime(wStart, wDur),
    ),
  );
  axisEl.appendChild(
    el(
      'span',
      'absolute top-1 right-1 text-zinc-600',
      fmtAxisTime(wStart + wDur, wDur),
    ),
  );
}

// ---------- Minimap (incremental for marks, mutate viewport rect) ----------

let minimapMStart = 0;
let minimapMDur = 1;

function updateMinimap() {
  const trackEl = ui!.minimapTrackEl;
  const viewportEl = ui!.minimapViewportEl;
  const cache = ui!.minimapMarksById;

  const { min, max } = fullRange();
  const padding = Math.max((max - min) * 0.02, 200);
  minimapMStart = min - padding;
  minimapMDur = Math.max(max - min + padding * 2, 1000);

  const enabledIds = new Set(
    state.events
      .filter((e) => state.enabledCategories.has(e.category))
      .map((e) => e.id),
  );

  // Remove marks for events that are no longer eligible (filtered out
  // by category or evicted by ring-buffer cap).
  const present = new Set(state.events.map((e) => e.id));
  for (const [id, node] of cache) {
    if (!enabledIds.has(id) || !present.has(id)) {
      node.remove();
      cache.delete(id);
    }
  }

  // Ensure a mark exists for every eligible event; position it.
  for (const ev of state.events) {
    if (!state.enabledCategories.has(ev.category)) continue;
    let node = cache.get(ev.id);
    if (!node) {
      node = el(
        'div',
        `absolute w-[2px] ${miniColorCls(ev)} pointer-events-none`,
      );
      node.style.height = '7px';
      cache.set(ev.id, node);
      trackEl.insertBefore(node, viewportEl);
    }
    const leftPct = ((ev.timestamp - minimapMStart) / minimapMDur) * 100;
    node.style.left = `${leftPct}%`;
    node.style.top = `${categoryRowTopPx(ev.category)}px`;
  }

  // Update viewport rectangle position/width.
  const wStartPct = Math.max(
    ((state.windowStart - minimapMStart) / minimapMDur) * 100,
    0,
  );
  const wEndPct = Math.min(
    ((windowEnd() - minimapMStart) / minimapMDur) * 100,
    100,
  );
  viewportEl.style.left = `${wStartPct}%`;
  viewportEl.style.width = `${Math.max(wEndPct - wStartPct, 0.5)}%`;
}

// ---------- Event list (incremental, scroll-preserving) ----------

function updateEventList() {
  const listEl = ui!.eventListEl;
  const emptyEl = ui!.eventListEmptyEl;
  const cache = ui!.eventRowsById;

  // Compute the ordered, filtered set for the list (newest first).
  const visible = state.events
    .filter(passesFilters)
    .sort((a, b) => b.timestamp - a.timestamp);
  const visibleIds = new Set(visible.map((e) => e.id));

  // Drop rows that no longer pass filters.
  for (const [id, node] of cache) {
    if (!visibleIds.has(id)) {
      node.remove();
      cache.delete(id);
    }
  }

  // Insert/move rows into the correct order. We iterate `visible` and
  // re-attach existing rows in order using insertBefore — this is O(n)
  // and DOM moves are cheap; far better than full innerHTML rebuilds
  // because hovered/selected rows + the user's scroll position stay put.
  let cursor: ChildNode | null = listEl.firstChild;
  for (const ev of visible) {
    let row = cache.get(ev.id);
    if (!row) {
      row = buildEventRow(ev);
      cache.set(ev.id, row);
    }
    if (row !== cursor) {
      listEl.insertBefore(row, cursor);
    } else {
      cursor = cursor.nextSibling;
    }
    // Reflect selection state without rebuilding.
    const selected = state.modalEvent?.id === ev.id;
    row.classList.toggle('bg-cyan-500/10', selected);
  }

  emptyEl.classList.toggle('hidden', visible.length > 0);
}

function buildEventRow(ev: TimelineEvent): HTMLElement {
  const row = el(
    'button',
    'w-full text-left px-4 h-9 grid items-center gap-3 text-sm cursor-pointer transition-colors hover:bg-zinc-900/60',
  );
  row.style.gridTemplateColumns = '130px 90px 70px minmax(0, 1fr)';
  row.addEventListener('click', () => openModal(ev));
  row.appendChild(
    el(
      'div',
      'font-mono text-[11px] text-zinc-500 whitespace-nowrap tabular-nums',
      fmtAbsMs(ev.timestamp),
    ),
  );
  row.appendChild(
    el(
      'div',
      'flex items-center gap-2 text-[11px] uppercase tracking-wider text-zinc-400',
      `<span class="size-1.5 rounded-full ${statusDotCls(ev.status)}"></span>${ev.category}`,
    ),
  );
  row.appendChild(
    el(
      'div',
      'font-mono text-xs text-zinc-400 text-right tabular-nums',
      ev.durationMs != null ? `${ev.durationMs} ms` : '',
    ),
  );
  row.appendChild(
    el('div', 'truncate text-zinc-100 text-[13px]', escapeHtml(ev.label)),
  );
  return row;
}

// ---------- Modal (show/hide layer; rebuild only on open) ----------

let modalEventId: string | null = null;
let modalTabRendered: string | null = null;

function updateModal() {
  const layer = ui!.modalLayerEl;
  if (!state.modalEvent) {
    layer.classList.add('hidden');
    layer.replaceChildren();
    modalEventId = null;
    modalTabRendered = null;
    return;
  }
  // Only rebuild when the event or tab actually changed.
  const sig = `${state.modalEvent.id}|${state.modalTab}`;
  if (sig !== `${modalEventId}|${modalTabRendered}`) {
    layer.classList.remove('hidden');
    layer.replaceChildren(renderModal(state.modalEvent));
    modalEventId = state.modalEvent.id;
    modalTabRendered = state.modalTab;
  }
}

function renderModal(ev: TimelineEvent): HTMLElement {
  // Anchor at a fixed top offset so switching tabs doesn't shift the
  // tab strip around. Content grows downward.
  const backdrop = el(
    'div',
    'fixed inset-0 z-50 flex items-start justify-center bg-black/60 backdrop-blur-sm pt-16',
  );
  backdrop.addEventListener('click', (e) => {
    if (e.target === backdrop) closeModal();
  });
  const card = el(
    'div',
    'w-[min(1040px,92vw)] max-h-[calc(100vh-6rem)] bg-zinc-950 rounded-lg ring-1 ring-zinc-800 shadow-2xl flex flex-col overflow-hidden',
  );
  card.appendChild(renderModalHeader(ev));
  card.appendChild(renderModalBody(ev));
  backdrop.appendChild(card);
  return backdrop;
}

function renderModalHeader(ev: TimelineEvent): HTMLElement {
  const head = el(
    'header',
    'flex items-center gap-3 px-5 py-3 border-b border-zinc-800 bg-zinc-900/60',
  );
  if (isHttpEvent(ev)) {
    const method = (ev.raw['method'] as string | undefined) ?? 'GET';
    const url =
      (ev.raw['url'] as string | undefined) ??
      (ev.raw['path'] as string | undefined) ??
      '';
    const status = ev.raw['status'] as number | undefined;
    head.appendChild(
      el(
        'div',
        'shrink-0 text-[11px] font-semibold uppercase tracking-wider px-2 py-1 rounded ring-1 ring-zinc-700 bg-zinc-900 text-zinc-100',
        method,
      ),
    );
    head.appendChild(
      el(
        'div',
        'truncate font-mono text-sm text-zinc-100 flex-1',
        escapeHtml(url),
      ),
    );
    if (status) {
      head.appendChild(
        el(
          'div',
          `shrink-0 text-[11px] font-semibold px-2 py-1 rounded ring-1 ${pillColorCls(ev.status)}`,
          `${status}`,
        ),
      );
    }
    if (ev.durationMs != null) {
      head.appendChild(
        el(
          'div',
          'shrink-0 font-mono text-xs text-zinc-400',
          `${ev.durationMs} ms`,
        ),
      );
    }
  } else {
    head.appendChild(
      el(
        'div',
        'shrink-0 text-[11px] font-semibold uppercase tracking-wider px-2 py-1 rounded ring-1 ring-zinc-700 bg-zinc-900 text-zinc-100',
        ev.category,
      ),
    );
    head.appendChild(
      el(
        'div',
        'truncate font-mono text-sm text-zinc-100 flex-1',
        escapeHtml(ev.label),
      ),
    );
    head.appendChild(
      el(
        'div',
        'shrink-0 font-mono text-xs text-zinc-500',
        fmtAbs(ev.timestamp),
      ),
    );
  }
  const closeBtn = el(
    'button',
    'shrink-0 text-zinc-500 hover:text-zinc-200 rounded-md p-1 -mr-2',
    '<svg viewBox="0 0 16 16" class="size-4"><path fill="currentColor" d="M4.3 3.3a1 1 0 011.4 0L8 5.6l2.3-2.3a1 1 0 111.4 1.4L9.4 7l2.3 2.3a1 1 0 11-1.4 1.4L8 8.4 5.7 10.7a1 1 0 01-1.4-1.4L6.6 7 4.3 4.7a1 1 0 010-1.4z"/></svg>',
  );
  closeBtn.addEventListener('click', closeModal);
  head.appendChild(closeBtn);
  return head;
}

function renderModalBody(ev: TimelineEvent): HTMLElement {
  if (isHttpEvent(ev)) return renderNetworkBody(ev);
  const wrap = el(
    'div',
    'flex-1 min-h-0 overflow-auto p-4 bg-zinc-950 space-y-4',
  );
  const link = renderSourceLink(ev.raw);
  if (link) wrap.appendChild(link);
  wrap.appendChild(renderJsonBlock(ev.raw));
  return wrap;
}

/// Render the call-site link on a log event. ⌘-click opens the
/// configured editor (settings popup, top-right). Falls back to a
/// plain "copy path" button when:
/// - the source is a `package:` URI (we'd need pubspec resolution to
///   turn it into an absolute file path)
/// - the user selected "No deep link"
function renderSourceLink(raw: Record<string, unknown>): HTMLElement | null {
  const file = raw['sourceFile'];
  const line = raw['sourceLine'];
  if (typeof file !== 'string' || typeof line !== 'number') return null;
  const col = typeof raw['sourceColumn'] === 'number' ? raw['sourceColumn'] : 1;

  // Resolve to an absolute path for IDE deep links. `file:///abs/path`
  // → `/abs/path`; `package:foo/bar.dart` can't be resolved here so we
  // skip the deep link and show the path verbatim.
  let absPath: string | null = null;
  let displayPath = file;
  if (file.startsWith('file:///')) {
    absPath = '/' + file.slice('file:///'.length);
    displayPath = absPath;
  } else if (file.startsWith('file://')) {
    absPath = file.slice('file://'.length);
    displayPath = absPath;
  }

  const segments = displayPath.split('/');
  const short = segments.slice(-2).join('/');

  // Resolve the active IDE's URL builder; may return null for paths
  // the IDE can't handle.
  const ide = IDES.find((i) => i.key === state.settings.ide) ?? IDES[0]!;
  const href = absPath ? ide.buildUrl(absPath, line, col) : null;

  const wrap = el('div', 'flex items-center gap-3 text-xs');
  wrap.appendChild(
    el(
      'span',
      'text-[10px] uppercase tracking-wider text-zinc-500',
      'source',
    ),
  );

  if (href) {
    const a = el(
      'a',
      'font-mono text-cyan-300 hover:text-cyan-200 underline decoration-cyan-700 underline-offset-2 truncate',
      `${escapeHtml(short)}:${line}:${col}`,
    ) as HTMLAnchorElement;
    a.href = href;
    a.title = `${file}:${line}:${col} — ⌘-click to open in ${ide.label}`;
    wrap.appendChild(a);
  } else {
    const span = el(
      'span',
      'font-mono text-zinc-300 truncate',
      `${escapeHtml(short)}:${line}:${col}`,
    );
    span.title = file.startsWith('package:')
      ? `${file}:${line}:${col} — package: URIs can't be opened directly. Use "copy path" or switch IDE in settings.`
      : `${file}:${line}:${col}`;
    wrap.appendChild(span);
  }

  const copyTarget =
    absPath != null ? `${absPath}:${line}:${col}` : `${file}:${line}:${col}`;
  const copyBtn = el(
    'button',
    'text-[10px] uppercase tracking-wider px-2 py-0.5 rounded ring-1 ring-zinc-700 bg-zinc-900/80 text-zinc-300 hover:text-zinc-100 hover:ring-zinc-500',
    'copy path',
  );
  copyBtn.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(copyTarget);
      copyBtn.textContent = 'copied!';
      setTimeout(() => (copyBtn.textContent = 'copy path'), 1200);
    } catch {
      copyBtn.textContent = 'copy failed';
    }
  });
  wrap.appendChild(copyBtn);
  return wrap;
}

function renderNetworkBody(ev: TimelineEvent): HTMLElement {
  const wrap = el('div', 'flex flex-col min-h-0 flex-1');
  const tabs = el(
    'nav',
    'flex items-center gap-1 px-3 border-b border-zinc-800 bg-zinc-900/40',
  );
  (['request', 'response', 'curl'] as const).forEach((t) =>
    tabs.appendChild(modalTab(t)),
  );
  wrap.appendChild(tabs);

  const body = el('div', 'flex-1 min-h-0 overflow-auto');
  switch (state.modalTab) {
    case 'request':
      body.appendChild(renderRequestSection(ev.raw));
      break;
    case 'response':
      body.appendChild(renderResponseSection(ev.raw));
      break;
    case 'curl':
      body.appendChild(renderCurlSection(ev.raw));
      break;
  }
  wrap.appendChild(body);
  return wrap;
}

function modalTab(t: 'request' | 'response' | 'curl'): HTMLElement {
  const active = state.modalTab === t;
  const cap = t[0]!.toUpperCase() + t.slice(1);
  const btn = el(
    'button',
    [
      'text-xs uppercase tracking-wider px-3 py-2 rounded-t-md -mb-px transition-colors border-b-2',
      active
        ? 'text-zinc-100 border-cyan-400'
        : 'text-zinc-500 border-transparent hover:text-zinc-300',
    ].join(' '),
    cap,
  );
  btn.addEventListener('click', () => {
    state.modalTab = t;
    scheduleUpdate();
  });
  return btn;
}

function renderRequestSection(raw: Record<string, unknown>): HTMLElement {
  const wrap = el('div', 'p-4 space-y-4');
  wrap.appendChild(sectionTitle('Headers', raw['requestHeaders'] ? '' : 'none captured'));
  wrap.appendChild(renderHeadersTable(raw['requestHeaders'] as any));
  wrap.appendChild(
    sectionTitle(
      'Body',
      raw['requestBody'] ? `${raw['requestBodySize'] ?? '?'} B` : 'empty',
    ),
  );
  wrap.appendChild(renderBodyBlock(raw['requestBody'] as string | undefined));
  return wrap;
}

function renderResponseSection(raw: Record<string, unknown>): HTMLElement {
  const wrap = el('div', 'p-4 space-y-4');
  const status = raw['status'];
  if (status != null) {
    wrap.appendChild(
      el(
        'div',
        'flex items-center gap-3 text-xs text-zinc-400',
        `<span class="font-mono text-zinc-100">${status}</span>${raw['error'] ? `<span class="text-rose-400">${escapeHtml(String(raw['error']))}</span>` : ''}`,
      ),
    );
  }
  wrap.appendChild(sectionTitle('Headers', raw['responseHeaders'] ? '' : 'none captured'));
  wrap.appendChild(renderHeadersTable(raw['responseHeaders'] as any));
  wrap.appendChild(
    sectionTitle(
      'Body',
      raw['responseBody']
        ? `${raw['responseBodySize'] ?? '?'} B${raw['responseBodyTruncated'] ? ' · truncated' : ''}`
        : 'empty',
    ),
  );
  wrap.appendChild(renderBodyBlock(raw['responseBody'] as string | undefined));
  return wrap;
}

function buildCurlCommand(raw: Record<string, unknown>): string {
  const method = ((raw['method'] as string | undefined) ?? 'GET').toUpperCase();
  const url =
    (raw['url'] as string | undefined) ??
    (raw['path'] as string | undefined) ??
    '';
  const headers = (raw['requestHeaders'] as Record<string, string> | undefined) ?? {};
  const body = raw['requestBody'] as string | undefined;

  const parts: string[] = [`curl -X ${method} ${shellQuote(url)}`];
  for (const [k, v] of Object.entries(headers)) {
    parts.push(`-H ${shellQuote(`${k}: ${maskHeaderValue(k, v)}`)}`);
  }
  if (body) {
    parts.push(`--data ${shellQuote(body)}`);
  }
  return parts.join(' \\\n  ');
}

// Mask bearer tokens, cookies, and other secret-shaped header values so
// the exported curl is safe to paste into a doc / share with a teammate.
function maskHeaderValue(name: string, value: string): string {
  const lower = name.toLowerCase();
  if (lower === 'authorization') {
    const m = value.match(/^(Bearer|Basic|Digest|Token)\s+(.+)$/i);
    if (m) return `${m[1]} {{token}}`;
    return '{{token}}';
  }
  if (lower === 'cookie' || lower === 'set-cookie') {
    return value
      .split(';')
      .map((part) => {
        const eq = part.indexOf('=');
        if (eq < 0) return part;
        const key = part.slice(0, eq).trim();
        return `${key}={{value}}`;
      })
      .join('; ');
  }
  if (lower === 'x-api-key' || lower.endsWith('-api-key') || lower.endsWith('-token')) {
    return '{{token}}';
  }
  return value;
}

function shellQuote(s: string): string {
  // POSIX single-quote escape: 'foo' → 'foo', "won't" → 'won'"'"'t'.
  return `'${s.replaceAll("'", "'\\''")}'`;
}

function renderCurlSection(raw: Record<string, unknown>): HTMLElement {
  const wrap = el('div', 'p-4');
  wrap.appendChild(copyableCodeBlock(buildCurlCommand(raw)));
  return wrap;
}

function renderHeadersTable(headers: Record<string, string> | undefined): HTMLElement {
  if (!headers || Object.keys(headers).length === 0) {
    return el('div', 'text-zinc-500 text-xs', '<em>(none)</em>');
  }
  const tbl = el(
    'div',
    'rounded-md ring-1 ring-zinc-800 divide-y divide-zinc-800 bg-zinc-900/30 font-mono text-xs',
  );
  for (const [k, v] of Object.entries(headers)) {
    const row = el('div', 'grid grid-cols-[200px_minmax(0,1fr)] gap-4 px-3 py-1.5');
    row.appendChild(el('div', 'text-cyan-300 truncate', escapeHtml(k)));
    row.appendChild(el('div', 'text-zinc-200 break-all', escapeHtml(v)));
    tbl.appendChild(row);
  }
  return tbl;
}

function renderBodyBlock(body: string | undefined): HTMLElement {
  if (!body) return el('div', 'text-zinc-500 text-xs', '<em>(empty)</em>');
  const t = body.trim();
  let text = body;
  let isJson = false;
  if (
    (t.startsWith('{') && t.endsWith('}')) ||
    (t.startsWith('[') && t.endsWith(']'))
  ) {
    try {
      text = JSON.stringify(JSON.parse(t), null, 2);
      isJson = true;
    } catch {
      // leave as-is
    }
  }
  return copyableCodeBlock(text, { html: isJson ? highlightJson(text) : null });
}

// Generic "code block with a copy button in the corner". When `html`
// is provided it's used as the rendered (already escaped) markup;
// otherwise we escape `text` ourselves. The copy button always copies
// the raw `text`.
function copyableCodeBlock(
  text: string,
  opts: { html?: string | null; maxHeight?: string } = {},
): HTMLElement {
  const pre = el(
    'pre',
    [
      'relative rounded-md bg-zinc-900 ring-1 ring-zinc-800 p-3 text-[12px] font-mono text-zinc-200 overflow-auto whitespace-pre-wrap break-all',
      opts.maxHeight ? '' : 'max-h-[60vh]',
    ].join(' '),
  );
  if (opts.maxHeight) pre.style.maxHeight = opts.maxHeight;
  const code = el('code', 'block pr-12');
  if (opts.html != null) {
    code.innerHTML = opts.html;
  } else {
    code.textContent = text;
  }
  pre.appendChild(code);
  pre.appendChild(buildCopyButton(text));
  return pre;
}

function buildCopyButton(text: string): HTMLElement {
  const btn = el(
    'button',
    'absolute top-2 right-2 text-[10px] uppercase tracking-wider px-2 py-1 rounded ring-1 ring-zinc-700 bg-zinc-900/80 text-zinc-300 hover:text-zinc-100 hover:ring-zinc-500',
    'copy',
  );
  btn.addEventListener('click', async (e) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = 'copied!';
      setTimeout(() => (btn.textContent = 'copy'), 1200);
    } catch {
      btn.textContent = 'copy failed';
    }
  });
  return btn;
}

// ---------- JSON syntax highlighting -----------------------------------
// Tiny tokenizer that wraps strings / numbers / booleans / null / keys
// in colored spans. Operates on already-pretty-printed JSON text.
//
// Important: we tokenize the *raw* JSON (where quotes are still ASCII
// double-quotes), then escape *each token's text* exactly once on the
// way into HTML. Earlier versions escaped the whole string up front
// and then re-escaped inside the replacer, which double-encoded any
// `&` / `<` / `>` inside string values.
function highlightJson(src: string): string {
  const re =
    /("(?:[^"\\]|\\.)*"\s*:)|("(?:[^"\\]|\\.)*")|(\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(\btrue\b|\bfalse\b)|(\bnull\b)/g;
  let out = '';
  let lastIdx = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    // Plain text between tokens — escape once.
    if (m.index > lastIdx) {
      out += escapeHtml(src.slice(lastIdx, m.index));
    }
    let cls = '';
    if (m[1]) cls = 'text-cyan-300';
    else if (m[2]) cls = 'text-emerald-300';
    else if (m[3]) cls = 'text-amber-300';
    else if (m[4]) cls = 'text-sky-400 font-semibold';
    else if (m[5]) cls = 'text-zinc-500 italic';
    out += `<span class="${cls}">${escapeHtml(m[0])}</span>`;
    lastIdx = re.lastIndex;
  }
  if (lastIdx < src.length) {
    out += escapeHtml(src.slice(lastIdx));
  }
  return out;
}

function sectionTitle(title: string, hint: string): HTMLElement {
  const wrap = el('div', 'flex items-baseline gap-2');
  wrap.appendChild(
    el('h3', 'text-[10px] uppercase tracking-wider text-zinc-500', title),
  );
  if (hint) wrap.appendChild(el('span', 'text-[10px] text-zinc-600', hint));
  return wrap;
}

function renderJsonBlock(obj: unknown): HTMLElement {
  const text = JSON.stringify(obj, null, 2);
  return copyableCodeBlock(text, { html: highlightJson(text) });
}

// ---------- Settings popup ----------
//
// The popup contains a native <select>. Rebuilding it on every tick
// would close the user's open dropdown out from under them — so we
// build the popup DOM exactly once (lazily, on first open) and after
// that only toggle visibility. See `devtools_ui/AGENTS.md` for the
// general rule.

function updateSettings() {
  const layer = ui!.settingsLayerEl;
  if (!state.settingsOpen) {
    layer.classList.add('hidden');
    return;
  }
  if (layer.children.length === 0) {
    layer.appendChild(renderSettings());
  }
  layer.classList.remove('hidden');
}

function renderSettings(): HTMLElement {
  const backdrop = el(
    'div',
    'fixed inset-0 z-40 cursor-default',
  );
  backdrop.addEventListener('click', () => {
    state.settingsOpen = false;
    scheduleUpdate();
  });

  const panel = el(
    'div',
    'absolute top-12 right-3 z-50 w-[min(360px,calc(100vw-1.5rem))] bg-zinc-950 rounded-lg ring-1 ring-zinc-800 shadow-2xl p-4',
  );
  panel.addEventListener('click', (e) => e.stopPropagation());

  const header = el(
    'div',
    'flex items-center justify-between mb-3',
  );
  header.appendChild(
    el(
      'h3',
      'text-[11px] uppercase tracking-wider text-zinc-400 font-semibold',
      'Settings',
    ),
  );
  const closeBtn = el(
    'button',
    'text-zinc-500 hover:text-zinc-200 rounded-md p-1 -mr-1',
    '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M4.3 3.3a1 1 0 011.4 0L8 5.6l2.3-2.3a1 1 0 111.4 1.4L9.4 7l2.3 2.3a1 1 0 11-1.4 1.4L8 8.4 5.7 10.7a1 1 0 01-1.4-1.4L6.6 7 4.3 4.7a1 1 0 010-1.4z"/></svg>',
  );
  closeBtn.addEventListener('click', () => {
    state.settingsOpen = false;
    scheduleUpdate();
  });
  header.appendChild(closeBtn);
  panel.appendChild(header);

  // IDE picker.
  panel.appendChild(
    el(
      'label',
      'block text-[11px] uppercase tracking-wider text-zinc-500 mb-1.5',
      'Open source links with',
    ),
  );

  // The native <select>'s chevron sits flush against the right edge
  // (and is differently placed on every platform). Wrap it so we can
  // hide the native chevron via `appearance-none` and overlay our own
  // at a controlled offset.
  const selectWrap = el('div', 'relative');
  const select = el(
    'select',
    'appearance-none w-full h-9 pl-3 pr-9 rounded-md ring-1 ring-zinc-700 bg-zinc-900 text-zinc-200 text-sm hover:ring-zinc-500 focus:outline-none focus:ring-zinc-400 cursor-pointer truncate',
  ) as HTMLSelectElement;
  for (const ide of IDES) {
    const o = document.createElement('option');
    o.value = ide.key;
    o.textContent = ide.label;
    if (ide.key === state.settings.ide) o.selected = true;
    select.appendChild(o);
  }
  select.addEventListener('change', () => {
    state.settings.ide = select.value as IdeKey;
    saveSettings(state.settings);
    scheduleUpdate();
  });
  selectWrap.appendChild(select);
  selectWrap.appendChild(
    el(
      'span',
      'pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-zinc-500',
      '<svg viewBox="0 0 16 16" class="size-3.5"><path fill="currentColor" d="M3.7 5.7a1 1 0 011.4 0L8 8.6l2.9-2.9a1 1 0 111.4 1.4l-3.6 3.6a1 1 0 01-1.4 0L3.7 7.1a1 1 0 010-1.4z"/></svg>',
    ),
  );
  panel.appendChild(selectWrap);

  panel.appendChild(
    el(
      'p',
      'mt-2 text-[11px] text-zinc-500 leading-relaxed',
      'Click a source link in a log entry to ⌘-click into the chosen editor. Setting is saved in this browser.',
    ),
  );

  backdrop.appendChild(panel);
  return backdrop;
}

function openModal(ev: TimelineEvent) {
  state.modalEvent = ev;
  state.modalTab = 'request';
  scheduleUpdate();
  // The list / SSE payload is a summary — headers + body live behind a
  // detail endpoint. Fetch them lazily so the Response / Request / Curl
  // tabs can show full info.
  if (isHttpEvent(ev)) void hydrateNetworkDetail(ev);
}

async function hydrateNetworkDetail(ev: TimelineEvent) {
  const id = ev.raw['id'];
  if (typeof id !== 'number') return;
  const isBridge = ev.id.startsWith('bridge:');
  const path = isBridge
    ? `devtools/requests/${id}`
    : `devtools/network/${id}`;
  try {
    const detail = await api<Record<string, unknown>>(path);
    // Merge into the event's raw payload so subsequent re-renders show
    // full headers / body without a fresh fetch.
    ev.raw = { ...ev.raw, ...detail };
    if (state.modalEvent?.id === ev.id) {
      // Force the modal to rebuild since its rendered signature is the
      // same (id + tab) — but the underlying raw changed.
      modalEventId = null;
      modalTabRendered = null;
      scheduleUpdate();
    }
  } catch (err) {
    console.error('detail fetch failed', err);
  }
}

function closeModal() {
  state.modalEvent = null;
  scheduleUpdate();
}

// ============================================================
// Pan / zoom interaction (module-level, single set of listeners)
// ============================================================

function attachWheelZoom(tracksCol: HTMLElement) {
  tracksCol.addEventListener(
    'wheel',
    (e: WheelEvent) => {
      e.preventDefault();
      const rect = tracksCol.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const frac = Math.min(Math.max(x / rect.width, 0), 1);
      const cursorTime = state.windowStart + frac * state.windowDuration;
      const factor = Math.exp(e.deltaY * 0.0015);
      const newDur = Math.max(
        MIN_WINDOW_MS,
        Math.min(MAX_WINDOW_MS, state.windowDuration * factor),
      );
      state.windowStart = cursorTime - frac * newDur;
      state.windowDuration = newDur;
      const { max } = fullRange();
      state.follow = state.windowStart + state.windowDuration >= max - 50;
      scheduleUpdate();
    },
    { passive: false },
  );
}

interface MinimapDrag {
  trackEl: HTMLElement;
  px: number;
  t: number;
}
let minimapDrag: MinimapDrag | null = null;

function attachMinimapHandlers(
  trackEl: HTMLElement,
  viewportEl: HTMLElement,
) {
  trackEl.addEventListener('mousedown', (e) => {
    if (e.target !== trackEl) return;
    const rect = trackEl.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const t = minimapMStart + (x / rect.width) * minimapMDur;
    state.windowStart = t - state.windowDuration / 2;
    state.follow =
      state.windowStart + state.windowDuration >= fullRange().max - 50;
    scheduleUpdate();
  });
  viewportEl.addEventListener('mousedown', (e) => {
    e.stopPropagation();
    const rect = trackEl.getBoundingClientRect();
    minimapDrag = {
      trackEl,
      px: e.clientX - rect.left,
      t: state.windowStart,
    };
    document.body.style.cursor = 'grabbing';
  });
}

window.addEventListener('mousemove', (e) => {
  if (!minimapDrag) return;
  const rect = minimapDrag.trackEl.getBoundingClientRect();
  if (rect.width <= 0) return;
  const dx = e.clientX - rect.left - minimapDrag.px;
  const dt = (dx / rect.width) * minimapMDur;
  state.windowStart = minimapDrag.t + dt;
  state.follow =
    state.windowStart + state.windowDuration >= fullRange().max - 50;
  scheduleUpdate();
});
window.addEventListener('mouseup', () => {
  if (!minimapDrag) return;
  minimapDrag = null;
  document.body.style.cursor = '';
});

window.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (state.modalEvent) {
    closeModal();
  } else if (state.settingsOpen) {
    state.settingsOpen = false;
    scheduleUpdate();
  }
});

// ============================================================
// Data wiring
// ============================================================

function upsert(event: TimelineEvent) {
  const idx = state.events.findIndex((e) => e.id === event.id);
  if (idx >= 0) state.events[idx] = event;
  else state.events.push(event);
  prune();
  maybeFollow();
}

function prune() {
  // Hard cap by count to defend against runaway streams.
  if (state.events.length > 5000) {
    state.events.splice(0, state.events.length - 5000);
  }
  if (state.retentionMs <= 0) return;
  const cutoff = Date.now() - state.retentionMs;
  // Drop events whose right edge is older than the cutoff. We compare
  // on (timestamp + durationMs) so an in-flight 1s network call doesn't
  // disappear immediately on a 10s retention.
  let dropTo = 0;
  for (let i = 0; i < state.events.length; i++) {
    if (state.events[i]!.timestamp + (state.events[i]!.durationMs ?? 0) >= cutoff) {
      dropTo = i;
      break;
    }
    dropTo = i + 1;
  }
  if (dropTo > 0) state.events.splice(0, dropTo);
}

// Idle prune so the timeline doesn't show stale data when the app is
// quiet — without this, 30s-old events would linger as long as no new
// event triggers `upsert()`.
setInterval(() => {
  const before = state.events.length;
  prune();
  if (state.events.length !== before) scheduleUpdate();
}, 1000);

async function loadInitial() {
  try {
    const [bridge, network, logs, nav] = await Promise.all([
      api<{ entries: any[] }>('devtools/requests'),
      api<{ entries: any[] }>('devtools/network'),
      api<{ entries: any[] }>('devtools/logs'),
      api<{ entries: any[] }>('devtools/navigation').catch(() => ({ entries: [] })),
    ]);
    bridge.entries.forEach((e) => upsert(fromRequest(e)));
    network.entries.forEach((e) => upsert(fromNetwork(e)));
    logs.entries.forEach((e) => upsert(fromLog(e)));
    nav.entries.forEach((e) => upsert(fromNavigation(e)));
    maybeFollow();
    scheduleUpdate();
  } catch (err) {
    console.error('initial load failed', err);
  }
}

function connectEvents() {
  const es = new EventSource('events');
  const handlers: Record<string, (p: any) => TimelineEvent> = {
    request: fromRequest,
    network: fromNetwork,
    log: fromLog,
    navigation: fromNavigation,
  };
  for (const [type, conv] of Object.entries(handlers)) {
    es.addEventListener(type, (e) => {
      try {
        const p = JSON.parse((e as MessageEvent).data).payload;
        upsert(conv(p));
        scheduleUpdate();
      } catch (err) {
        console.error(`bad ${type} event`, err);
      }
    });
  }
  es.onerror = () => {
    setTimeout(connectEvents, 2000);
    es.close();
  };
}

// ============================================================
// Boot
// ============================================================

function boot() {
  const mountEl = document.getElementById('app');
  if (!mountEl) return;
  mount(mountEl);
  update();
  void loadInitial();
  connectEvents();
  ensureFollowTicker();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
