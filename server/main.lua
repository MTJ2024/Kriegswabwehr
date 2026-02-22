-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Hauptmodul / Main Module
-- ═══════════════════════════════════════════════════════════════════════════
-- playerConnecting-Hook, Eskalations-Engine, Dashboard-API
-- playerConnecting hook, escalation engine, dashboard API
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- Angriffsstatistiken / Attack statistics
-- ─────────────────────────────────────────────────────────────────────────────

local stats = {
    totalConnAttempts   = 0,
    blockedLastMinute   = 0,
    blockedTotal        = 0,
    legitimateConns     = 0,
    attackIntensity     = 0,    -- 0–100 %
    blockedPerMinute    = {},   -- Zeitreihe / Time series
    connsPerSecond      = {},
    attackLog           = {},   -- Letzte Angriffe / Recent attacks
}

-- Helfer: Zeitreihe aktualisieren (gleitende 60-Sekunden-Fenster)
-- Helper: update time series (rolling 60-second windows)
local function pushTimeSeries(series, value)
    table.insert(series, { t = os.time(), v = value })
    -- Nur letzte 60 Einträge behalten / Keep only last 60 entries
    while #series > 60 do table.remove(series, 1) end
end

-- Angriffsintensität berechnen (0–100)
-- Calculate attack intensity (0–100)
local function calcIntensity()
    local blocked  = stats.blockedLastMinute
    local legit    = stats.legitimateConns
    local total    = blocked + legit
    if total == 0 then return 0 end
    return math.min(100, math.floor((blocked / total) * 100))
end

-- Angriffseintrag hinzufügen / Add attack log entry
local function logAttack(ip, country, isp, attackType, status)
    table.insert(stats.attackLog, 1, {
        time       = os.date("%H:%M:%S"),
        ip         = ip,
        country    = country or "XX",
        isp        = isp or "Unknown",
        attackType = attackType or "Connection Flood",
        status     = status or "BLOCKED",
        timestamp  = os.time(),
    })
    -- Maximal 200 Einträge / Maximum 200 entries
    if #stats.attackLog > 200 then
        table.remove(stats.attackLog)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Eskalations-Engine / Escalation Engine
-- ─────────────────────────────────────────────────────────────────────────────

-- Bestimmt und führt die Eskalationsstufe aus
-- Determines and executes the escalation level
local function escalate(ip, geoData)
    local violations = RateLimiter.getViolations(ip)
    local level      = math.min(violations, 3)
    local cfg        = Config.Escalation[level]
    if not cfg then return end

    local geoInfo = geoData or {}

    local alertData = {
        ip              = ip,
        country         = geoInfo.country or "XX",
        isp             = geoInfo.isp or "Unknown",
        attackType      = "Connection Flood",
        escalationLevel = level,
        action          = cfg.action,
        reason          = cfg.message,
    }

    if cfg.action == "warn" then
        -- Stufe 1: Nur warnen und protokollieren / Level 1: Warn and log only
        Logger.alertAttack(alertData)

    elseif cfg.action == "tempban" then
        -- Stufe 2: Temporäre Sperre / Level 2: Temporary ban
        IPBlocker.tempBan(ip, cfg.message, cfg.duration or Config.TempBanDuration, "Connection Flood")
        Logger.alertAttack(alertData)

    elseif cfg.action == "permban" then
        -- Stufe 3: Permanente Sperre + Subnetzblockierung + Discord
        IPBlocker.permBan(ip, cfg.message, "Connection Flood")
        if cfg.subnetBlock then
            IPBlocker.blockSubnet(ip, "Wiederholter DDoS-Angriff / Repeated DDoS attack")
        end
        if cfg.discordAlert then
            Logger.alertAttack(alertData)
        end
    end

    stats.blockedTotal        = stats.blockedTotal + 1
    stats.blockedLastMinute   = stats.blockedLastMinute + 1
    stats.attackIntensity     = calcIntensity()

    logAttack(ip, geoInfo.country, geoInfo.isp, "Connection Flood", cfg.action:upper())
end

