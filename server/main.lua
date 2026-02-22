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
-- Adaptive Card für visuellen Abschreck / Adaptive Card visual deterrence
-- ─────────────────────────────────────────────────────────────────────────────
-- FiveM deferrals.presentCard() rendert eine echte grafische Karte direkt
-- im Ladebildschirm. Kein Text-Dump – echte formatierte Warnung mit Farben,
-- Tabellen und Abschnitten.
-- FiveM deferrals.presentCard() renders a real graphic card directly in the
-- loading screen. Not a text dump – a real formatted warning with colors,
-- tables and sections.
--
-- LEGAL: Wir zeigen NUR öffentliche Netzwerkdaten des Angreifers.
-- LEGAL: We show ONLY the attacker's own public network data.
-- ─────────────────────────────────────────────────────────────────────────────

local function buildDeterrenceCard(ip, geoData, refID, banType, violations)
    local cfg    = Config.VisualDeterrence or {}
    local geo    = geoData or {}
    local subnet = ip:match("^(%d+%.%d+%.%d+)%.%d+$") or "?"
    local ts     = os.date("!%Y-%m-%d %H:%M:%S UTC")

    -- Standort / Location
    local location = ""
    if geo.city and geo.city ~= "" and geo.city ~= "Unknown" then
        location = geo.city .. ", "
    end
    location = location .. (geo.countryName or geo.country or "Unbekannt / Unknown")

    -- Status-Badge / Status badge
    local statusText = "🔒 BLOCKIERT / BLOCKED"
    if banType == "perm"   then statusText = "⛔ PERMANENTE SPERRE / PERMANENT BAN"  end
    if banType == "temp"   then statusText = "⏳ TEMPORÄRE SPERRE / TEMPORARY BAN"   end
    if banType == "subnet" then statusText = "🔗 SUBNETZ GESPERRT / SUBNET BLOCKED"  end

    -- Fakten-Tabelle / Facts table
    local facts = {}
    if cfg.showIP then
        table.insert(facts, { title = "🌐 IP-Adresse",        value = ip })
        if subnet ~= "?" then
            table.insert(facts, { title = "🔗 Subnetz / Subnet", value = subnet .. ".0/24" })
        end
    end
    if cfg.showLocation then
        table.insert(facts, { title = "🗺️  Standort / Location", value = location })
    end
    if cfg.showISP and geo.isp then
        table.insert(facts, { title = "🏢 Anbieter / ISP",       value = geo.isp })
        if geo.asn and geo.asn ~= "" then
            table.insert(facts, { title = "📡 ASN / Netz",        value = geo.asn })
        end
    end
    if geo.isVPN     then table.insert(facts, { title = "🕵️  Typ",     value = "⚠️ VPN / Proxy erkannt / detected"    }) end
    if geo.isHosting then table.insert(facts, { title = "🖥️  Hosting", value = "⚠️ Rechenzentrum-IP / Datacenter IP" }) end
    table.insert(facts, { title = "⏱️  Zeitstempel / Time", value = ts })
    table.insert(facts, { title = "🔒 Status",               value = statusText })
    if violations and violations >= 2 then
        table.insert(facts, { title = "🔢 Verstöße / Violations", value = tostring(violations) })
    end

    -- ISP-Warnzeile / ISP warning line
    local ispLine
    if cfg.showAbuseWarning and violations and violations >= 2 and geo.isp then
        ispLine = "📨  ISP-MISSBRAUCHSBERICHT AN " .. geo.isp:upper() .. " GESENDET"
    else
        ispLine = "📋  VORFALL VOLLSTÄNDIG PROTOKOLLIERT / INCIDENT FULLY LOGGED"
    end

    -- Referenz-Zeile / Reference line
    local refLine = refID and ("🔖  " .. refID) or ""

    -- ── Adaptive Card (Lua-Tabelle -> JSON) ───────────────────────────────────
    local card = {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        type        = "AdaptiveCard",
        version     = "1.2",
        body        = {

            -- ── Roter Kopf / Red header ──────────────────────────────────────
            {
                type  = "Container",
                style = "attention",
                bleed = true,
                items = {
                    {
                        type                = "TextBlock",
                        text                = "⛔  K R I E G S W A B W E H R  ⛔",
                        weight              = "Bolder",
                        size                = "ExtraLarge",
                        color               = "Light",
                        horizontalAlignment = "Center",
                        wrap                = true,
                    },
                    {
                        type                = "TextBlock",
                        text                = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
                        color               = "Light",
                        horizontalAlignment = "Center",
                        spacing             = "None",
                        wrap                = false,
                    },
                    {
                        type                = "TextBlock",
                        text                = "ZUGANG VERWEIGERT  ▪  ACCESS DENIED",
                        weight              = "Bolder",
                        size                = "Large",
                        color               = "Light",
                        horizontalAlignment = "Center",
                        wrap                = true,
                        spacing             = "None",
                    },
                },
            },

            -- ── Orangene Warnzeile / Orange warning banner ───────────────────
            {
                type  = "Container",
                style = "warning",
                items = {
                    {
                        type                = "TextBlock",
                        text                = "⚠️  DEINE VERBINDUNG WURDE VOLLSTÄNDIG IDENTIFIZIERT  ⚠️",
                        weight              = "Bolder",
                        color               = "Dark",
                        horizontalAlignment = "Center",
                        wrap                = true,
                        size                = "Medium",
                    },
                    {
                        type                = "TextBlock",
                        text                = "YOUR CONNECTION HAS BEEN FULLY IDENTIFIED AND LOGGED",
                        color               = "Dark",
                        horizontalAlignment = "Center",
                        wrap                = true,
                        spacing             = "None",
                        size                = "Small",
                    },
                },
            },

            -- ── Informationstabelle / Information table ──────────────────────
            {
                type  = "Container",
                style = "emphasis",
                items = {
                    {
                        type    = "TextBlock",
                        text    = "📊  VERBINDUNGSDATEN / CONNECTION DATA",
                        weight  = "Bolder",
                        size    = "Medium",
                        spacing = "Small",
                    },
                    {
                        type  = "FactSet",
                        facts = facts,
                    },
                },
            },

            -- ── Roter Footer / Red footer ────────────────────────────────────
            {
                type  = "Container",
                style = "attention",
                bleed = true,
                items = {
                    {
                        type                = "TextBlock",
                        text                = ispLine,
                        weight              = "Bolder",
                        color               = "Light",
                        horizontalAlignment = "Center",
                        wrap                = true,
                        size                = "Medium",
                    },
                    {
                        type                = "TextBlock",
                        text                = refLine,
                        color               = "Light",
                        horizontalAlignment = "Center",
                        wrap                = true,
                        spacing             = "Small",
                        size                = "Small",
                    },
                    {
                        type                = "TextBlock",
                        text                = "⚖️  §303b StGB (Computersabotage)  ▪  §202a StGB  ▪  18 U.S.C. § 1030 (CFAA)",
                        color               = "Warning",
                        horizontalAlignment = "Center",
                        size                = "Small",
                        wrap                = true,
                        spacing             = "Small",
                    },
                },
            },

        },
    }

    return json.encode(card)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Alarm-Flash + Adaptive Card anzeigen, dann Verbindung trennen
