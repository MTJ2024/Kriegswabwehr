/* ═══════════════════════════════════════════════════════════════════════
   Kriegswabwehr – Dashboard App Controller
   Kommuniziert mit FiveM via window.addEventListener('message', ...)
   Kommunicates with FiveM via window.addEventListener('message', ...)
   ═══════════════════════════════════════════════════════════════════════ */

'use strict';

// ── State ────────────────────────────────────────────────────────────────────
const state = {
    open:       false,
    attackLog:  [],   // max 200 entries kept in memory
};

// ── DOM refs (set after DOMContentLoaded) ────────────────────────────────────
let dom = {};

// ── FiveM NUI helper ─────────────────────────────────────────────────────────
function nuiFetch(endpoint, data) {
    return fetch('https://kriegswabwehr/' + endpoint, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(data || {}),
    }).catch(() => {});
}

// ── Open / Close ──────────────────────────────────────────────────────────────
function openDashboard() {
    state.open = true;
    document.getElementById('dashboard').classList.remove('hidden');
    nuiFetch('requestStats');
    nuiFetch('getBanList');
    startClock();
}

function closeDashboard() {
    state.open = false;
    document.getElementById('dashboard').classList.add('hidden');
    nuiFetch('close');
}

// ── Clock ─────────────────────────────────────────────────────────────────────
function startClock() {
    const el = document.getElementById('clock');
    if (!el) return;
    const tick = () => {
        el.textContent = new Date().toLocaleTimeString('de-DE', { hour12: false });
    };
    tick();
    setInterval(tick, 1000);
}

// ── Stats update ──────────────────────────────────────────────────────────────
function applyStats(data) {
    if (!data) return;

    // Tiles
    setText('tile-attempts', fmtNum(data.totalConnAttempts));
    setText('tile-blocked',  fmtNum(data.blockedLastMinute));
    setText('tile-legit',    fmtNum(data.legitimateConns));
    setText('tile-players',  (data.players || 0) + ' / ' + (data.maxPlayers || 32));
    setText('tile-tarpit',   fmtNum((data.tarpitStats && data.tarpitStats.active) || 0));
    setText('tile-permbans', fmtNum((data.banStats && data.banStats.permBans) || 0));

    // Intensity bar
    const pct = Math.min(100, Math.round(data.attackIntensity || 0));
    const bar = document.getElementById('intensity-bar');
    const lbl = document.getElementById('intensity-pct');
    if (bar) bar.style.width = pct + '%';
    if (lbl) lbl.textContent = pct + '%';

    // Header attack state
    const header = document.querySelector('.header');
    const dot    = document.getElementById('status-dot');
    const status = document.getElementById('status-text');
    if (pct >= 50) {
        header && header.classList.add('under-attack');
        dot    && dot.classList.add('attacking');
        if (status) { status.textContent = 'UNTER ANGRIFF / UNDER ATTACK'; status.className = 'attacking'; }
    } else {
        header && header.classList.remove('under-attack');
        dot    && dot.classList.remove('attacking');
        if (status) { status.textContent = 'AKTIV / ACTIVE'; status.className = ''; }
    }

    // Charts
    if (typeof updateCharts === 'function') updateCharts(data);

    // Attack log
    if (Array.isArray(data.attackLog)) {
        renderAttackLog(data.attackLog);
        // Map markers
        if (typeof updateMap === 'function') updateMap(data.attackLog);
    }
}

// ── Attack log table ──────────────────────────────────────────────────────────
function renderAttackLog(entries) {
    const tbody = document.getElementById('attack-log-body');
    if (!tbody) return;

    // Newest first, max 100 rows shown
    const rows = entries.slice().reverse().slice(0, 100);

    if (rows.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="empty">Keine Angriffe erkannt / No attacks detected</td></tr>';
        return;
    }

    // Only re-render if there are new entries (compare first entry)
    const firstKey = rows[0] && (rows[0].timestamp + rows[0].ip);
    if (tbody.dataset.firstKey === firstKey) return;
    tbody.dataset.firstKey = firstKey;

    tbody.innerHTML = rows.map((e, idx) => {
        const badgeClass = statusBadge(e.action || e.status);
        const countryFlag = e.country ? countryToFlag(e.country) : '';
        return `<tr class="${idx === 0 ? 'row-new' : ''}">
            <td>${e.timestamp || ''}</td>
            <td>${e.ip || '?'}</td>
            <td>${countryFlag} ${e.country || '?'}</td>
            <td>${e.isp || '?'}</td>
            <td>${e.attackType || e.type || '?'}</td>
            <td><span class="badge ${badgeClass}">${(e.action || e.status || 'BLOCKED').toUpperCase()}</span></td>
        </tr>`;
    }).join('');
}

function statusBadge(action) {
    if (!action) return 'badge-blocked';
    const a = action.toLowerCase();
    if (a.includes('perm'))    return 'badge-perm';
    if (a.includes('temp'))    return 'badge-temp';
    if (a.includes('subnet'))  return 'badge-subnet';
    if (a.includes('warn'))    return 'badge-warn';
    return 'badge-blocked';
}

// Simple country code to emoji flag
function countryToFlag(cc) {
    if (!cc || cc.length !== 2) return '';
    try {
        return String.fromCodePoint(...[...cc.toUpperCase()].map(c => 0x1F1E0 - 65 + c.charCodeAt(0)));
    } catch(e) { return ''; }
}

// ── Ban list ──────────────────────────────────────────────────────────────────
function fetchBanList() {
    nuiFetch('getBanList');
}

function renderBanList(data) {
    const tbody = document.getElementById('ban-list-body');
    if (!tbody) return;

    const bans = data && data.bans ? data.bans : [];
    if (bans.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="empty">Keine gesperrten IPs / No banned IPs</td></tr>';
        return;
    }

    tbody.innerHTML = bans.map(b => {
        const badgeClass = b.type === 'perm' ? 'badge-perm' : 'badge-temp';
        const remaining = b.expiry ? fmtRemaining(b.expiry) : 'Permanent';
        return `<tr>
            <td>${b.ip || '?'}</td>
            <td><span class="badge ${badgeClass}">${(b.type || 'perm').toUpperCase()}</span></td>
            <td>${b.reason || '?'}</td>
            <td>${b.attackType || '?'}</td>
            <td>${remaining}</td>
            <td><button class="btn-unban" onclick="unbanIP('${b.ip}')">Entsperren / Unban</button></td>
        </tr>`;
    }).join('');
}

function unbanIP(ip) {
    if (!ip) return;
    nuiFetch('unbanIP', { ip });
    showToast('IP entsperrt / Unbanned', ip, 'info');
    setTimeout(fetchBanList, 500);
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
    if (secs <= 0) return 'Abgelaufen / Expired';
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    return h > 0 ? `${h}h ${m}m` : m > 0 ? `${m}m ${s}s` : `${s}s`;
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
            if (msg.data && msg.data.success) {
                showToast('Entsperrt / Unbanned', msg.data.ip, 'info');
            } else {
                showToast('Fehler / Error', 'IP nicht gefunden / IP not found', 'error');
            }
            fetchBanList();
            break;
        default:
            break;
    }
});

// ── ESC key ───────────────────────────────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && state.open) closeDashboard();
});

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', function() {
    // Init charts when Chart.js is available
    if (typeof initCharts === 'function') initCharts();
    // Init map when available
    if (typeof initMap === 'function') initMap();
});
