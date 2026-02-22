/* ═══════════════════════════════════════════════════════════════════════
   Kriegswabwehr – Premium Dashboard Controller
   FiveM NUI bridge + live queue management + tab system
   ═══════════════════════════════════════════════════════════════════════ */

'use strict';

// ── State ────────────────────────────────────────────────────────────────────
const state = {
    open:          false,
    currentTab:    'overview',
    attackLog:     [],
    pendingQueue:  [],       // current queue snapshot
    queueTimers:   {},       // { [token]: intervalId }
};

// ── FiveM NUI helper ─────────────────────────────────────────────────────────
function nuiFetch(endpoint, data) {
    return fetch('https://kriegswabwehr/' + endpoint, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data || {}),
    }).catch(() => {});
}

// ── Open / Close ─────────────────────────────────────────────────────────────
function openDashboard() {
    state.open = true;
    document.getElementById('dashboard').classList.remove('hidden');
    startClock();
    nuiFetch('requestStats');
    nuiFetch('getBanList');
    nuiFetch('getQueue');
    nuiFetch('getWhitelist');
}

function closeDashboard() {
    state.open = false;
    document.getElementById('dashboard').classList.add('hidden');
    nuiFetch('close');
}

// ── Clock ────────────────────────────────────────────────────────────────────
let _clockStarted = false;
function startClock() {
    if (_clockStarted) return;
    _clockStarted = true;
    const el = document.getElementById('clock');
    if (!el) return;
    const tick = () => { el.textContent = new Date().toLocaleTimeString('de-DE', {hour12:false}); };
    tick();
    setInterval(tick, 1000);
}

// ── Tab navigation ────────────────────────────────────────────────────────────
function switchTab(name) {
    // Deactivate all
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

    // Activate selected
    const pane = document.getElementById('tab-' + name);
    if (pane) pane.classList.add('active');
    const item = document.querySelector('[data-tab="' + name + '"]');
    if (item) item.classList.add('active');

    state.currentTab = name;

    // Refresh data when switching tabs
    if (name === 'bans')      nuiFetch('getBanList');
    if (name === 'whitelist') nuiFetch('getWhitelist');
    if (name === 'queue')     nuiFetch('getQueue');
    if (name === 'log')       loadLogDates();
}

// ── Stats update ──────────────────────────────────────────────────────────────
function applyStats(data) {
    if (!data) return;

    setText('tile-attempts', fmtNum(data.totalConnAttempts));
    setText('tile-blocked',  fmtNum(data.blockedLastMinute));
    setText('tile-legit',    fmtNum(data.legitimateConns));
    setText('tile-players',  (data.players || 0) + ' / ' + (data.maxPlayers || 32));
    setText('tile-tarpit',   fmtNum((data.tarpitStats  && data.tarpitStats.active)  || 0));
    setText('tile-permbans', fmtNum((data.banStats     && data.banStats.permBans)   || 0));

    // Intensity
    const pct = Math.min(100, Math.round(data.attackIntensity || 0));
    const bar = document.getElementById('intensity-bar');
    const lbl = document.getElementById('intensity-pct');
    if (bar) bar.style.width = pct + '%';
    if (lbl) lbl.textContent = pct + '%';

    // Header/dashboard under-attack state
    const dash = document.getElementById('dashboard');
    const dot  = document.getElementById('status-dot');
    const stxt = document.getElementById('status-text');
    if (pct >= 50) {
        dash && dash.classList.add('under-attack');
        dot  && dot.classList.add('attacking');
        if (stxt) { stxt.textContent = 'UNTER ANGRIFF'; stxt.className = 'attacking'; }
    } else {
        dash && dash.classList.remove('under-attack');
        dot  && dot.classList.remove('attacking');
        if (stxt) { stxt.textContent = 'AKTIV'; stxt.className = ''; }
    }

    // Charts
    if (typeof updateCharts === 'function') updateCharts(data);

    // Attack log (kept in memory, rendered only when log tab is active)
    if (Array.isArray(data.attackLog)) {
        state.attackLog = data.attackLog;
        const badge = document.getElementById('log-badge');
        if (badge) {
            badge.textContent = data.attackLog.length;
            badge.classList.toggle('hidden', data.attackLog.length === 0);
        }
        if (state.currentTab === 'log') renderAttackLog(data.attackLog);
        if (typeof updateMap === 'function') updateMap(data.attackLog);
    }

    // Queue embedded in stats
    if (Array.isArray(data.pendingQueue)) {
        applyQueue(data.pendingQueue);
    }
}

