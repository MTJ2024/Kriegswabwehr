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

    -- Konsolenausgabe nur wenn explizit aktiviert / Console output only if explicitly enabled
    -- Config.ConsoleLogs = false  -> kein einziger Log in der Serverkonsole sichtbar
    -- Config.ConsoleLogs = false  -> not a single log visible in the server console
    if Config.ConsoleLogs then
        print(string.format("%s %s %s", entry.timestamp, prefix(level), message))
    end

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
        "[ADMIN] %s (%s) IP=%s -> %s auf %s | %s",
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

-- =============================================================================
-- PERSISTENZ / PERSISTENCE – Logs auf Festplatte / Logs to disk
-- =============================================================================
-- Format: data/log_YYYYMMDD.json  (ein File pro Tag / one file per day)
-- Retention: automatische Löschung nach Config.LogRetentionDays (Standard: 5)
-- Verlängerung: data/log_YYYYMMDD.lock – Datei schützt vor Löschung
-- =============================================================================

local RESOURCE = GetCurrentResourceName()

-- Wie viele Tage in der Vergangenheit das Dashboard anzeigt / How many days the dashboard browses back
local LOG_BROWSE_DAYS = 30
-- Wie weit zurück beim Cleanup geprüft wird (> LogRetentionDays + mögliche Lock-Verlängerungen)
-- How far back cleanup checks (> LogRetentionDays + possible lock extensions)
local LOG_CLEANUP_LOOKBACK = 90

-- Puffer für den aktuellen Tag / Buffer for today
local diskBuffer   = {}       -- Einträge seit letztem Flush / entries since last flush
local lastFlushDay = os.date("%Y%m%d")

-- ─────────────────────────────────────────────────────────────────────────────
-- Interner Dateiname für ein Datum / Internal filename for a date
-- ─────────────────────────────────────────────────────────────────────────────
local function logFile(dateKey)
    return "data/log_" .. dateKey .. ".json"
end

local function lockFile(dateKey)
    return "data/log_" .. dateKey .. ".lock"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Bestehendes Log laden / Load existing log from disk
-- ─────────────────────────────────────────────────────────────────────────────
local function loadFromDisk(dateKey)
    local raw = LoadResourceFile(RESOURCE, logFile(dateKey))
    if not raw or raw == "" then return {} end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Flush: aktuellen Puffer auf Festplatte schreiben
-- Flush: write current buffer to disk
-- ─────────────────────────────────────────────────────────────────────────────
local function flush()
    if #diskBuffer == 0 then return end

    local today = os.date("%Y%m%d")

    -- Tag gewechselt: alten Puffer mit gestern zusammenführen und leeren
    -- Day changed: merge old buffer with yesterday and reset
    if today ~= lastFlushDay then
        local old = loadFromDisk(lastFlushDay)
        for _, e in ipairs(diskBuffer) do table.insert(old, e) end
        SaveResourceFile(RESOURCE, logFile(lastFlushDay), json.encode(old), -1)
        diskBuffer   = {}
        lastFlushDay = today
        return
    end

    -- Heute: bestehende Datei laden und ergänzen
    -- Today: load existing file and append
    local existing = loadFromDisk(today)
    for _, e in ipairs(diskBuffer) do table.insert(existing, e) end
    SaveResourceFile(RESOURCE, logFile(today), json.encode(existing), -1)
    diskBuffer = {}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Öffentliche API: Log-Datei für ein Datum laden
-- Public API: load log file for a date
-- ─────────────────────────────────────────────────────────────────────────────
function Logger.getLogByDate(dateKey)
    flush()  -- sicherstellen dass Puffer geschrieben ist
    return loadFromDisk(dateKey)
end

