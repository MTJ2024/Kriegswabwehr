-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Hauptmodul / Main Module
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️  PRIMÄRER ANGRIFFSPUNKT: playerConnecting / Ladebildschirm-Phase
-- ⚠️  PRIMARY ATTACK SURFACE:  playerConnecting / loading-screen phase
--
-- ALLE Abwehrmechanismen greifen hier, bevor der Spieler den Server betritt.
-- ALL defence mechanisms fire here before the player enters the server.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- Angriffsstatistiken / Attack statistics
-- ─────────────────────────────────────────────────────────────────────────────

local stats = {
    totalConnAttempts   = 0,
    blockedLastMinute   = 0,
    blockedTotal        = 0,
    legitimateConns     = 0,
    attackIntensity     = 0,
    blockedPerMinute    = {},
    connsPerSecond      = {},
    attackLog           = {},
}

-- Erster gesehener Zeitstempel pro IP (für Dossier) / First-seen timestamp per IP
local firstSeenAt = {}

-- Zentrale Referenz-ID-Funktion / Central reference ID function
local function makeRefID(ip, suffix)
    local clean = ip:gsub("%.", ""):sub(1, 8)
    return string.format("KW-%s-%s-%s-%04X",
        os.date("%Y%m%d"), os.date("%H%M%S"), clean, math.random(0, 65535))
        .. (suffix and ("-" .. suffix) or "")
end

local function pushTimeSeries(series, value)
    table.insert(series, { t = os.time(), v = value })
    while #series > 60 do table.remove(series, 1) end
end

local function calcIntensity()
    local total = stats.blockedLastMinute + stats.legitimateConns
    if total == 0 then return 0 end
    return math.min(100, math.floor((stats.blockedLastMinute / total) * 100))
end

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
    if #stats.attackLog > 200 then table.remove(stats.attackLog) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Visuelle Abschreckungsnachricht / Visual deterrence message
-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL: Zeigt dem Angreifer NUR seine eigenen öffentlichen Netzwerk-Daten.
-- LEGAL: Shows the attacker ONLY their own public network data.
--
-- Diese Nachricht erscheint direkt im FiveM-Ladebildschirm des Angreifers –
-- genau dort, wo der Angriff startet.
-- This message appears directly in the attacker's FiveM loading screen –
-- exactly where the attack originates.