-- Show alarm flash + Adaptive Card, then disconnect
-- ─────────────────────────────────────────────────────────────────────────────
-- Ablauf / Flow:
--   1. Kurzes Blink-Flash via deferrals.update()     (~2s)
--   2. Große rote Adaptive Card via presentCard()
--   3. Warten damit Angreifer die Karte sehen muss   (config: cardDisplaySeconds)
--   4. Verbindung trennen mit Text-Nachricht
-- ─────────────────────────────────────────────────────────────────────────────
local function showVisualDeterrence(ip, geoData, refID, banType, violations, deferrals)
    local cfg         = Config.VisualDeterrence or {}
    local displaySecs = cfg.cardDisplaySeconds or 8

    -- ── Phase 1: Alarm-Blink (4 × 500ms = 2s) ───────────────────────────────
    -- Schnelles Wechseln zwischen Vollwarnung und Pause erzeugt Blinkeffekt
    -- Rapid switching between full warning and pause creates blinking effect
    local FLASH_ON  = "🚨 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 🚨\n" ..
                      "         ⛔  ZUGANG VERWEIGERT  ⛔\n" ..
                      "         ⛔  ACCESS  DENIED     ⛔\n" ..
                      "🚨 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 🚨"
    local FLASH_OFF = "\n\n" ..
                      "         ⚠️  IP ERKANNT / IP DETECTED  ⚠️\n" ..
                      "              " .. ip .. "\n"

    for i = 1, 4 do
        deferrals.update(i % 2 == 1 and FLASH_ON or FLASH_OFF)
        Wait(500)
    end

    -- ── Phase 2: Adaptive Card (grafische Warnung / graphic warning) ─────────
    local cardOk = false
    local ok, err = pcall(function()
        deferrals.presentCard(buildDeterrenceCard(ip, geoData, refID, banType, violations))
        cardOk = true
    end)
    if not ok then
        Logger.warn("[CARD] presentCard fehlgeschlagen / failed: " .. tostring(err))
    end

    -- ── Phase 3: Angreifer muss Karte sehen / Force attacker to view card ────
    if cardOk then
        Wait(displaySecs * 1000)
    end

    -- ── Phase 4: Verbindung trennen / Disconnect ─────────────────────────────
    deferrals.done(buildDeterrenceMessage(ip, geoData, refID, banType, violations))