-- Gibt alle verfügbaren Log-Daten zurück (letzte 30 Tage prüfen)
-- Returns all available log dates (checks last 30 days)
function Logger.getLogDates()
    flush()
    local dates = {}
    for i = 0, LOG_BROWSE_DAYS - 1 do
        local ts = os.time() - i * 86400
        local key = os.date("%Y%m%d", ts)
        local content = LoadResourceFile(RESOURCE, logFile(key))
        if content and content ~= "" then
            local locked  = LoadResourceFile(RESOURCE, lockFile(key)) or ""
            local entries = 0
            local ok, parsed = pcall(json.decode, content)
            if ok and type(parsed) == "table" then entries = #parsed end
            table.insert(dates, {
                date      = os.date("%Y-%m-%d", ts),
                key       = key,
                entries   = entries,
                size      = #content,
                locked    = locked ~= "",
                lockInfo  = locked ~= "" and locked or nil,
            })
        end
    end
    return dates
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Verlängerung: Lock-Datei schreiben – verhindert automatische Löschung
-- Extension: write lock file – prevents automatic deletion
-- ─────────────────────────────────────────────────────────────────────────────
function Logger.extendRetention(dateKey, extraDays, adminName)
    extraDays = extraDays or 5
    local until_ts  = os.time() + extraDays * 86400
    local lockData  = string.format(
        "locked_by=%s until=%s extraDays=%d",
        adminName or "admin",
        os.date("%Y-%m-%d %H:%M:%S", until_ts),
        extraDays
    )
    local ok = SaveResourceFile(RESOURCE, lockFile(dateKey), lockData, -1)
    if ok then
        Logger.info(string.format(
            "[LOG] Retention verlängert / Retention extended: %s um %d Tage bis %s",
            dateKey, extraDays, os.date("%Y-%m-%d", until_ts)
        ))
    end
    return ok
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Export: gibt den Inhalt einer Log-Datei als formatierten Text zurück
-- Export: returns the content of a log file as formatted text
-- ─────────────────────────────────────────────────────────────────────────────
function Logger.exportLog(dateKey)
    local entries = Logger.getLogByDate(dateKey)
    if #entries == 0 then return "-- Keine Eintraege / No entries --" end
    local lines = {
        string.format("# Kriegswabwehr Log-Export / Log Export"),
        string.format("# Datum / Date: %s | Eintraege / Entries: %d", dateKey, #entries),
        string.format("# Exportiert / Exported: %s", os.date("%Y-%m-%d %H:%M:%S")),
        string.rep("-", 80),
    }
    for _, e in ipairs(entries) do
        table.insert(lines, string.format("[%s] [%-5s] %s",
            e.timestamp or "?", e.level or "?", e.message or ""))
    end
    return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-Cleanup: Logs älter als Config.LogRetentionDays löschen
-- Auto-cleanup: delete logs older than Config.LogRetentionDays
-- ─────────────────────────────────────────────────────────────────────────────
local function runCleanup()
    local retDays = (Config and Config.LogRetentionDays) or 5
    local deleted = 0
    for i = retDays, LOG_CLEANUP_LOOKBACK do  -- prüfe weit genug zurück / check far enough back
        local ts  = os.time() - i * 86400
        local key = os.date("%Y%m%d", ts)
        local fName = logFile(key)
        if LoadResourceFile(RESOURCE, fName) then
            -- Lock prüfen / check lock
            local lockRaw = LoadResourceFile(RESOURCE, lockFile(key)) or ""
            local locked  = false
            if lockRaw ~= "" then
                -- Prüfe ob Lock noch gültig / check if lock still valid
                local untilStr = lockRaw:match("until=(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)")
                if untilStr then
                    local y,mo,d,h,mi,s = untilStr:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
                    local lockUntil = os.time{year=y,month=mo,day=d,hour=h,min=mi,sec=s}
                    if os.time() < lockUntil then locked = true end
                end
            end
            if not locked then
                -- Datei löschen durch Überschreiben mit leerem Inhalt
                -- Delete by overwriting with empty content
                SaveResourceFile(RESOURCE, fName, "", -1)
                SaveResourceFile(RESOURCE, lockFile(key), "", -1)
                deleted = deleted + 1
            end
        end
    end
    if deleted > 0 then
        Logger.info(string.format(
            "[LOG] Auto-Cleanup: %d alte Log-Datei(en) gelöscht (Aufbewahrung: %d Tage)",
            deleted, retDays
        ))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Alle Logeinträge auch in den Disk-Puffer schreiben
-- Also write all log entries to the disk buffer
-- ─────────────────────────────────────────────────────────────────────────────
-- Originale log-Funktion patchen / Patch original log function
local _origLog = Logger.log
function Logger.log(level, message)
    _origLog(level, message)
    -- Auch in Disk-Puffer / also to disk buffer
    table.insert(diskBuffer, {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        level     = level,
        message   = message,
    })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Periodischer Flush-Thread und Cleanup-Thread
-- Periodic flush thread and cleanup thread
-- ─────────────────────────────────────────────────────────────────────────────
CreateThread(function()
    -- Initialer Cleanup beim Start / Initial cleanup on start
    Wait(3000)
    runCleanup()

    local flushInterval = (Config and Config.LogFlushInterval or 60) * 1000
    local cleanupTimer  = 0
    while true do
        Wait(flushInterval)
        flush()
        cleanupTimer = cleanupTimer + flushInterval
        -- Stündlicher Cleanup / Hourly cleanup
        if cleanupTimer >= 3600000 then
            cleanupTimer = 0
            runCleanup()
        end
    end
end)

Logger.info("Log-Persistenz aktiv / Log persistence active – Aufbewahrung: " .. ((Config and Config.LogRetentionDays) or 5) .. " Tage")