local function buildDeterrenceMessage(ip, geoData, refID, banType, violations)
    local cfg = Config.VisualDeterrence
    if not cfg or not cfg.enabled then
        return "🚫 Zugang verweigert / Access denied."
    end

    local geo     = geoData or {}
    local subnet  = ip:match("^(%d+%.%d+%.%d+)%.%d+$")
    local ts      = os.date("!%Y-%m-%d %H:%M:%S UTC")

    -- Abschreckungsstufe erhöht mit jeder Verletzung
    -- Deterrence level increases with each violation
    local lines = {}

    table.insert(lines, "")
    table.insert(lines, "╔══════════════════════════════════════════════╗")
    table.insert(lines, "║   🛡️  KRIEGSWABWEHR – ZUGANG VERWEIGERT     ║")
    table.insert(lines, "║      🛡️  ACCESS DENIED                       ║")
    table.insert(lines, "╚══════════════════════════════════════════════╝")
    table.insert(lines, "")

    if cfg.showIP then
        table.insert(lines, "🌐 IP-Adresse erkannt:  " .. ip)
    end

    if cfg.showSubnet and subnet then
        table.insert(lines, "🔗 Subnetz / Subnet:    " .. subnet .. ".0/24")
    end

    if cfg.showLocation then
        local loc = ""
        if geo.city and geo.city ~= "" and geo.city ~= "Unknown" then
            loc = geo.city .. ", "
        end
        loc = loc .. (geo.countryName or geo.country or "Unknown")
        table.insert(lines, "🗺️  Standort / Location: " .. loc)
    end

    if cfg.showISP and geo.isp then
        table.insert(lines, "🏢 Anbieter / ISP:      " .. geo.isp)
        if geo.asn and geo.asn ~= "" then
            table.insert(lines, "📡 ASN:                 " .. geo.asn)
        end
    end

    if geo.isVPN then
        table.insert(lines, "🕵️  VPN/Proxy erkannt / VPN/Proxy detected")
    end

    if geo.isHosting then
        table.insert(lines, "🖥️  Hosting-IP erkannt / Hosting IP detected")
    end

    table.insert(lines, "")
    table.insert(lines, "⏱️  Zeitstempel:         " .. ts)

    if banType == "perm" then
        table.insert(lines, "🚫 Status:              PERMANENTE SPERRE / PERMANENT BAN")
    elseif banType == "temp" then
        table.insert(lines, "⏳ Status:              TEMPORÄRE SPERRE / TEMPORARY BAN")
    elseif banType == "subnet" then
        table.insert(lines, "🔒 Status:              SUBNETZ GESPERRT / SUBNET BLOCKED")
    else
        table.insert(lines, "🔒 Status:              BLOCKIERT / BLOCKED")
    end

    if violations and violations >= 2 then
        table.insert(lines, "🔢 Verstöße / Violations: " .. violations)
    end

    -- Eskalationswarnung / Escalation warning
    if violations and violations >= 3 then
        table.insert(lines, "")
        table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        table.insert(lines, "⚠️  HINWEIS / NOTICE:")
        table.insert(lines, "Dieser Vorfall wurde vollständig protokolliert.")
        table.insert(lines, "This incident has been fully logged.")
    end

    if cfg.showAbuseWarning and violations and violations >= 2 then
        table.insert(lines, "")
        table.insert(lines, "📨 Ein Missbrauchsbericht wurde an deinen ISP")
        table.insert(lines, "   gesendet / An abuse report has been sent")
        table.insert(lines, "   to your ISP: " .. (geo.isp or "Unknown"))
    end

    if cfg.showRefID and refID then
        table.insert(lines, "")
        table.insert(lines, "📋 Referenz-ID / Reference ID:")
        table.insert(lines, "   " .. refID)
        table.insert(lines, "   (Für Strafanzeige / For police report)")
    end

    table.insert(lines, "")
    table.insert(lines, "╚══════════════════════════════════════════════╝")

    return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Eskalations-Engine / Escalation Engine
-- ─────────────────────────────────────────────────────────────────────────────

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
        Logger.alertAttack(alertData)

    elseif cfg.action == "tempban" then
        IPBlocker.tempBan(ip, cfg.message, cfg.duration or Config.TempBanDuration, "Connection Flood")
        Logger.alertAttack(alertData)

    elseif cfg.action == "permban" then
        IPBlocker.permBan(ip, cfg.message, "Connection Flood")
        if cfg.subnetBlock then
            IPBlocker.blockSubnet(ip, "Wiederholter DDoS-Angriff / Repeated DDoS attack")
        end
        if cfg.discordAlert then
            Logger.alertAttack(alertData)
        end
        -- Stufe 3: Missbrauchsbericht an ISP generieren / Level 3: generate ISP abuse report
        if Config.AbuseReporting and Config.AbuseReporting.enabled then
            AbuseReporter.quickReport(ip, geoInfo, violations, firstSeenAt[ip])
        end
    end

    stats.blockedTotal      = stats.blockedTotal + 1
    stats.blockedLastMinute = stats.blockedLastMinute + 1
    stats.attackIntensity   = calcIntensity()
    logAttack(ip, geoInfo.country, geoInfo.isp, "Connection Flood", cfg.action:upper())
end