// ── Attack log ────────────────────────────────────────────────────────────────
function renderAttackLog(entries) {
    const tbody = document.getElementById('attack-log-body');
    if (!tbody) return;
    const rows = entries.slice(0, 200);
    if (rows.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="td-empty">Keine Ereignisse / No events</td></tr>';
        return;
    }
    const firstKey = rows[0].timestamp + rows[0].ip;
    if (tbody.dataset.firstKey === firstKey) return;
    tbody.dataset.firstKey = firstKey;
    tbody.innerHTML = rows.map((e, i) => `<tr class="${i === 0 ? 'row-new' : ''}">
        <td>${e.time || ''}</td>
        <td>${e.ip || '?'}</td>
        <td>${flag(e.country)} ${e.country || '?'}</td>
        <td>${e.isp || '?'}</td>
        <td>${e.attackType || '?'}</td>
        <td><span class="badge ${statusBadge(e.action || e.status)}">${(e.action || e.status || 'BLOCKED').toUpperCase()}</span></td>
    </tr>`).join('');
}

function clearLogTable() {
    state.attackLog = [];
    const tbody = document.getElementById('attack-log-body');
    if (tbody) tbody.innerHTML = '<tr><td colspan="6" class="td-empty">Geleert / Cleared</td></tr>';
}

// ── Ban list ──────────────────────────────────────────────────────────────────
function renderBanList(data) {
    const tbody = document.getElementById('ban-list-body');
    if (!tbody) return;
    const bans = (data && data.bans) ? data.bans : [];
    if (bans.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="td-empty">Keine aktiven Sperren</td></tr>';
        return;
    }
    tbody.innerHTML = bans.map(b => `<tr>
        <td><code>${b.ip || '?'}</code></td>
        <td><span class="badge ${b.type === 'perm' ? 'badge-perm' : 'badge-temp'}">${(b.type||'perm').toUpperCase()}</span></td>
        <td>${b.reason || '?'}</td>
        <td>${b.attackType || '?'}</td>
        <td>${b.expiry ? fmtRemaining(b.expiry) : '<span class="badge badge-perm">PERMANENT</span>'}</td>
        <td><button class="btn-unban" onclick="unbanIP('${b.ip}')">🔓 Entsperren</button></td>
    </tr>`).join('');
}

function unbanIP(ip) {
    if (!ip) return;
    nuiFetch('unbanIP', { ip });
    showToast('IP entsperrt', ip, 'success');
    setTimeout(() => nuiFetch('getBanList'), 400);
}

// ── Whitelist ─────────────────────────────────────────────────────────────────
function renderWhitelist(data) {
    const tbody = document.getElementById('whitelist-body');
    if (!tbody) return;
    const entries = (data && data.entries) ? data.entries : [];
    if (entries.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="td-empty">Keine Whitelist-Einträge / No entries</td></tr>';
        return;
    }
    tbody.innerHTML = entries.map(e => `<tr>
        <td><code>${e.identifier || '?'}</code></td>
        <td>${e.addedBy || '?'}</td>
        <td>${e.addedAt ? new Date(e.addedAt * 1000).toLocaleDateString('de-DE') : '?'}</td>
        <td>${e.note || '—'}</td>
        <td><button class="btn-remove" onclick="removeWhitelist('${esc(e.identifier)}')">🗑️ Entfernen</button></td>
    </tr>`).join('');
}