end



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
--   1. Sofort defer()  -> wir kontrollieren den Ladebildschirm
--   2. IP-Sperre       -> Honeypot oder sofortige Ablehnung
--   3. ID-Sperre       -> Identifier-Ban
--   4. Steam-Token     -> kein Token = Bot-Merkmal
--   5. Simultane Limit -> zu viele parallele Verbindungen von dieser IP
--   6. Rate-Limit      -> zu schnelle Verbindungsversuche
--   7. Geo-IP          -> Land/VPN/Proxy prüfen
--   ✓  Erlaubt         -> Spieler darf joinen
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

    -- ╔══════════════════════════════════════════════════════════════════════╗
    -- ║  WHITELIST-BYPASS – LÄUFT VOR ALLEN ANDEREN PRÜFUNGEN              ║
    -- ║  Ebene 1: ACE/txAdmin  |  Ebene 2: Datei  |  Ebene 3: Config      ║
    -- ╚══════════════════════════════════════════════════════════════════════╝
    local playerIds             = GetPlayerIdentifiers(src) or {}
    local whitelisted, wlReason = Whitelist.check(src, ip)

    if whitelisted then
        stats.legitimateConns = stats.legitimateConns + 1
        Logger.info(string.format(
            "[%s ✓] %s (%s) IP=%s – Whitelist-Bypass / whitelist bypass",
            wlReason, name, tostring(src), ip
        ))
        deferrals.done()
        return
    end
    -- ══════════════════════════════════════════════════════════════════════

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
                    showVisualDeterrence(ip, geoData, refID, banCheck.type, violations, deferrals)
                end)
            end)
        else
            IPBlocker.checkGeoIP(ip, function(geoData)
                local refID = makeRefID(ip, "BAN")
                showVisualDeterrence(ip, geoData, refID, banCheck.type, violations, deferrals)
            end)
        end
        return
    end

    -- ────────────────────────────────────────────────────────────────────────
    -- Schritt 2: Identifier-Sperre / Step 2: Identifier ban
    -- ────────────────────────────────────────────────────────────────────────
    for _, id in ipairs(playerIds) do
        local idBlocked, idReason = IPBlocker.isIdentifierBlocked(id)
        if idBlocked then
            stats.blockedTotal      = stats.blockedTotal + 1
            stats.blockedLastMinute = stats.blockedLastMinute + 1
            showVisualDeterrence(ip, {}, makeRefID(ip, "ID"), "perm", 1, deferrals)
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
                showVisualDeterrence(ip, {}, makeRefID(ip, "BOT"), nil, 1, deferrals)
            end)
        else
            showVisualDeterrence(ip, {}, makeRefID(ip, "BOT"), nil, 1, deferrals)
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
                    showVisualDeterrence(ip, geoData, refID, "temp", violations, deferrals)
                end)
            else
                showVisualDeterrence(ip, geoData, refID, "temp", violations, deferrals)
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
                Tarpit.hold(ip, violations, deferrals, function()
                    showVisualDeterrence(ip, geoData, refID, nil, violations, deferrals)
                end)
            else
                showVisualDeterrence(ip, geoData, refID, nil, violations, deferrals)
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
            showVisualDeterrence(ip, geoData, refID, "perm", 1, deferrals)
        else
            -- ─────────────────────────────────────────────────────────────────
            -- ✓ Alle Security-Checks bestanden / All security checks passed
            -- WhitelistQueue-Modus: Spieler in Warteschlange legen?
            -- WhitelistQueue mode: put player in approval queue?
            -- ─────────────────────────────────────────────────────────────────
            if Config.WhitelistQueue and Config.WhitelistQueue.enabled then
                -- Spieler in Queue einreihen / Add player to queue
                local token = WhitelistQueue.add(src, name, ip, playerIds, geoData)

                -- Ladebildschirm-Nachricht / Loading screen message
                local timeout    = Config.WhitelistQueue.timeoutSeconds or 120
                local waitMsg    = Config.WhitelistQueue.waitMessage
                    or "Warte auf Admin-Freigabe... / Waiting for admin approval..."

                deferrals.update(waitMsg)

                -- ── Warte-Schleife / Wait loop ────────────────────────────────
                -- Hält den Deferral offen solange kein Ergebnis vorliegt.
                -- Holds the deferral open until a result is available.
                local waited = 0
                local step   = 3  -- Prüfintervall in Sekunden / check interval seconds
                local resolved, allow, denyReason = false, false, ""

                while waited < timeout do
                    Wait(step * 1000)
                    waited = waited + step

                    resolved, allow, denyReason = WhitelistQueue.getResult(token)
                    if resolved then break end

                    local remaining = timeout - waited
                    deferrals.update(string.format(
                        "%s\n\n⏱️  %ds verbleibend / remaining",
                        waitMsg, remaining
                    ))
                end

                WhitelistQueue.cleanup(token)

                if not resolved then
                    -- Auto-Timeout
                    deferrals.done(Config.WhitelistQueue.timeoutMessage
                        or "Zeitüberschreitung / Timeout.")
                elseif allow then
                    -- Freigegeben / Approved
                    stats.legitimateConns = stats.legitimateConns + 1
                    stats.attackIntensity = calcIntensity()
                    Logger.info(string.format(
                        "[QUEUE ✓] %s (%s) IP=%s freigegeben / approved",
                        name, tostring(src), ip
                    ))
                    deferrals.done()
                else
                    -- Abgelehnt / Denied
                    stats.blockedTotal      = stats.blockedTotal + 1
                    stats.blockedLastMinute = stats.blockedLastMinute + 1
                    Logger.info(string.format(
                        "[QUEUE ✗] %s (%s) IP=%s abgelehnt / denied: %s",
                        name, tostring(src), ip, denyReason
                    ))
                    deferrals.done(denyReason)
                end
            else
                -- ✓ Verbindung direkt erlaubt / Connection allowed directly
                stats.legitimateConns = stats.legitimateConns + 1
                stats.attackIntensity = calcIntensity()
                Logger.info(string.format(
                    "[CONNECT ✓] %s (%s) IP=%s %s/%s ISP=%s",
                    name, tostring(src), ip,
                    geoData.country or "XX", geoData.countryName or "?", geoData.isp or "?"
                ))
                deferrals.done()
            end
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
        players           = #GetPlayers(),
        maxPlayers        = GetConvarInt("sv_maxclients", 32),
        pendingQueue      = WhitelistQueue.getAll(),
        whitelistCount    = (function()
            local n = 0
            for _ in pairs(Whitelist.list()) do n = n + 1 end
            return n
        end)(),
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
-- Whitelist-API fuer Dashboard / Whitelist API for dashboard
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:getWhitelist", function()
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    local entries = {}
    for id, data in pairs(Whitelist.list()) do
        table.insert(entries, {
            identifier = id,
            addedBy    = data.addedBy,
            addedAt    = data.addedAt,
            note       = data.note or "",
        })
    end
    table.sort(entries, function(a, b) return (a.addedAt or 0) > (b.addedAt or 0) end)
    TriggerClientEvent("kriegswabwehr:whitelistResponse", src, { entries = entries })
