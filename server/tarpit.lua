-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Tarpit / Verbindungs-Verlangsamer
-- ═══════════════════════════════════════════════════════════════════════════
-- LEGAL: Wir verlangsamen NUR eingehende Verbindungen auf unserem eigenen
--        Server. Kein aktiver Angriff. Passiver Ressourcen-Erschöpfer.
-- LEGAL: We only slow down incoming connections on OUR OWN server.
--        No active attack. Passive resource exhaustion.
-- ─────────────────────────────────────────────────────────────────────────────
-- Wirkung: Angreifer-Bots müssen ihre Verbindungs-Threads offen halten,
--          während wir sie mit Fake-Status-Meldungen beschäftigen.
--          Bei 1000 parallelen Bot-Verbindungen à 30s = Angreifer erschöpft
--          seinen eigenen Threadpool, nicht unseren.
-- Effect:  Attacker bots must keep their connection threads open while we
--          keep them busy with fake status messages.
--          1000 parallel bot connections × 30s = attacker exhausts HIS OWN
--          thread pool, not ours.
-- ═══════════════════════════════════════════════════════════════════════════

Tarpit = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Fake-Prüfnachrichten (erscheinen im FiveM-Ladebildschirm des Angreifers)
-- Fake check messages (appear in the attacker's FiveM loading screen)
-- ─────────────────────────────────────────────────────────────────────────────
local FAKE_MESSAGES = {
    "🔍 Überprüfe Spielerdaten...",
    "🔍 Checking player data...",
    "📡 Verbinde mit Datenbankserver...",
    "📡 Connecting to database server...",
    "🛡️ Führe Sicherheitsprüfung durch...",
    "🛡️ Running security scan...",
    "📋 Lade Spielerprofil...",
    "📋 Loading player profile...",
    "⚙️ Synchronisiere Server-Daten...",
    "⚙️ Synchronizing server data...",
    "🔐 Verifiziere Lizenzschlüssel...",
    "🔐 Verifying license key...",
    "📊 Prüfe Spielerverlauf...",
    "📊 Checking player history...",
    "🌐 Geo-Verifikation läuft...",
    "🌐 Geo-verification in progress...",
    "⏳ Fast fertig...",
    "⏳ Almost done...",
    "🔄 Synchronisiere...",
    "🔄 Synchronizing...",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Tarpit-Konfiguration / Tarpit configuration
-- ─────────────────────────────────────────────────────────────────────────────
-- Verzögerungsstufen nach Verstoßanzahl / Delay levels by violation count
local DELAY_LEVELS = {
    [1] = 8000,    -- 8 Sekunden  – erste Auffälligkeit
    [2] = 20000,   -- 20 Sekunden – zweite Auffälligkeit
    [3] = 45000,   -- 45 Sekunden – Wiederholungstäter
}

-- Maximale Tarpit-Dauer / Maximum tarpit duration
local MAX_TARPIT_MS = Config.Tarpit and Config.Tarpit.maxDurationMs or 45000

-- ─────────────────────────────────────────────────────────────────────────────
-- Aktive Tarpits (zur Übersicht) / Active tarpits (for overview)
-- ─────────────────────────────────────────────────────────────────────────────
local activeTarpits = {}
local tarpitStats   = { total = 0, currentActive = 0, totalMsWasted = 0 }

-- ─────────────────────────────────────────────────────────────────────────────
-- Haupt-Tarpit-Funktion / Main tarpit function
-- ─────────────────────────────────────────────────────────────────────────────

-- Hält eine Verbindung in einer Fake-Schleife und gibt erst dann false zurück.
-- Holds a connection in a fake loop, then returns false to block it.
--
-- Verwendung innerhalb eines playerConnecting-Handlers (deferrals):
-- Usage inside a playerConnecting handler (deferrals):
--   Tarpit.hold(ip, violations, deferrals, function()
--       deferrals.done("🚫 Geblockt")
--   end)
--
function Tarpit.hold(ip, violations, deferrals, onDone)
    local level     = math.min(violations, 3)
    local delayMs   = DELAY_LEVELS[level] or DELAY_LEVELS[1]
    delayMs         = math.min(delayMs, MAX_TARPIT_MS)

    local startedAt = os.time()
    activeTarpits[ip]            = { start = startedAt, level = level, delayMs = delayMs }
    tarpitStats.total            = tarpitStats.total + 1
    tarpitStats.currentActive    = tarpitStats.currentActive + 1

    Logger.warn(string.format(
        "[TARPIT] IP=%s Level=%d Verzögerung=%dms / Delay=%dms",
        ip, level, delayMs, delayMs
    ))

    -- Fake-Nachrichten alle 2 Sekunden senden / Send fake messages every 2s
    local elapsed   = 0
    -- Starte immer bei Nachricht 1 für konsistente Sprache / Always start at msg 1 for consistent language
    local msgIndex  = 1

    CreateThread(function()
        while elapsed < delayMs do
            local msg = FAKE_MESSAGES[msgIndex]
            -- Fortschrittsbalken simulieren / Simulate progress bar
            local pct    = math.floor((elapsed / delayMs) * 100)
            local bars   = math.floor(pct / 5)
            local bar    = string.rep("█", bars) .. string.rep("░", 20 - bars)
            local status = string.format("🛡️ %s\n[%s] %d%%", msg, bar, pct)
            deferrals.update(status)

            Wait(2000)
            elapsed  = elapsed + 2000
            msgIndex = (msgIndex % #FAKE_MESSAGES) + 1
        end

        -- Tarpit abgeschlossen / Tarpit complete
        local wastedSec = os.time() - startedAt
        tarpitStats.totalMsWasted   = tarpitStats.totalMsWasted + (wastedSec * 1000)
        tarpitStats.currentActive   = math.max(0, tarpitStats.currentActive - 1)
        activeTarpits[ip]           = nil

        Logger.info(string.format(
            "[TARPIT] Abgeschlossen: IP=%s ~%ds Ressourcen verschwendet / Wasted ~%ds of attacker resources",
            ip, wastedSec, wastedSec
        ))

        onDone()
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Statistiken / Statistics
-- ─────────────────────────────────────────────────────────────────────────────
function Tarpit.getStats()
    return {
        total         = tarpitStats.total,
        currentActive = tarpitStats.currentActive,
        totalMsWasted = tarpitStats.totalMsWasted,
        active        = tarpitStats.currentActive,  -- Zahl fuer Dashboard-Kachel / number for dashboard tile
    }
end

Logger.info("Tarpit initialisiert / Tarpit initialized")