function openAddWhitelistModal() {
    document.getElementById('modal-overlay').classList.remove('hidden');
    document.getElementById('wl-identifier').focus();
}

function closeModal() {
    document.getElementById('modal-overlay').classList.add('hidden');
    document.getElementById('wl-identifier').value = '';
    document.getElementById('wl-note').value = '';
}

function submitAddWhitelist() {
    const id   = document.getElementById('wl-identifier').value.trim();
    const note = document.getElementById('wl-note').value.trim();
    if (!id) { showToast('Fehler', 'Identifier darf nicht leer sein', 'error'); return; }
    nuiFetch('addWhitelist', { identifier: id, note });
    closeModal();
    showToast('Whitelist', 'Eintrag wird hinzugefügt…', 'info');
}

function removeWhitelist(identifier) {
    nuiFetch('removeWhitelist', { identifier });
    showToast('Whitelist', identifier + ' entfernt', 'info');
    setTimeout(() => nuiFetch('getWhitelist'), 400);
}

// ── Queue system ─────────────────────────────────────────────────────────────
function applyQueue(queueArr) {
    state.pendingQueue = queueArr || [];

    // Update sidebar badge
    const badge = document.getElementById('queue-badge');
    if (badge) {
        badge.textContent = state.pendingQueue.length;
        badge.classList.toggle('hidden', state.pendingQueue.length === 0);
    }

    // Auto-switch to queue tab if there are new requests and we're on overview
    if (state.pendingQueue.length > 0 && state.currentTab === 'overview') {
        showToast('⏳ Neue Anfrage!',
            state.pendingQueue[0].name + ' wartet auf Freigabe', 'warn');
    }

    if (state.currentTab === 'queue') renderQueue();
}