end)

RegisterNetEvent("kriegswabwehr:addWhitelist", function(data)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    if not data or not data.identifier then return end
    local ok, msg = Whitelist.add(data.identifier, "admin:" .. tostring(src), data.note or "")
    Logger.adminAction(src, "WHITELIST_ADD", data.identifier, ok and "OK" or msg)
    TriggerClientEvent("kriegswabwehr:whitelistActionResult", src, {
        success    = ok,
        action     = "add",
        identifier = data.identifier,
        msg        = msg,
    })
end)

RegisterNetEvent("kriegswabwehr:removeWhitelist", function(data)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    if not data or not data.identifier then return end
    local ok, msg = Whitelist.remove(data.identifier)
    Logger.adminAction(src, "WHITELIST_REMOVE", data.identifier, ok and "OK" or msg)
    TriggerClientEvent("kriegswabwehr:whitelistActionResult", src, {
        success    = ok,
        action     = "remove",
        identifier = data.identifier,
        msg        = msg,
    })
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Log-Persistenz-API fuer Dashboard / Log persistence API for dashboard
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:getLogDates", function()
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    TriggerClientEvent("kriegswabwehr:logDatesResponse", src, {
        dates = Logger.getLogDates()
    })
end)

RegisterNetEvent("kriegswabwehr:getLogByDate", function(data)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    local dateKey = data and data.key
    if not dateKey or not dateKey:match("^%d%d%d%d%d%d%d%d$") then return end
    TriggerClientEvent("kriegswabwehr:logByDateResponse", src, {
        key     = dateKey,
        entries = Logger.getLogByDate(dateKey),
    })
end)

