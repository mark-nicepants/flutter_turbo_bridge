const api = (path, opts = {}) =>
  fetch('api/' + path, {
    ...opts,
    headers: { 'x-turbo-devtools': '1', ...(opts.headers || {}) },
  });

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// ----- Tabs -----
$$('.tab').forEach((btn) => {
  btn.addEventListener('click', () => {
    $$('.tab').forEach((b) => b.classList.remove('active'));
    $$('.panel').forEach((p) => p.classList.remove('active'));
    btn.classList.add('active');
    $('#panel-' + btn.dataset.tab).classList.add('active');
  });
});

// ----- Toast -----
function toast(msg, ms = 1500) {
  let el = $('#toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    el.className = 'toast';
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('show'), ms);
}

// ----- Health -----
async function refreshHealth() {
  try {
    const r = await api('health');
    const dot = $('#health-dot');
    const text = $('#health-text');
    if (r.ok) {
      dot.className = 'dot ok';
      text.textContent = 'connected · bridge ok';
    } else {
      dot.className = 'dot err';
      text.textContent = 'bridge returned ' + r.status;
    }
  } catch (e) {
    $('#health-dot').className = 'dot err';
    $('#health-text').textContent = 'bridge unreachable';
  }
}
setInterval(refreshHealth, 5000);
refreshHealth();

// ----- App info (also used as the source of truth for tap coordinates) -----
//
// The app's logical screen size (in dp) is what /api/tap expects as
// (x, y). We cache it here and refresh whenever the user hits "Refresh"
// or captures a screenshot, so a click on the screenshot translates
// directly to logical coordinates without needing to know the screenshot's
// pixel ratio.
let appLogical = { width: 0, height: 0 };

async function refreshInfo() {
  try {
    const r = await api('info');
    const json = await r.json();
    $('#info-json').textContent = JSON.stringify(json, null, 2);
    if (typeof json.screenWidth === 'number' && typeof json.screenHeight === 'number') {
      appLogical = { width: json.screenWidth, height: json.screenHeight };
    }
  } catch (e) {
    $('#info-json').textContent = String(e);
  }
}
$('#info-refresh').addEventListener('click', refreshInfo);
refreshInfo();

// ----- Screenshot -----
let shotTimer = null;

async function captureScreenshot() {
  // Refresh app dimensions in case the device orientation changed.
  refreshInfo();
  const pr = parseFloat($('#shot-pixel-ratio').value) || 1;
  const r = await api('screenshot?pixelRatio=' + pr + '&t=' + Date.now());
  if (!r.ok) {
    toast('Screenshot failed: ' + r.status);
    return;
  }
  const blob = await r.blob();
  const objUrl = URL.createObjectURL(blob);
  const img = $('#shot-image');
  if (img.dataset.blobUrl) URL.revokeObjectURL(img.dataset.blobUrl);
  img.dataset.blobUrl = objUrl;
  img.src = objUrl;
  const w = parseInt(r.headers.get('x-image-width') || '0', 10);
  const h = parseInt(r.headers.get('x-image-height') || '0', 10);
  const ms = parseInt(r.headers.get('x-capture-time-ms') || '0', 10);
  $('#shot-meta').textContent =
    w + ' x ' + h + ' px · captured in ' + ms + ' ms';
}

$('#shot-capture').addEventListener('click', captureScreenshot);
$('#shot-interval').addEventListener('change', (e) => {
  if (shotTimer) { clearInterval(shotTimer); shotTimer = null; }
  const ms = parseInt(e.target.value, 10);
  if (ms > 0) shotTimer = setInterval(captureScreenshot, ms);
});

function logicalCoordsFromEvent(e) {
  if (!appLogical.width || !appLogical.height) return null;
  const img = e.currentTarget;
  if (!img.naturalWidth) return null;
  const rect = img.getBoundingClientRect();
  return {
    x: ((e.clientX - rect.left) / rect.width) * appLogical.width,
    y: ((e.clientY - rect.top) / rect.height) * appLogical.height,
    rect,
  };
}

$('#shot-image').addEventListener('click', async (e) => {
  const coords = logicalCoordsFromEvent(e);
  if (!coords) {
    toast(appLogical.width ? 'Capture a screenshot first.' : 'App size unknown — hit Refresh on the Overview tab.');
    return;
  }
  if ($('#shot-mode').checked) {
    await pickWidget(coords);
  } else {
    await sendTap(coords);
  }
});