function renderQueue() {
    const list  = document.getElementById('queue-list');
    const empty = document.getElementById('queue-empty');
    if (!list || !empty) return;

    if (state.pendingQueue.length === 0) {
        list.innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');

    // Clear old timers
    Object.values(state.queueTimers).forEach(clearInterval);
    state.queueTimers = {};

    list.innerHTML = state.pendingQueue.map(req => buildQueueCard(req)).join('');

    // Start countdown timers for each card
    state.pendingQueue.forEach(req => startCardTimer(req.token, req.addedAt, req.timeout || 120));
}

function buildQueueCard(req) {
    const geo = req.geoData || {};
    const ids = (req.identifiers || []).slice(0, 6);

    return `<div class="queue-card" id="qcard-${req.token}">
      <div class="qc-head">
        <div>
          <div class="qc-name">${esc(req.name || 'Unbekannt')}</div>
          <div class="qc-token">${req.token}</div>
        </div>
        <div class="qc-timer ok" id="qtimer-${req.token}">??s</div>
      </div>
      <div class="qc-body">
        <div class="qc-row"><span class="qc-label">🌐 IP</span><span class="qc-val">${req.ip || '?'}</span></div>
        ${geo.country ? `<div class="qc-row"><span class="qc-label">🌍 Land</span><span class="qc-val">${flag(geo.country)} ${geo.countryName || geo.country}</span></div>` : ''}
        ${geo.isp     ? `<div class="qc-row"><span class="qc-label">🏢 ISP</span><span class="qc-val">${esc(geo.isp)}</span></div>` : ''}
        ${geo.city    ? `<div class="qc-row"><span class="qc-label">📍 Stadt</span><span class="qc-val">${esc(geo.city)}</span></div>` : ''}
        <div class="qc-row"><span class="qc-label">⏱️ Wartet</span><span class="qc-val" id="qwait-${req.token}">…</span></div>
        <div class="qc-identifiers">
          ${ids.map(id => `<div class="qc-identifier-row">${esc(id)}</div>`).join('')}
          ${req.identifiers && req.identifiers.length > 6 ? `<div class="qc-identifier-row qc-label">+${req.identifiers.length - 6} weitere…</div>` : ''}
        </div>
      </div>
      <div class="qc-foot">
        <label class="toggle-label qc-permanent-wrap">
          <input type="checkbox" id="qperm-${req.token}"/>
          <span class="toggle-track"><span class="toggle-thumb"></span></span>
          Permanent whitelisten
        </label>
        <button class="btn-deny"    onclick="denyQueue('${req.token}')">✕ Ablehnen</button>
        <button class="btn-approve" onclick="approveQueue('${req.token}')">✓ Freigeben</button>
      </div>
    </div>`;
}

function startCardTimer(token, addedAt, timeout) {
    const now       = Math.floor(Date.now() / 1000);
    const elapsed   = now - (addedAt || now);
    const remaining = Math.max(0, timeout - elapsed);

    const timerEl = document.getElementById('qtimer-' + token);
    const waitEl  = document.getElementById('qwait-' + token);
    const card    = document.getElementById('qcard-' + token);

    const update = () => {
        const r = Math.max(0, remaining - Math.floor((Date.now()/1000) - now));
        if (timerEl) {
            timerEl.textContent = r + 's';
            timerEl.className   = 'qc-timer ' + (r > 60 ? 'ok' : r > 20 ? 'warn' : 'urgent');
        }
        if (waitEl) {
            const sec = Math.floor(Date.now()/1000) - now + elapsed;
            waitEl.textContent = sec + 's';
        }
        if (card && r <= 10) card.classList.add('urgent');
        if (r <= 0) {
            clearInterval(state.queueTimers[token]);
            delete state.queueTimers[token];
        }
    };
    update();
    state.queueTimers[token] = setInterval(update, 1000);
}

function approveQueue(token) {
    const permanent = document.getElementById('qperm-' + token);
    nuiFetch('approveQueue', {
        token,
        permanent: permanent ? permanent.checked : false,
    });
    removeQueueCard(token);
    showToast('✅ Freigegeben', 'Spieler wird verbunden…', 'success');
}

function denyQueue(token) {
    nuiFetch('denyQueue', { token, reason: 'Verbindung vom Admin abgelehnt.' });
    removeQueueCard(token);
    showToast('✕ Abgelehnt', 'Spieler wurde abgelehnt.', 'warn');
}

function removeQueueCard(token) {
    // Remove from state
    state.pendingQueue = state.pendingQueue.filter(r => r.token !== token);
    // Stop timer
    if (state.queueTimers[token]) {
        clearInterval(state.queueTimers[token]);
        delete state.queueTimers[token];
    }
    // Animate out
    const card = document.getElementById('qcard-' + token);
    if (card) {
        card.style.opacity    = '0';
        card.style.transform  = 'scale(.95)';
        card.style.transition = '.25s ease';
        setTimeout(() => { card.remove(); renderQueue(); }, 260);
    } else {
        renderQueue();
    }
    // Update badge
    const badge = document.getElementById('queue-badge');
    if (badge) {
        badge.textContent = state.pendingQueue.length;
        badge.classList.toggle('hidden', state.pendingQueue.length === 0);
    }
}

function toggleQueueMode(enabled) {
    // Tell server to enable/disable queue mode
    nuiFetch('setQueueMode', { enabled });
    showToast(
        enabled ? '⏳ Queue-Modus aktiv' : '⏳ Queue-Modus deaktiviert',
        enabled ? 'Spieler werden jetzt zur Genehmigung eingereiht.' : 'Spieler verbinden sich direkt.',
        'info'
    );
}

// ── Toast notifications ───────────────────────────────────────────────────────
function showToast(title, body, level) {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = 'toast ' + (level || 'error');
    toast.innerHTML = `<div class="toast-title">${title}</div><div class="toast-body">${body}</div>`;
    container.appendChild(toast);
    setTimeout(() => {
        toast.classList.add('removing');
        setTimeout(() => toast.remove(), 300);
    }, 5000);
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
}

function fmtNum(n) {
    if (n === undefined || n === null) return '0';
    return Number(n).toLocaleString('de-DE');
}

function fmtRemaining(expiry) {
    const secs = Math.max(0, expiry - Math.floor(Date.now() / 1000));
    if (secs <= 0) return '<span class="badge badge-temp">Abgelaufen</span>';
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    return h > 0 ? `${h}h ${m}m` : m > 0 ? `${m}m ${s}s` : `${s}s`;
}

function statusBadge(action) {
    if (!action) return 'badge-blocked';
    const a = action.toLowerCase();
    if (a.includes('perm'))   return 'badge-perm';
    if (a.includes('temp'))   return 'badge-temp';
    if (a.includes('subnet')) return 'badge-subnet';
    if (a.includes('warn'))   return 'badge-warn';
    return 'badge-blocked';
}

function flag(cc) {
    if (!cc || cc.length !== 2) return '';
    try {
        return String.fromCodePoint(...[...cc.toUpperCase()].map(c => 0x1F1E0 - 65 + c.charCodeAt(0)));
    } catch(e) { return ''; }
}

function esc(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;')
        .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── FiveM message listener ────────────────────────────────────────────────────
window.addEventListener('message', function(event) {
    const msg = event.data;
    if (!msg || !msg.type) return;

    switch (msg.type) {
        case 'open':
            openDashboard();
            break;
        case 'close':
            document.getElementById('dashboard').classList.add('hidden');
            state.open = false;
            break;
        case 'statsUpdate':
            applyStats(msg.data);
            break;
        case 'banListUpdate':
            renderBanList(msg.data);
            break;
        case 'unbanResult':
            showToast(
                msg.data && msg.data.success ? '✅ Entsperrt' : '❌ Fehler',
                msg.data && msg.data.ip ? msg.data.ip : '',
                msg.data && msg.data.success ? 'success' : 'error'
            );
            setTimeout(() => nuiFetch('getBanList'), 300);
            break;
        case 'queueUpdate':
            if (msg.data && Array.isArray(msg.data.pending)) {
                applyQueue(msg.data.pending);
                // Show toast for new entries
                if (msg.data.type === 'new' && msg.data.pending.length > 0) {
                    const newest = msg.data.pending[msg.data.pending.length - 1];
                    showToast('⏳ Neue Verbindungsanfrage!',
                        (newest.name || 'Spieler') + ' (' + (newest.ip || '?') + ')', 'warn');
                    // Play notification pulse: flash queue badge
                    const badge = document.getElementById('queue-badge');
                    if (badge) {
                        badge.style.animation = 'none';
                        setTimeout(() => badge.style.animation = '', 10);
                    }
                }
            }
            break;
        case 'queueActionResult':
            if (msg.data && !msg.data.success) {
                showToast('❌ Fehler', msg.data.msg || 'Unbekannter Fehler', 'error');
            }
            break;
        case 'whitelistResponse':
            renderWhitelist(msg.data);
            break;
        case 'whitelistActionResult':
            if (msg.data && msg.data.success) {
                showToast(
                    msg.data.action === 'add' ? '✅ Whitelist' : '🗑️ Whitelist',
                    msg.data.action === 'add'
                        ? (msg.data.identifier + ' hinzugefügt')
                        : (msg.data.identifier + ' entfernt'),
                    'success'
                );
                setTimeout(() => nuiFetch('getWhitelist'), 300);
            } else {
                showToast('❌ Fehler', (msg.data && msg.data.msg) || 'Fehler', 'error');
            }
            break;
        case 'logDatesResponse':
            renderLogDates(msg.data && msg.data.dates);
            break;
        case 'logByDateResponse':
            renderLogEntries(msg.data);
            break;
        case 'logRetentionResult':
            if (msg.data && msg.data.success) {
                showToast('📋 Verlängert', msg.data.key + ' + ' + msg.data.extraDays + ' Tage', 'success');
                nuiFetch('getLogDates');
            } else {
                showToast('❌ Fehler', 'Verlängerung fehlgeschlagen', 'error');
            }
            break;
        case 'logExportResponse':
            if (msg.data && msg.data.content) {
                downloadText('kw_log_' + (msg.data.key || 'export') + '.txt', msg.data.content);
                showToast('📥 Export', 'Log-Datei wird heruntergeladen', 'success');
            }
            break;
        default:
            break;
    }
});

// ── Keyboard shortcuts ────────────────────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && state.open) closeDashboard();
    // Number keys: 1-5 switch tabs
    if (state.open && !e.ctrlKey && !e.altKey) {
        const tabs = ['overview','queue','bans','whitelist','log'];
        const n    = parseInt(e.key);
        if (n >= 1 && n <= tabs.length) switchTab(tabs[n-1]);
    }
});

