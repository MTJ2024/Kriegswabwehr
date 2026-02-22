-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Logger / Protokollierungssystem
-- ═══════════════════════════════════════════════════════════════════════════
-- Zentrale Protokollierung mit Discord-Webhook-Integration
-- Central logging with Discord webhook integration
-- ═══════════════════════════════════════════════════════════════════════════

Logger = {}

-- Interne Protokoll-Puffer / Internal log buffer
local logBuffer = {}
local logCount   = 0

-- ANSI-Farbcodes für Server-Konsole / ANSI color codes for server console
local COLORS = {
    RESET  = "^0",
    RED    = "^1",
    GREEN  = "^2",
    YELLOW = "^3",
    BLUE   = "^4",
    CYAN   = "^5",
    WHITE  = "^7",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Hilfsfunktionen / Helper functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Aktuellen Zeitstempel zurückgeben / Return current timestamp string
local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Präfix für Konsolenausgabe / Prefix for console output
local function prefix(level)
    local map = {
        DEBUG = COLORS.CYAN   .. "[KW DEBUG]" .. COLORS.RESET,
        INFO  = COLORS.GREEN  .. "[KW INFO] " .. COLORS.RESET,
        WARN  = COLORS.YELLOW .. "[KW WARN] " .. COLORS.RESET,
        ERROR = COLORS.RED    .. "[KW ERROR]" .. COLORS.RESET,
    }
    return map[level] or ("[KW " .. level .. "]")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Kern-Logging / Core Logging
-- ─────────────────────────────────────────────────────────────────────────────

-- Schreibt eine Protokollnachricht in die Konsole
-- Writes a log message to the console
function Logger.log(level, message)
    -- Prüfen ob der Log-Level relevant ist / Check if log level is relevant
    local levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
    local cfgLevel = levels[Config.LogLevel] or 2
    if (levels[level] or 2) < cfgLevel then return end

    local entry = {
        timestamp = getTimestamp(),
        level     = level,
        message   = message,
    }

    -- Konsolenausgabe / Console output
    print(string.format("%s %s %s", entry.timestamp, prefix(level), message))

    -- Puffer speichern / Save to buffer
    table.insert(logBuffer, entry)
    logCount = logCount + 1

    -- Rotation: älteste Einträge löschen wenn Maximum erreicht
    -- Rotation: delete oldest entries when maximum reached
    if logCount > Config.MaxLogEntries then
        table.remove(logBuffer, 1)
        logCount = logCount - 1
    end
end

-- Kurzformen / Shorthand functions
function Logger.debug(msg)   Logger.log("DEBUG", msg) end
function Logger.info(msg)    Logger.log("INFO",  msg) end
function Logger.warn(msg)    Logger.log("WARN",  msg) end
function Logger.error(msg)   Logger.log("ERROR", msg) end

-- ─────────────────────────────────────────────────────────────────────────────
-- Discord-Webhook / Discord Webhook
-- ─────────────────────────────────────────────────────────────────────────────

-- Sendet eine Nachricht an den konfigurierten Discord-Webhook
-- Sends a message to the configured Discord webhook
function Logger.sendDiscord(title, description, color, fields)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" then return end

    local embed = {
        title       = title,
        description = description,
        color       = color or Config.DiscordColors.info,
        timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer      = { text = "Kriegswabwehr v1.0.0 • " .. GetConvarInt("sv_maxclients", 32) .. " Slots" },
        fields      = fields or {},
    }

    PerformHttpRequest(Config.DiscordWebhook, function(err, text, headers)
        if err ~= 200 then
            Logger.warn("Discord-Webhook fehlgeschlagen / Discord webhook failed: " .. tostring(err))
        end
    end, "POST", json.encode({ embeds = { embed } }), {
        ["Content-Type"] = "application/json",
    })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Angriffs-Benachrichtigung / Attack Notification
-- ─────────────────────────────────────────────────────────────────────────────

-- Sendet eine strukturierte Angriffs-Warnung an Discord
-- Sends a structured attack warning to Discord
function Logger.alertAttack(data)
    -- data = { ip, action, reason, country, isp, attackType, escalationLevel }
    local colors = {
        warn    = Config.DiscordColors.warning,
        tempban = Config.DiscordColors.tempban,
        permban = Config.DiscordColors.permban,
    }
    local color = colors[data.action] or Config.DiscordColors.info

    local fields = {
        { name = "🌐 IP-Adresse",        value = data.ip or "Unbekannt",         inline = true  },
        { name = "🗺️ Land / Country",    value = data.country or "Unbekannt",    inline = true  },
        { name = "🏢 ISP",               value = data.isp or "Unbekannt",        inline = true  },
        { name = "⚔️ Angriffstyp",       value = data.attackType or "Unbekannt", inline = true  },
        { name = "📊 Eskalationsstufe",  value = tostring(data.escalationLevel or 1), inline = true },
        { name = "🚫 Maßnahme",          value = data.action or "warn",          inline = true  },
        { name = "📝 Grund / Reason",    value = data.reason or "Rate limit",    inline = false },
    }

    local titles = {
        warn    = "⚠️ Angriffswarnung / Attack Warning",
        tempban = "🔒 Temporäre Sperre / Temporary Ban",
        permban = "☠️ PERMANENTE SPERRE / PERMANENT BAN",
    }

    Logger.sendDiscord(
        titles[data.action] or "🛡️ Kriegswabwehr Ereignis",
        string.format("```\n%s\n```", data.reason or "Verdächtige Aktivität"),
        color,
        fields
    )

    Logger.warn(string.format(
        "[ANGRIFF] IP=%s Aktion=%s Stufe=%d Typ=%s",
        data.ip or "?", data.action or "?", data.escalationLevel or 1, data.attackType or "?"
    ))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin-Aktion Logging / Admin Action Logging
-- ─────────────────────────────────────────────────────────────────────────────

-- Protokolliert alle Admin-Aktionen mit Zeitstempel, IP und Identifikator
-- Logs all admin actions with timestamp, IP and identifier
function Logger.adminAction(adminId, action, target, details)
    local adminName = GetPlayerName(adminId) or "Unbekannt"
    local adminIp   = GetPlayerEndpoint(adminId) or "?"

    Logger.info(string.format(
        "[ADMIN] %s (%s) IP=%s → %s auf %s | %s",
        adminName, adminId, adminIp, action, tostring(target), details or ""
    ))

    Logger.sendDiscord(
        "🔑 Admin-Aktion / Admin Action",
        string.format("**%s** (`%s`) hat **%s** ausgeführt", adminName, adminId, action),
        Config.DiscordColors.info,
        {
            { name = "👤 Admin",     value = adminName .. " (" .. tostring(adminId) .. ")", inline = true },
            { name = "🌐 Admin IP", value = adminIp,                                        inline = true },
            { name = "🎯 Ziel",     value = tostring(target),                               inline = true },
            { name = "📋 Details",  value = details or "–",                                 inline = false },
        }
    )
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Log-Puffer abrufen (für Dashboard) / Retrieve log buffer (for dashboard)
-- ─────────────────────────────────────────────────────────────────────────────
function Logger.getBuffer(limit)
    limit = limit or 100
    local result = {}
    local start  = math.max(1, #logBuffer - limit + 1)
    for i = start, #logBuffer do
        table.insert(result, logBuffer[i])
    end
    return result
end

Logger.info("Logger initialisiert / Logger initialized")