async function sendTap({ x, y }) {
  try {
    const r = await api('tap', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ x, y }),
    });
    const json = await r.json();
    if (json.success === false || r.status >= 400) {
      toast('Tap failed: ' + (json.error || r.status));
    } else {
      toast('Tap at ' + x.toFixed(1) + ', ' + y.toFixed(1));
      setTimeout(captureScreenshot, 250);
    }
  } catch (err) {
    toast('Tap error: ' + err);
  }
}

// ----- Widget inspector -----
async function pickWidget({ x, y }) {
  try {
    const r = await api('pick?x=' + x + '&y=' + y);
    if (!r.ok) {
      toast('Pick failed: ' + r.status);
      return;
    }
    const json = await r.json();
    renderInspector(json.chain || []);
  } catch (err) {
    toast('Pick error: ' + err);
  }
}

function renderInspector(chain) {
  const panel = $('#inspector-panel');
  const content = $('#inspector-content');
  const overlay = $('#shot-overlay');
  overlay.innerHTML = '';
  content.innerHTML = '';
  if (!chain.length) {
    panel.hidden = true;
    return;
  }
  panel.hidden = false;
  // Reverse so the most-specific widget is on top.
  const ordered = [...chain].reverse();
  ordered.forEach((node, idx) => {
    const row = document.createElement('div');
    row.className = 'inspector-node' + (idx === 0 ? ' selected' : '');
    const parts = [`<span class="type">${node.type}</span>`];
    if (node.key) parts.push(`<span class="key">key=${node.key}</span>`);
    if (node.text) parts.push(`<span class="key">"${node.text}"</span>`);
    if (node.rect) parts.push(`<span class="attrs">${Math.round(node.rect.x)},${Math.round(node.rect.y)} · ${Math.round(node.rect.w)}×${Math.round(node.rect.h)}</span>`);
    row.innerHTML = parts.join(' · ');
    row.addEventListener('click', () => {
      $$('.inspector-node').forEach((n) => n.classList.remove('selected'));
      row.classList.add('selected');
      drawPickRect(node.rect);
    });
    content.appendChild(row);
  });
  drawPickRect(ordered[0].rect);
}

function drawPickRect(rect) {
  const overlay = $('#shot-overlay');
  overlay.innerHTML = '';
  if (!rect || !appLogical.width) return;
  const img = $('#shot-image');
  const imgRect = img.getBoundingClientRect();
  overlay.style.width = imgRect.width + 'px';
  overlay.style.height = imgRect.height + 'px';
  const sx = imgRect.width / appLogical.width;
  const sy = imgRect.height / appLogical.height;
  const box = document.createElement('div');
  box.className = 'pick-rect';
  box.style.left = (rect.x * sx) + 'px';
  box.style.top = (rect.y * sy) + 'px';
  box.style.width = (rect.w * sx) + 'px';
  box.style.height = (rect.h * sy) + 'px';
  overlay.appendChild(box);
}

// ----- Widget tree -----
function renderTreeNode(node, filter) {
  const el = document.createElement('div');
  el.className = 'tree-node';
  const label = document.createElement('div');
  label.className = 'row-label';
  const hasChildren = Array.isArray(node.children) && node.children.length > 0;
  const toggle = document.createElement('span');
  toggle.className = 'tree-toggle';
  toggle.textContent = hasChildren ? '▾' : '·';
  label.appendChild(toggle);
  const type = document.createElement('span');
  type.className = 'tree-type';
  type.textContent = node.type || node.runtimeType || '?';
  label.appendChild(type);
  if (node.text || node.label) {
    const t = document.createElement('span');
    t.className = 'tree-text';
    t.textContent = ' "' + (node.text || node.label) + '"';
    label.appendChild(t);
  }
  const extras = [];
  if (node.key) extras.push('key=' + node.key);
  if (node.rect) extras.push('rect=' + JSON.stringify(node.rect));
  if (extras.length) {
    const a = document.createElement('span');
    a.className = 'tree-attrs';
    a.textContent = ' · ' + extras.join(' · ');
    label.appendChild(a);
  }
  el.appendChild(label);

  const haystack = JSON.stringify({
    type: node.type,
    text: node.text || node.label,
    key: node.key,
  }).toLowerCase();
  if (filter && haystack.includes(filter)) el.classList.add('match');

  if (hasChildren) {
    const childWrap = document.createElement('div');
    for (const c of node.children) childWrap.appendChild(renderTreeNode(c, filter));
    el.appendChild(childWrap);
    label.addEventListener('click', () => {
      const hidden = childWrap.style.display === 'none';
      childWrap.style.display = hidden ? '' : 'none';
      toggle.textContent = hidden ? '▾' : '▸';
    });
  }
  return el;
}