RegisterNetEvent("kriegswabwehr:extendLogRetention", function(data)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    local dateKey   = data and data.key
    local extraDays = (data and data.extraDays) or 5
    if not dateKey or not dateKey:match("^%d%d%d%d%d%d%d%d$") then return end
    extraDays = math.max(1, math.min(365, tonumber(extraDays) or 5))
    local adminName = GetPlayerName(src) or tostring(src)
    local ok = Logger.extendRetention(dateKey, extraDays, adminName)
    Logger.adminAction(src, "EXTEND_LOG", dateKey, extraDays .. " extra Tage / extra days")
    TriggerClientEvent("kriegswabwehr:logRetentionResult", src, {
        success   = ok,
        key       = dateKey,
        extraDays = extraDays,
    })
end)

RegisterNetEvent("kriegswabwehr:exportLog", function(data)
    local src = source
    if not AntiTheft.isAdmin(src) then return end
    local dateKey = data and data.key
    if not dateKey or not dateKey:match("^%d%d%d%d%d%d%d%d$") then return end
    Logger.adminAction(src, "EXPORT_LOG", dateKey, "Log-Export angefordert / Log export requested")
    TriggerClientEvent("kriegswabwehr:logExportResponse", src, {
        key     = dateKey,
        content = Logger.exportLog(dateKey),
    })
end)

Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
Logger.info("  🛡️  KRIEGSWABWEHR – Ladebildschirm-Festung aktiv      ")
Logger.info("  🌐  Verbindungsanalyse | 👁️  Visual Deterrence | 📨 ISP")
Logger.info("  🔒  Sperrprotokoll  | 🌍  Geo-Block  | 📋  Log 5 Tage  ")
Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
