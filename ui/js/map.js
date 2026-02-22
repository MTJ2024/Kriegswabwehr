/* ═══════════════════════════════════════════════════════════════════════
   Kriegswabwehr – Canvas World Map (Angriffskarte / Attack Map)
   Zeichnet eine vereinfachte Weltkarte auf einem Canvas und platziert
   Angriffs-Marker basierend auf Laengengrad/Breitengrad.
   Draws a simplified world map on canvas and places attack markers
   based on longitude/latitude data from ip-api responses.
   ═══════════════════════════════════════════════════════════════════════ */

'use strict';

// ── Map state ─────────────────────────────────────────────────────────────────
let mapCanvas  = null;
let mapCtx     = null;
let mapMarkers = [];   // { lat, lon, ip, country, type, ts }
const MAX_MARKERS = 80;

// ── Country centroids (lat, lon) for approximate marker placement ─────────────
// ISO 3166-1 Alpha-2 -> [lat, lon]
const COUNTRY_COORDS = {
    AF:[ 33.0, 65.0], AL:[ 41.0, 20.0], DZ:[ 28.0,  3.0], AR:[-34.0,-64.0],
    AM:[ 40.0, 45.0], AU:[-27.0,133.0], AT:[ 47.5, 14.0], AZ:[ 40.5, 47.5],
    BA:[ 44.0, 17.0], BD:[ 24.0, 90.0], BE:[ 50.8,  4.0], BG:[ 43.0, 25.0],
    BO:[-17.0,-65.0], BR:[-10.0,-55.0], BY:[ 53.0, 28.0], CA:[ 60.0,-95.0],
    CH:[ 47.0,  8.0], CL:[-30.0,-71.0], CN:[ 35.0,105.0], CO:[  4.0,-72.0],
    CZ:[ 50.0, 15.5], DE:[ 51.0, 10.0], DK:[ 56.0, 10.0], EC:[ -2.0,-77.5],
    EE:[ 59.0, 25.0], EG:[ 27.0, 30.0], ES:[ 40.0, -4.0], FI:[ 64.0, 26.0],
    FR:[ 46.0,  2.0], GB:[ 54.0, -2.0], GE:[ 42.0, 43.5], GR:[ 39.0, 22.0],
    HK:[ 22.4,114.1], HU:[ 47.0, 20.0], ID:[ -5.0,120.0], IE:[ 53.0, -8.0],
    IL:[ 31.5, 34.8], IN:[ 20.0, 77.0], IQ:[ 33.0, 44.0], IR:[ 32.0, 53.0],
    IT:[ 42.5, 12.5], JP:[ 36.0,138.0], KR:[ 37.0,127.5], KZ:[ 48.0, 68.0],
    LT:[ 56.0, 24.0], LV:[ 57.0, 25.0], MA:[ 32.0, -5.0], MD:[ 47.0, 29.0],
    MK:[ 41.8, 22.0], MX:[ 23.0,-102.0],MY:[  4.0,109.5], NL:[ 52.3,  5.3],
    NO:[ 62.0,  8.0], NZ:[-41.0,174.0], PE:[-10.0,-76.0], PH:[ 13.0,122.0],
    PK:[ 30.0, 70.0], PL:[ 52.0, 20.0], PT:[ 39.5, -8.0], RO:[ 46.0, 25.0],
    RS:[ 44.0, 21.0], RU:[ 60.0, 90.0], SA:[ 25.0, 45.0], SE:[ 62.0, 15.0],
    SG:[  1.4,103.8], SI:[ 46.1, 14.8], SK:[ 48.7, 19.5], TH:[ 15.0,100.0],
    TN:[ 34.0,  9.0], TR:[ 39.0, 35.0], TW:[ 23.7,121.0], UA:[ 49.0, 32.0],
    US:[ 38.0,-97.0], UZ:[ 41.0, 64.0], VE:[  8.0,-66.0], VN:[ 16.0,106.0],
    ZA:[-29.0, 25.0], XX:[  0.0,  0.0],
};

// ── Init ──────────────────────────────────────────────────────────────────────
function initMap() {
    mapCanvas = document.getElementById('map-canvas');
    if (!mapCanvas) return;
    mapCtx = mapCanvas.getContext('2d');
    drawMap();
}

// ── Project lat/lon to canvas coords (equirectangular) ───────────────────────
function project(lat, lon, w, h) {
    const x = ((lon + 180) / 360) * w;
    const y = ((90 - lat) / 180) * h;
    return { x, y };
}