async function captureTree() {
  const depth = parseInt($('#tree-depth').value, 10) || 10;
  const compact = $('#tree-compact').checked ? 'true' : 'false';
  const r = await api('tree?depth=' + depth + '&compact=' + compact);
  if (!r.ok) {
    $('#tree-view').textContent = 'Tree fetch failed: ' + r.status;
    return;
  }
  const json = await r.json();
  const filter = $('#tree-filter').value.trim().toLowerCase();
  const view = $('#tree-view');
  view.innerHTML = '';
  if (json.rootWidget) {
    view.appendChild(renderTreeNode(json.rootWidget, filter));
  } else {
    view.textContent = 'No root widget in response.';
  }
}
$('#tree-capture').addEventListener('click', captureTree);
$('#tree-filter').addEventListener('input', captureTree);

// ----- Find -----
$('#find-go').addEventListener('click', async () => {
  const params = new URLSearchParams();
  const text = $('#find-text').value.trim();
  const type = $('#find-type').value.trim();
  const key = $('#find-key').value.trim();
  if (text) params.set('text', text);
  if (type) params.set('type', type);
  if (key) params.set('key', key);
  params.set('limit', $('#find-limit').value || '10');
  params.set('visibleOnly', $('#find-visible').checked ? 'true' : 'false');
  params.set('interactiveOnly', $('#find-interactive').checked ? 'true' : 'false');
  const r = await api('find?' + params.toString());
  const text2 = await r.text();
  try {
    $('#find-results').textContent = JSON.stringify(JSON.parse(text2), null, 2);
  } catch {
    $('#find-results').textContent = text2;
  }
});

// ----- Request log -----
const logBody = $('#log-body');
const logRows = [];

function statusClass(status) {
  if (status >= 500) return 'log-status-5xx';
  if (status >= 400) return 'log-status-4xx';
  return 'log-status-2xx';
}

function addLogRow(entry) {
  const filter = $('#log-filter').value.trim().toLowerCase();
  const haystack = (entry.method + ' ' + entry.path).toLowerCase();
  if (filter && !haystack.includes(filter)) return;
  const tr = document.createElement('tr');
  const time = new Date(entry.timestamp).toLocaleTimeString();
  tr.innerHTML =
    '<td>' + time + '</td>' +
    '<td>' + entry.method + '</td>' +
    '<td>' + entry.path + (entry.query ? '?' + entry.query : '') + '</td>' +
    '<td class="' + statusClass(entry.status) + '">' + entry.status + '</td>' +
    '<td>' + entry.durationMs + ' ms</td>' +
    '<td>' + (entry.remoteAddress || '') + '</td>';
  logBody.prepend(tr);
  logRows.push(tr);
  while (logRows.length > 500) {
    const old = logRows.shift();
    old.remove();
  }
}

async function loadInitialLog() {
  try {
    const r = await api('devtools/requests');
    const json = await r.json();
    (json.entries || []).forEach(addLogRow);
  } catch (e) {
    console.error('initial log load failed', e);
  }
}
loadInitialLog();

$('#log-clear').addEventListener('click', () => {
  logBody.innerHTML = '';
  logRows.length = 0;
});

// ----- Bridge log row click → detail panel -----
async function showRequestDetail(id) {
  const panel = $('#log-detail');
  try {
    const r = await api('devtools/requests/' + id);
    if (!r.ok) {
      panel.hidden = true;
      return;
    }
    panel.hidden = false;
    panel.innerHTML = renderDetail(await r.json(), 'request');
    panel.querySelector('.close').addEventListener('click', () => {
      panel.hidden = true;
    });
  } catch (err) {
    panel.hidden = true;
  }
}