// ── Modal keyboard ────────────────────────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    const modal = document.getElementById('modal-overlay');
    if (!modal || modal.classList.contains('hidden')) return;
    if (e.key === 'Escape')  closeModal();
    if (e.key === 'Enter')   submitAddWhitelist();
});

// ── Init ─────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', function() {
    if (typeof initCharts === 'function') initCharts();
    if (typeof initMap    === 'function') initMap();
});

// ── Log file browser ──────────────────────────────────────────────────────────

let _selectedLogKey = null;

function loadLogDates() {
    nuiFetch('getLogDates');
}

function renderLogDates(dates) {
    const list = document.getElementById('log-file-list');
    if (!list) return;
    if (!dates || dates.length === 0) {
        list.innerHTML = '<div class="log-file-empty">Keine gespeicherten Logs / No stored logs</div>';
        return;
    }
    list.innerHTML = dates.map(d => `
        <div class="log-file-row ${d.locked ? 'log-file-locked' : ''}" onclick="selectLogDate('${d.key}', '${d.date}')">
            <div class="log-file-info">
                <span class="log-file-date">${d.date}</span>
                <span class="log-file-meta">${fmtNum(d.entries)} Einträge · ${fmtSize(d.size)}</span>
                ${d.locked ? '<span class="log-file-lock">🔒 Verlängert</span>' : ''}
            </div>
            <div class="log-file-actions">
                <button class="btn-log-extend" onclick="extendLog(event,'${d.key}')">+5 Tage</button>
                <button class="btn-log-export" onclick="exportLog(event,'${d.key}')">📥 Export</button>
            </div>
        </div>`).join('');
}