-- ─────────────────────────────────────────────────────────────────────────────
-- playerConnecting – Erste Verteidigungslinie / First line of defense
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local source  = source
    local rawIP   = GetPlayerEndpoint(source) or ""
    local ip      = rawIP:match("^([^:]+)") or rawIP

    stats.totalConnAttempts = stats.totalConnAttempts + 1
    pushTimeSeries(stats.connsPerSecond, 1)

    -- Sofort deferrieren / Defer immediately
    deferrals.defer()
    Wait(0)

    deferrals.update("🛡️ Kriegswabwehr: Verbindung wird geprüft...")
    Wait(50)

    -- ── Schritt 1: IP-Sperre prüfen / Step 1: Check IP ban ──────────────────
    local banCheck = IPBlocker.isBlocked(ip)
    if banCheck.blocked then
        stats.blockedTotal      = stats.blockedTotal + 1
        stats.blockedLastMinute = stats.blockedLastMinute + 1
        logAttack(ip, nil, nil, "Banned IP", "BLOCKED")
        deferrals.done("🚫 Zugang verweigert: " .. banCheck.reason)
        return
    end

    -- ── Schritt 2: Identifier-Sperre prüfen / Step 2: Check identifier ban ──
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers or {}) do
        local idBlocked, idReason = IPBlocker.isIdentifierBlocked(id)
        if idBlocked then
            stats.blockedTotal      = stats.blockedTotal + 1
            stats.blockedLastMinute = stats.blockedLastMinute + 1
            deferrals.done("🚫 Zugang verweigert (ID): " .. (idReason or "Banned"))
            return
        end
    end

    -- ── Schritt 3: Steam-Token-Prüfung / Step 3: Steam token check ──────────
    if Config.AttackSignatures.requireSteamToken and not AntiTheft.validateSteamToken(source) then
        stats.blockedTotal      = stats.blockedTotal + 1
        stats.blockedLastMinute = stats.blockedLastMinute + 1
        logAttack(ip, nil, nil, "No Steam Token", "BLOCKED")
        deferrals.done("🚫 Kein gültiges Steam-Token erkannt / No valid Steam token detected.")
        return
    end

    -- ── Schritt 4: Simultane Verbindungslimits / Step 4: Simultaneous limits ─
    local simCheck = RateLimiter.checkSimultaneous(ip)
    if not simCheck.allowed then
        escalate(ip, nil)
        logAttack(ip, nil, nil, "Simultaneous Connection Limit", "BLOCKED")
        deferrals.done("🚫 Verbindungslimit erreicht / Connection limit reached.")
        return
    end

    -- ── Schritt 5: Rate-Limiting / Step 5: Rate limiting ────────────────────
    local rateCheck = RateLimiter.checkConnectionRate(ip)
    if not rateCheck.allowed then
        -- Geo-IP im Hintergrund abrufen und eskalieren
        -- Fetch Geo-IP in background and escalate
        IPBlocker.checkGeoIP(ip, function(geoData)
            escalate(ip, geoData)
        end)
        deferrals.done("🚫 Rate-Limit überschritten / Rate limit exceeded. Bitte warte kurz.")
        return
    end

    -- ── Schritt 6: Geo-IP-Prüfung / Step 6: Geo IP check ───────────────────
    RateLimiter.registerConnection(ip)

    IPBlocker.checkGeoIP(ip, function(geoData)
        if geoData.blocked then
            RateLimiter.deregisterConnection(ip)
            stats.blockedTotal      = stats.blockedTotal + 1
            stats.blockedLastMinute = stats.blockedLastMinute + 1
            logAttack(ip, geoData.country, geoData.isp, geoData.reason or "Geo-Block", "BLOCKED")
            Logger.alertAttack({
                ip              = ip,
                country         = geoData.country,
                isp             = geoData.isp,
                attackType      = "Geo-Block",
                escalationLevel = 1,
                action          = "permban",
                reason          = geoData.reason,
            })
            deferrals.done("🚫 Zugang verweigert: " .. (geoData.reason or "Geo-blocked"))
        else
            -- Verbindung erlaubt / Connection allowed
            stats.legitimateConns = stats.legitimateConns + 1
            stats.attackIntensity = calcIntensity()
            Logger.info(string.format(
                "[CONNECT] Erlaubt: %s (%s) IP=%s Land=%s ISP=%s",
                name, tostring(source), ip,
                geoData.country or "XX", geoData.isp or "?"
            ))
            deferrals.done()
        end
    end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- playerDropped – Verbindung abmelden / playerDropped – deregister connection
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler("playerDropped", function(reason)
    local source = source
    local rawIP  = GetPlayerEndpoint(source) or ""
    local ip     = rawIP:match("^([^:]+)") or rawIP

    RateLimiter.deregisterConnection(ip)
    RateLimiter.cleanupPlayer(source)

    Logger.debug(string.format("[DISCONNECT] Spieler %s (IP=%s) getrennt: %s", tostring(source), ip, reason))
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Dashboard-API über Netz-Events / Dashboard API via net events
-- ─────────────────────────────────────────────────────────────────────────────

-- Statistiken an Admin-Dashboard senden / Send statistics to admin dashboard
RegisterNetEvent("kriegswabwehr:requestStats", function()
    local source = source
    if not AntiTheft.isAdmin(source) then return end

    local payload = {
        totalConnAttempts = stats.totalConnAttempts,
        blockedLastMinute = stats.blockedLastMinute,
        legitimateConns   = stats.legitimateConns,
        blockedTotal      = stats.blockedTotal,
        attackIntensity   = stats.attackIntensity,
        connsPerSecond    = stats.connsPerSecond,
        attackLog         = stats.attackLog,
        banStats          = IPBlocker.getStats(),
        rateLimitStats    = RateLimiter.getStats(),
        players           = GetNumPlayers(),
        maxPlayers        = GetConvarInt("sv_maxclients", 32),
    }

    TriggerClientEvent("kriegswabwehr:statsResponse", source, payload)
end)

-- Ban-Liste abrufen / Retrieve ban list
RegisterNetEvent("kriegswabwehr:getBanList", function()
    local source = source
    if not AntiTheft.isAdmin(source) then return end
    TriggerClientEvent("kriegswabwehr:banListResponse", source, {
        bans    = IPBlocker.getBanList(),
        subnets = IPBlocker.getSubnetList(),
    })
end)

-- IP entsperren / Unban IP
RegisterNetEvent("kriegswabwehr:unbanIP", function(ip)
    local source = source
    if not AntiTheft.isAdmin(source) then return end
    local success = IPBlocker.unban(ip)
    Logger.adminAction(source, "UNBAN", ip, success and "Erfolgreich" or "IP nicht gefunden")
    TriggerClientEvent("kriegswabwehr:unbanResult", source, { success = success, ip = ip })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Periodisches Zurücksetzen der Minuten-Statistik
-- Periodic reset of per-minute statistics
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(60000)  -- Jede Minute / Every minute
        pushTimeSeries(stats.blockedPerMinute, stats.blockedLastMinute)
        stats.blockedLastMinute = 0
        stats.attackIntensity   = calcIntensity()
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin-Dashboard NUI öffnen / Open admin dashboard NUI
-- ─────────────────────────────────────────────────────────────────────────────

RegisterCommand("kwdashboard", function(source, args, raw)
    if source == 0 then
        -- Server-Konsole / Server console
        Logger.info("Dashboard-Befehl von Serverkonsole ausgeführt")
        return
    end
    if not AntiTheft.isAdmin(source) then
        TriggerClientEvent("chat:addMessage", source, {
            color   = {255, 50, 50},
            args    = {"[KW]", "Keine Berechtigung / No permission."},
        })
        return
    end
    TriggerClientEvent("kriegswabwehr:openDashboard", source)
end, false)

Logger.info("Kriegswabwehr Hauptmodul gestartet / Kriegswabwehr main module started")
Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
Logger.info("  🛡️  KRIEGSWABWEHR – DDoS-Schutzschild aktiv / Active  ")
Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