function renderHeaders(headers) {
  if (!headers || !Object.keys(headers).length) return '<span class="hint">none</span>';
  return '<div class="headers">' + Object.entries(headers)
    .map(([k, v]) => `<div class="header-row"><span class="header-name">${k}</span><span>${escapeHtml(v)}</span></div>`)
    .join('') + '</div>';
}

function renderBody(body, truncated) {
  if (!body) return '<span class="hint">empty</span>';
  return '<div class="body">' + escapeHtml(prettyMaybe(body)) + '</div>' +
    (truncated ? '<div class="truncated">⚠ truncated — body exceeded the 16 KB capture cap</div>' : '');
}

function prettyMaybe(s) {
  if (typeof s !== 'string') return String(s);
  const t = s.trim();
  if ((t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']'))) {
    try { return JSON.stringify(JSON.parse(t), null, 2); } catch {}
  }
  return s;
}

function escapeHtml(s) {
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function renderDetail(entry, kind) {
  const title = kind === 'request'
    ? `${entry.method} ${entry.path}${entry.query ? '?' + entry.query : ''} → ${entry.status}`
    : `${entry.method} ${entry.url} → ${entry.status ?? '—'}`;
  return `
    <button class="close">close</button>
    <h3>${escapeHtml(title)}</h3>
    <div class="hint">${new Date(entry.timestamp).toLocaleString()} · ${entry.durationMs ?? '?'} ms${entry.remoteAddress ? ' · from ' + entry.remoteAddress : ''}</div>
    <div class="section">
      <div class="section-title">Request headers</div>
      ${renderHeaders(entry.requestHeaders)}
    </div>
    <div class="section">
      <div class="section-title">Request body${entry.requestBodySize != null ? ' (' + entry.requestBodySize + ' B)' : ''}</div>
      ${renderBody(entry.requestBody, entry.requestBodyTruncated)}
    </div>
    <div class="section">
      <div class="section-title">Response headers</div>
      ${renderHeaders(entry.responseHeaders)}
    </div>
    <div class="section">
      <div class="section-title">Response body${entry.responseBodySize != null ? ' (' + entry.responseBodySize + ' B)' : ''}</div>
      ${renderBody(entry.responseBody, entry.responseBodyTruncated)}
    </div>
  `;
}

// Make rows clickable.
logBody.addEventListener('click', (e) => {
  const tr = e.target.closest('tr[data-id]');
  if (!tr) return;
  $$('#log-body tr').forEach((r) => r.classList.remove('selected'));
  tr.classList.add('selected');
  showRequestDetail(parseInt(tr.dataset.id, 10));
});

// Augment addLogRow with the row's id so the detail click works.
const _origAddLogRow = addLogRow;
addLogRow = function (entry) {
  const filter = $('#log-filter').value.trim().toLowerCase();
  const haystack = (entry.method + ' ' + entry.path).toLowerCase();
  if (filter && !haystack.includes(filter)) return;
  const tr = document.createElement('tr');
  tr.className = 'log-row';
  tr.dataset.id = entry.id;
  const time = new Date(entry.timestamp).toLocaleTimeString();
  tr.innerHTML =
    '<td>' + time + '</td>' +
    '<td>' + entry.method + '</td>' +
    '<td>' + entry.path + (entry.query ? '?' + entry.query : '') + '</td>' +
    '<td class="' + statusClass(entry.status) + '">' + entry.status + '</td>' +
    '<td>' + entry.durationMs + ' ms</td>' +
    '<td>' + (entry.remoteAddress || '') + '</td>';
  logBody.prepend(tr);
  logRows.push(tr);
  while (logRows.length > 500) {
    const old = logRows.shift();
    old.remove();
  }
};

// ----- App logs tab -----
const logsBody = $('#logs-body');
const logsRows = [];
const LEVEL_ORDER = { trace: 0, debug: 1, info: 2, warn: 3, error: 4 };

function logsLevelOK(level) {
  const min = $('#logs-level').value;
  if (!min) return true;
  return LEVEL_ORDER[level] >= LEVEL_ORDER[min];
}

function addAppLogRow(entry) {
  if (!logsLevelOK(entry.level)) return;
  const filter = $('#logs-filter').value.trim().toLowerCase();
  const haystack = (entry.message + ' ' + (entry.category || '')).toLowerCase();
  if (filter && !haystack.includes(filter)) return;
  $('#logs-empty').hidden = true;
  $('#logs-table').hidden = false;
  const tr = document.createElement('tr');
  tr.className = 'log-row';
  const time = new Date(entry.timestamp).toLocaleTimeString();
  tr.innerHTML =
    '<td>' + time + '</td>' +
    '<td class="log-level-' + entry.level + '">' + entry.level + '</td>' +
    '<td>' + (entry.category || '') + '</td>' +
    '<td>' + escapeHtml(entry.message) +
      (entry.error ? '<div class="hint">' + escapeHtml(entry.error) + '</div>' : '') +
    '</td>';
  logsBody.prepend(tr);
  logsRows.push(tr);
  while (logsRows.length > 500) logsRows.shift().remove();
}

async function loadInitialAppLogs() {
  try {
    const r = await api('devtools/logs');
    const json = await r.json();
    (json.entries || []).forEach(addAppLogRow);
  } catch (e) { console.error('logs load', e); }
}
loadInitialAppLogs();

$('#logs-clear').addEventListener('click', () => { logsBody.innerHTML = ''; logsRows.length = 0; });
$('#logs-level').addEventListener('change', loadInitialAppLogs);
$('#logs-filter').addEventListener('input', () => { logsBody.innerHTML = ''; logsRows.length = 0; loadInitialAppLogs(); });

// ----- Network tab -----
const netBody = $('#net-body');
const netRows = [];

function addNetRow(entry) {
  const filter = $('#net-filter').value.trim().toLowerCase();
  const haystack = (entry.method + ' ' + entry.url).toLowerCase();
  if (filter && !haystack.includes(filter)) return;
  $('#net-empty').hidden = true;
  $('#net-table').hidden = false;
  const tr = document.createElement('tr');
  tr.className = 'log-row';
  tr.dataset.id = entry.id;
  const time = new Date(entry.timestamp).toLocaleTimeString();
  const status = entry.status ?? '—';
  const statusCls = entry.status ? statusClass(entry.status) : '';
  tr.innerHTML =
    '<td>' + time + '</td>' +
    '<td>' + entry.method + '</td>' +
    '<td>' + escapeHtml(entry.url) + '</td>' +
    '<td class="' + statusCls + '">' + status + (entry.error ? ' (err)' : '') + '</td>' +
    '<td>' + (entry.durationMs != null ? entry.durationMs + ' ms' : '—') + '</td>' +
    '<td>' + (entry.responseBodySize != null ? entry.responseBodySize + ' B' : '—') + '</td>';
  netBody.prepend(tr);
  netRows.push(tr);
  while (netRows.length > 500) netRows.shift().remove();
}

netBody.addEventListener('click', async (e) => {
  const tr = e.target.closest('tr[data-id]');
  if (!tr) return;
  $$('#net-body tr').forEach((r) => r.classList.remove('selected'));
  tr.classList.add('selected');
  const panel = $('#net-detail');
  try {
    const r = await api('devtools/network/' + tr.dataset.id);
    if (!r.ok) { panel.hidden = true; return; }
    panel.hidden = false;
    panel.innerHTML = renderDetail(await r.json(), 'network');
    panel.querySelector('.close').addEventListener('click', () => { panel.hidden = true; });
  } catch { panel.hidden = true; }
});

async function loadInitialNetwork() {
  try {
    const r = await api('devtools/network');
    const json = await r.json();
    (json.entries || []).forEach(addNetRow);
  } catch (e) { console.error('net load', e); }
}
loadInitialNetwork();

$('#net-clear').addEventListener('click', () => { netBody.innerHTML = ''; netRows.length = 0; });
$('#net-filter').addEventListener('input', () => { netBody.innerHTML = ''; netRows.length = 0; loadInitialNetwork(); });

function connectEvents() {
  const es = new EventSource('events');
  es.addEventListener('request', (e) => {
    try { addLogRow(JSON.parse(e.data).payload); } catch {}
  });
  es.addEventListener('log', (e) => {
    try { addAppLogRow(JSON.parse(e.data).payload); } catch {}
  });
  es.addEventListener('network', (e) => {
    try { addNetRow(JSON.parse(e.data).payload); } catch {}
  });
  es.onerror = () => {
    setTimeout(connectEvents, 2000);
    es.close();
  };
}
connectEvents();
