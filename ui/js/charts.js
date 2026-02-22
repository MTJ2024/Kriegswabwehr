/* ═══════════════════════════════════════════════════════════════════
   Kriegswabwehr – Chart.js Live-Graphen / Live graphs
   ═══════════════════════════════════════════════════════════════════ */

'use strict';

// ── Chart-Instanz / Chart instance ──────────────────────────────────
let connChart = null;

// ── Rollende Datenpunkte / Rolling data points (max 60) ─────────────
const MAX_POINTS  = 60;
const chartLabels = [];
const connData    = [];   // Verbindungen/s
const blockData   = [];   // Geblockte/s

// ── Farben / Colors ──────────────────────────────────────────────────
const COLOR_CONN  = 'rgba(10, 132, 255, 0.85)';
const COLOR_BLOCK = 'rgba(255, 59, 48, 0.85)';
const COLOR_GRID  = 'rgba(30, 37, 48, 1)';
const COLOR_TEXT  = 'rgba(139, 148, 158, 1)';

// ── Initialisierung / Initialize ─────────────────────────────────────
function initCharts() {
  const ctx = document.getElementById('chart-conns');
  if (!ctx || typeof Chart === 'undefined') return;

  // Leere Startdaten / Empty initial data
  for (let i = 0; i < MAX_POINTS; i++) {
    chartLabels.push('');
    connData.push(0);
    blockData.push(0);
  }

  connChart = new Chart(ctx.getContext('2d'), {
    type: 'line',
    data: {
      labels: chartLabels,
      datasets: [
        {
          label: 'Verbindungen/s',
          data: connData,
          borderColor: COLOR_CONN,
          backgroundColor: 'rgba(10,132,255,0.08)',
          borderWidth: 2,
          pointRadius: 0,
          fill: true,
          tension: 0.4,
        },
        {
          label: 'Geblockt/s',
          data: blockData,
          borderColor: COLOR_BLOCK,
          backgroundColor: 'rgba(255,59,48,0.08)',
          borderWidth: 2,
          pointRadius: 0,
          fill: true,
          tension: 0.4,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      animation: { duration: 300 },
      plugins: {
        legend: {
          labels: { color: COLOR_TEXT, font: { family: 'Courier New', size: 11 } },
        },
        tooltip: {
          backgroundColor: '#141820',
          borderColor: '#1e2530',
          borderWidth: 1,
          titleColor: '#e6edf3',
          bodyColor: '#8b949e',
        },
      },
      scales: {
        x: {
          grid:   { color: COLOR_GRID },
          ticks:  { display: false },
        },
        y: {
          min:   0,
          grid:  { color: COLOR_GRID },
          ticks: { color: COLOR_TEXT, font: { size: 10 }, maxTicksLimit: 5 },
        },
      },
    },
  });
}

// ── Graphen mit neuen Daten aktualisieren / Update charts with new data
function updateCharts(stats) {
  if (!connChart) return;

  const now = new Date().toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  // Alten Wert vorne rausschieben, neuen Wert hinten anfügen
  // Shift old value off front, push new value onto back
  chartLabels.shift(); chartLabels.push(now);

  // Verbindungen/s aus Zeitreihe berechnen / Derive conn/s from time series
  const cps   = (stats.connsPerSecond && stats.connsPerSecond.length > 0)
                  ? stats.connsPerSecond[stats.connsPerSecond.length - 1].v || 0
                  : 0;
  const bps   = stats.blockedLastMinute > 0
                  ? Math.ceil(stats.blockedLastMinute / 60)
                  : 0;

  connData.shift();  connData.push(cps);
  blockData.shift(); blockData.push(bps);

  connChart.update('none');   // 'none' = kein Animations-Reset / no animation reset
}