// ── Draw base map ──────────────────────────────────────────────────────────────
function drawMap() {
    if (!mapCtx) return;
    const W = mapCanvas.width;
    const H = mapCanvas.height;

    // Background
    mapCtx.fillStyle = '#0a1020';
    mapCtx.fillRect(0, 0, W, H);

    // Grid lines
    mapCtx.strokeStyle = 'rgba(30, 55, 80, 0.5)';
    mapCtx.lineWidth = 0.5;
    for (let lon = -180; lon <= 180; lon += 30) {
        const { x } = project(0, lon, W, H);
        mapCtx.beginPath();
        mapCtx.moveTo(x, 0);
        mapCtx.lineTo(x, H);
        mapCtx.stroke();
    }
    for (let lat = -90; lat <= 90; lat += 30) {
        const { y } = project(lat, 0, W, H);
        mapCtx.beginPath();
        mapCtx.moveTo(0, y);
        mapCtx.lineTo(W, y);
        mapCtx.stroke();
    }

    // Equator and prime meridian highlights
    mapCtx.strokeStyle = 'rgba(30, 80, 100, 0.6)';
    mapCtx.lineWidth = 0.8;
    const eq = project(0, 0, W, H);
    mapCtx.beginPath(); mapCtx.moveTo(0, eq.y); mapCtx.lineTo(W, eq.y); mapCtx.stroke();
    mapCtx.beginPath(); mapCtx.moveTo(eq.x, 0); mapCtx.lineTo(eq.x, H); mapCtx.stroke();

    // Country dots (approximate centroids)
    mapCtx.fillStyle = 'rgba(40, 80, 120, 0.6)';
    for (const [cc, [lat, lon]] of Object.entries(COUNTRY_COORDS)) {
        if (cc === 'XX') continue;
        const { x, y } = project(lat, lon, W, H);
        mapCtx.beginPath();
        mapCtx.arc(x, y, 2, 0, Math.PI * 2);
        mapCtx.fill();
    }

    // Draw markers
    drawMarkers(W, H);
}

// ── Draw attack markers ────────────────────────────────────────────────────────
function drawMarkers(W, H) {
    if (!mapCtx) return;
    const now = Date.now();

    for (const m of mapMarkers) {
        // Fade out over 120 seconds
        const age     = (now - m.ts) / 1000;
        const opacity = Math.max(0, 1 - age / 120);
        if (opacity <= 0) continue;

        let lat = m.lat;
        let lon = m.lon;
        // Fall back to country centroid if no coords
        if ((lat === undefined || lat === null) && m.country) {
            const coord = COUNTRY_COORDS[m.country.toUpperCase()];
            if (coord) { lat = coord[0]; lon = coord[1]; }
        }
        if (lat === undefined || lat === null) continue;

        const { x, y } = project(lat, lon, W, H);
        const color = m.type === 'perm' ? `rgba(255,59,48,${opacity})` :
                      m.type === 'temp' ? `rgba(255,149,0,${opacity})` :
                                          `rgba(255,59,48,${opacity})`;

        // Pulsing outer ring
        const pulse = 3 + 2 * Math.sin((now / 400) + m.ts);
        mapCtx.beginPath();
        mapCtx.arc(x, y, pulse + 3, 0, Math.PI * 2);
        mapCtx.strokeStyle = color.replace(/[\d.]+\)$/, (opacity * 0.4) + ')');
        mapCtx.lineWidth = 1;
        mapCtx.stroke();

        // Inner dot
        mapCtx.beginPath();
        mapCtx.arc(x, y, 3, 0, Math.PI * 2);
        mapCtx.fillStyle = color;
        mapCtx.fill();
    }
}

// ── Update map with new attack log data ───────────────────────────────────────
function updateMap(attackLog) {
    if (!mapCtx || !Array.isArray(attackLog)) return;

    // Merge new entries into mapMarkers
    for (const entry of attackLog) {
        // Check if already in list by ip+timestamp
        const key = (entry.ip || '') + (entry.timestamp || '');
        if (mapMarkers.some(m => m._key === key)) continue;

        mapMarkers.push({
            _key:    key,
            ip:      entry.ip      || '',
            country: entry.country || 'XX',
            isp:     entry.isp     || '',
            type:    entry.action  || 'blocked',
            lat:     entry.lat     !== undefined ? entry.lat : null,
            lon:     entry.lon     !== undefined ? entry.lon : null,
            ts:      Date.now(),
        });
    }

    // Keep max markers
    if (mapMarkers.length > MAX_MARKERS) {
        mapMarkers.splice(0, mapMarkers.length - MAX_MARKERS);
    }
}

// ── Animate map ───────────────────────────────────────────────────────────────
(function animateMap() {
    requestAnimationFrame(animateMap);
    if (!mapCtx) return;
    drawMap();
})();