function selectLogDate(key, label) {
    _selectedLogKey = key;
    // Highlight selected
    document.querySelectorAll('.log-file-row').forEach(r => r.classList.remove('selected'));
    const row = document.querySelector(`.log-file-row[onclick*="${key}"]`);
    if (row) row.classList.add('selected');
    // Load entries
    nuiFetch('getLogByDate', { key });
    // Update header
    const hdr = document.getElementById('log-entries-header');
    if (hdr) hdr.textContent = '📋 Logs: ' + label;
}

function renderLogEntries(data) {
    const tbody = document.getElementById('log-entries-body');
    if (!tbody) return;
    const entries = (data && data.entries) ? data.entries : [];
    if (entries.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" class="td-empty">Keine Einträge / No entries</td></tr>';
        return;
    }
    tbody.innerHTML = entries.slice(-500).reverse().map(e => `<tr>
        <td class="log-ts">${e.timestamp || '?'}</td>
        <td><span class="badge log-level-${(e.level||'info').toLowerCase()}">${e.level || '?'}</span></td>
        <td class="log-msg">${esc(e.message || '')}</td>
    </tr>`).join('');
}

function extendLog(event, key) {
    event.stopPropagation();
    nuiFetch('extendLogRetention', { key, extraDays: 5 });
}

function exportLog(event, key) {
    event.stopPropagation();
    nuiFetch('exportLog', { key });
}

function downloadText(filename, content) {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

function fmtSize(bytes) {
    if (!bytes) return '0 B';
    if (bytes < 1024)      return bytes + ' B';
    if (bytes < 1048576)   return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
}