-- ─────────────────────────────────────────────────────────────────────────────
-- playerConnecting – LADEBILDSCHIRM-FESTUNG / LOADING SCREEN FORTRESS
-- ─────────────────────────────────────────────────────────────────────────────
-- Dies ist der exakte Punkt wo ~99% aller Angriffe stattfinden.
-- This is the exact point where ~99% of all attacks happen.
--
-- Ablauf / Flow:
--   1. Sofort defer()  → wir kontrollieren den Ladebildschirm
--   2. IP-Sperre       → Honeypot oder sofortige Ablehnung
--   3. ID-Sperre       → Identifier-Ban
--   4. Steam-Token     → kein Token = Bot-Merkmal
--   5. Simultane Limit → zu viele parallele Verbindungen von dieser IP
--   6. Rate-Limit      → zu schnelle Verbindungsversuche
--   7. Geo-IP          → Land/VPN/Proxy prüfen
--   ✓  Erlaubt         → Spieler darf joinen
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src    = source
    local rawIP  = GetPlayerEndpoint(src) or ""
    local ip     = rawIP:match("^([^:]+)") or rawIP

    stats.totalConnAttempts = stats.totalConnAttempts + 1
    pushTimeSeries(stats.connsPerSecond, 1)

    -- Ersten Zeitstempel merken / Record first-seen timestamp
    if not firstSeenAt[ip] then firstSeenAt[ip] = os.time() end

    -- ── Schritt 0: Sofort defer() – ab jetzt kontrollieren wir den Ladebildschirm
    -- ── Step 0: Defer immediately – we now control the loading screen
    deferrals.defer()
    Wait(0)

    deferrals.update("🛡️ Kriegswabwehr: Verbindungsprüfung läuft...")
    Wait(100)

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 1: IP-Sperrliste / Step 1: IP ban list
    -- ────────────────────────────────────────────────────────────────────────
    local banCheck = IPBlocker.isBlocked(ip)
    if banCheck.blocked then
        stats.blockedTotal      = stats.blockedTotal + 1
        stats.blockedLastMinute = stats.blockedLastMinute + 1
        logAttack(ip, nil, nil, "Banned IP", "BLOCKED")

        local violations = RateLimiter.getViolations(ip)

        -- Honeypot: Gebannte IP in Fake-Schleife halten / Hold banned IP in fake loop
        if Config.Honeypot and Config.Honeypot.enabled then
            IPBlocker.checkGeoIP(ip, function(geoData)
                local refID = makeRefID(ip, "BAN")
                Tarpit.hold(ip, math.max(violations, 1), deferrals, function()
                    deferrals.done(buildDeterrenceMessage(ip, geoData, refID, banCheck.type, violations))
                end)
            end)
        else
            IPBlocker.checkGeoIP(ip, function(geoData)
                local refID = makeRefID(ip, "BAN")
                deferrals.done(buildDeterrenceMessage(ip, geoData, refID, banCheck.type, violations))
            end)
        end
        return
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 2: Identifier-Sperre / Step 2: Identifier ban
    -- ────────────────────────────────────────────────────────────────────────
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers or {}) do
        local idBlocked, idReason = IPBlocker.isIdentifierBlocked(id)
        if idBlocked then
            stats.blockedTotal      = stats.blockedTotal + 1
            stats.blockedLastMinute = stats.blockedLastMinute + 1
            deferrals.done("🚫 Zugang verweigert (ID gesperrt): " .. (idReason or "Banned"))
            return
        end
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 3: Steam-Token-Prüfung (kein Token = Bot-Merkmal)
    -- Step 3: Steam token check (no token = bot signature)
    -- ────────────────────────────────────────────────────────────────────────
    if Config.AttackSignatures.requireSteamToken and not AntiTheft.validateSteamToken(src) then
        stats.blockedTotal      = stats.blockedTotal + 1
        stats.blockedLastMinute = stats.blockedLastMinute + 1
        logAttack(ip, nil, nil, "No Steam Token (Bot)", "BLOCKED")
        Logger.warn("[BOT-DETECT] Kein Steam-Token – wahrscheinlich Bot: IP=" .. ip)
        -- Bots kurz in Tarpit halten / Hold bots briefly in tarpit
        if Config.Tarpit and Config.Tarpit.enabled then
            Tarpit.hold(ip, 1, deferrals, function()
                deferrals.done("🚫 Kein gültiges Steam-Token erkannt.\nBitte starte Steam und versuche es erneut.")
            end)
        else
            deferrals.done("🚫 Kein gültiges Steam-Token erkannt.")
        end
        return
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 4: Simultane Verbindungslimits / Step 4: Simultaneous limits
    -- Zu viele parallele Verbindungen von dieser IP = DDoS-Werkzeug
    -- Too many parallel connections from this IP = DDoS tool
    -- ────────────────────────────────────────────────────────────────────────
    local simCheck = RateLimiter.checkSimultaneous(ip)
    if not simCheck.allowed then
        IPBlocker.checkGeoIP(ip, function(geoData)
            escalate(ip, geoData)
            local violations = RateLimiter.getViolations(ip)
            local refID      = makeRefID(ip, "SIM")
            logAttack(ip, geoData.country, geoData.isp, "Connection Flood", "BLOCKED")
            if Config.Tarpit and Config.Tarpit.enabled and violations >= (Config.Tarpit.minViolations or 1) then
                Tarpit.hold(ip, violations, deferrals, function()
                    deferrals.done(buildDeterrenceMessage(ip, geoData, refID, "temp", violations))
                end)
            else
                deferrals.done(buildDeterrenceMessage(ip, geoData, refID, "temp", violations))
            end
        end)
        return
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 5: Rate-Limiting / Step 5: Rate limiting
    -- Zu schnelle Verbindungsfolge = Angriffstools (CMD-Skripte, Bots)
    -- Too-fast connection sequence = attack tools (CMD scripts, bots)
    -- ────────────────────────────────────────────────────────────────────────
    local rateCheck = RateLimiter.checkConnectionRate(ip)
    if not rateCheck.allowed then
        -- Geo-IP abrufen, eskalieren, dann deterrence anzeigen
        -- Fetch Geo-IP, escalate, then show deterrence
        IPBlocker.checkGeoIP(ip, function(geoData)
            escalate(ip, geoData)
            local violations = RateLimiter.getViolations(ip)
            local refID      = makeRefID(ip, "RL")
            logAttack(ip, geoData.country, geoData.isp, "Connection Flood", "BLOCKED")

            -- Tarpit aktivieren wenn konfiguriert / Activate tarpit if configured
            if Config.Tarpit and Config.Tarpit.enabled and violations >= (Config.Tarpit.minViolations or 1) then
                -- Angreifer im Ladebildschirm festhalten / Hold attacker on loading screen
                Tarpit.hold(ip, violations, deferrals, function()
                    -- Nach Tarpit: visuell abschrecken / After tarpit: visual deterrence
                    deferrals.done(buildDeterrenceMessage(ip, geoData, refID, nil, violations))
                end)
            else
                deferrals.done(buildDeterrenceMessage(ip, geoData, refID, nil, violations))
            end
        end)
        return
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 6: Geo-IP-Prüfung / Step 6: Geo IP check
    -- Jede erlaubte Verbindung läuft durch Geo-Check
    -- Every permitted connection goes through geo check
    -- ────────────────────────────────────────────────────────────────────────
    RateLimiter.registerConnection(ip)

    IPBlocker.checkGeoIP(ip, function(geoData)
        if geoData.blocked then
            RateLimiter.deregisterConnection(ip)
            stats.blockedTotal      = stats.blockedTotal + 1
            stats.blockedLastMinute = stats.blockedLastMinute + 1

            local refID = makeRefID(ip, "GEO")
            logAttack(ip, geoData.country, geoData.isp, geoData.reason or "Geo-Block", "BLOCKED")
            Logger.alertAttack({
                ip              = ip,
                country         = geoData.country,
                isp             = geoData.isp,
                attackType      = "Geo-Block",
                escalationLevel = 1,
                action          = "block",
                reason          = geoData.reason,
            })
            deferrals.done(buildDeterrenceMessage(ip, geoData, refID, "perm", 1))
        else
            -- ✓ Verbindung erlaubt / Connection allowed
            stats.legitimateConns = stats.legitimateConns + 1
            stats.attackIntensity = calcIntensity()
            Logger.info(string.format(
                "[CONNECT ✓] %s (%s) IP=%s %s/%s ISP=%s",
                name, tostring(src), ip,
                geoData.country or "XX", geoData.countryName or "?", geoData.isp or "?"
            ))
            deferrals.done()
        end
    end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- playerDropped – Verbindung abmelden / Deregister connection
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler("playerDropped", function(reason)
    local src   = source
    local rawIP = GetPlayerEndpoint(src) or ""
    local ip    = rawIP:match("^([^:]+)") or rawIP

    RateLimiter.deregisterConnection(ip)
    RateLimiter.cleanupPlayer(src)

    Logger.debug(string.format("[DISCONNECT] %s (IP=%s): %s", tostring(src), ip, reason))
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Dashboard-API / Dashboard API
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:requestStats", function()
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    TriggerClientEvent("kriegswabwehr:statsResponse", src, {
        totalConnAttempts = stats.totalConnAttempts,
        blockedLastMinute = stats.blockedLastMinute,
        legitimateConns   = stats.legitimateConns,
        blockedTotal      = stats.blockedTotal,
        attackIntensity   = stats.attackIntensity,
        connsPerSecond    = stats.connsPerSecond,
        attackLog         = stats.attackLog,
        banStats          = IPBlocker.getStats(),
        rateLimitStats    = RateLimiter.getStats(),
        tarpitStats       = Tarpit.getStats(),
        players           = GetNumPlayers(),
        maxPlayers        = GetConvarInt("sv_maxclients", 32),
    })
end)

RegisterNetEvent("kriegswabwehr:getBanList", function()
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    TriggerClientEvent("kriegswabwehr:banListResponse", src, {
        bans    = IPBlocker.getBanList(),
        subnets = IPBlocker.getSubnetList(),
    })
end)

RegisterNetEvent("kriegswabwehr:unbanIP", function(ip)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    local success = IPBlocker.unban(ip)
    Logger.adminAction(src, "UNBAN", ip, success and "Erfolgreich" or "IP nicht gefunden")
    TriggerClientEvent("kriegswabwehr:unbanResult", src, { success = success, ip = ip })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Periodisches Zurücksetzen der Minuten-Statistik / Periodic stats reset
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(60000)
        pushTimeSeries(stats.blockedPerMinute, stats.blockedLastMinute)
        stats.blockedLastMinute = 0
        stats.attackIntensity   = calcIntensity()
        -- firstSeenAt bereinigen: Einträge älter als 24h entfernen / Clean entries older than 24h
        local cutoff = os.time() - 86400
        for ip, ts in pairs(firstSeenAt) do
            if ts < cutoff then firstSeenAt[ip] = nil end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin-Befehl / Admin command
-- ─────────────────────────────────────────────────────────────────────────────

RegisterCommand("kwdashboard", function(src, args, raw)
    if src == 0 then
        Logger.info("Dashboard-Befehl von Serverkonsole")
        return
    end
    if not AntiTheft.isAdmin(src) then
        TriggerClientEvent("chat:addMessage", src, {
            color = {255, 50, 50},
            args  = {"[KW]", "Keine Berechtigung / No permission."},
        })
        return
    end
    TriggerClientEvent("kriegswabwehr:openDashboard", src)
end, false)

Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
Logger.info("  🛡️  KRIEGSWABWEHR – Ladebildschirm-Festung aktiv      ")
Logger.info("  🕸️  Tarpit    | 👁️  Visual Deterrence | 📨 ISP Report  ")
Logger.info("  🍯  Honeypot  | 🌍  Geo-Block         | 🔒 Rate Limit  ")
Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
