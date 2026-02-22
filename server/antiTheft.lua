-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Anti-Datendiebstahl / Anti-Data-Theft
-- ═══════════════════════════════════════════════════════════════════════════
-- Skriptschutz, Datenbankabsicherung, Integritätsprüfung, Admin-Logging
-- Script protection, database security, integrity check, admin logging
-- ═══════════════════════════════════════════════════════════════════════════

AntiTheft = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- SQL-Injection-Erkennung / SQL Injection Detection
-- ─────────────────────────────────────────────────────────────────────────────

-- Bekannte SQL-Injection-Muster / Known SQL injection patterns
local SQL_PATTERNS = {
    "';",
    '";',
    "DROP%s+TABLE",
    "DROP%s+DATABASE",
    "UNION%s+SELECT",
    "OR%s+1%s*=%s*1",
    "OR%s+'1'%s*=%s*'1'",
    "xp_cmdshell",
    "EXEC%s*%(",
    "CAST%s*%(",
    "CONVERT%s*%(",
    "CHAR%s*%(",
    "DECLARE%s+@",
    "INSERT%s+INTO.*SELECT",
    "SELECT%s+.*%s+FROM%s+information_schema",
    "benchmark%s*%(",
    "sleep%s*%(",
    "waitfor%s+delay",
    "load_file%s*%(",
    "outfile%s+",
    "dumpfile%s+",
    "0x[0-9a-fA-F]+",
    "0%d+",   -- Octal
    "HAVING%s+1%s*=%s*1",
    "GROUP%s+BY.+HAVING",
    "ORDER%s+BY%s+%d",
    "--[^>]",    -- SQL comment
    "/%*.*%*/",  -- Block comment
}

-- Prüft einen String auf SQL-Injection-Muster
-- Checks a string for SQL injection patterns
-- Gibt zurück: { safe = bool, pattern = string|nil }
function AntiTheft.checkSQL(input)
    if type(input) ~= "string" then return { safe = true } end

    local upperInput = input:upper()
    for _, pattern in ipairs(SQL_PATTERNS) do
        if upperInput:match(pattern) then
            return { safe = false, pattern = pattern }
        end
    end

    return { safe = true }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Eingabe-Bereinigung / Input sanitization
-- ─────────────────────────────────────────────────────────────────────────────

-- Bereinigt eine Eingabe für sichere DB-Verwendung
-- Sanitizes input for safe DB use
function AntiTheft.sanitize(input)
    if type(input) ~= "string" then return input end
    -- Entferne gefährliche Zeichen / Remove dangerous characters
    local sanitized = input:gsub("'",  "''")
                           :gsub("\\", "\\\\")
                           :gsub("\0", "")
                           :gsub("\x1a", "")
    return sanitized
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ressourcen-Integritätsprüfung / Resource Integrity Check
-- ─────────────────────────────────────────────────────────────────────────────

-- Hashwerte der überwachten Ressourcen beim Start / Hashes of monitored resources at start
local resourceHashes = {}

-- Berechnet einen einfachen Prüfwert für eine Ressource
-- Calculates a simple checksum for a resource
local function hashResource(resourceName)
    -- FiveM's GetResourceMetadata gibt uns Metadaten zurück
    -- FiveM's GetResourceMetadata gives us metadata
    local version = GetResourceMetadata(resourceName, "version", 0) or ""
    local desc    = GetResourceMetadata(resourceName, "description", 0) or ""
    local author  = GetResourceMetadata(resourceName, "author", 0) or ""
    -- Einfacher Hash aus Metadaten / Simple hash from metadata
    local str = version .. desc .. author
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + str:byte(i)) % 2147483647
    end
    return hash
end

-- Initialisiert die Ressourcen-Überwachung
-- Initializes resource monitoring
function AntiTheft.initResourceWatch()
    if not Config.ResourceIntegrityCheck then return end

    for _, resName in ipairs(Config.MonitoredResources or {}) do
        local state = GetResourceState(resName)
        if state == "started" then
            resourceHashes[resName] = hashResource(resName)
            Logger.debug("[INTEGRITY] Baseline gesetzt für / Baseline set for: " .. resName)
        else
            Logger.warn("[INTEGRITY] Ressource nicht gestartet / Resource not started: " .. resName)
        end
    end

    Logger.info("[INTEGRITY] Ressourcen-Überwachung aktiv / Resource monitoring active")
end

-- Prüft ob Ressourcen-Hashes sich geändert haben
-- Checks whether resource hashes have changed
function AntiTheft.checkResourceIntegrity()
    if not Config.ResourceIntegrityCheck then return end

    for resName, originalHash in pairs(resourceHashes) do
        local currentHash = hashResource(resName)
        if currentHash ~= originalHash then
            Logger.error(string.format(
                "[INTEGRITY] WARNUNG: Ressource %s wurde möglicherweise manipuliert! / WARNING: Resource %s may have been tampered with!",
                resName, resName
            ))
            Logger.sendDiscord(
                "🚨 Ressourcen-Integritätsverletzung / Resource Integrity Violation",
                string.format("Ressource `%s` zeigt Änderungen seit Serverstart!", resName),
                Config.DiscordColors.permban,
                {
                    { name = "Ressource",          value = resName,                          inline = true },
                    { name = "Original-Hash",       value = tostring(originalHash),           inline = true },
                    { name = "Aktueller Hash",      value = tostring(currentHash),            inline = true },
                }
            )
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Spieler-Validierung / Player Validation
-- ─────────────────────────────────────────────────────────────────────────────

-- Prüft ob ein Spieler ein gültiges FiveM-Token hat (steam:, license:, license2:, fivem:)
-- FiveM funktioniert OHNE Steam (Epic, Social Club, usw.) – prüft alle gültigen Token-Typen.
-- Checks whether a player has any valid FiveM game token.
-- FiveM works WITHOUT Steam (Epic, Social Club, etc.) – checks all valid token types.
-- @param source      number     FiveM source ID
-- @param preloadedIds table|nil Bereits abgerufene Identifiers (vermeidet Doppel-Abruf / avoids double-fetch)
function AntiTheft.validateSteamToken(source, preloadedIds)
    if not Config.AttackSignatures.requireSteamToken then return true end
    -- Vorgeladene IDs verwenden falls vorhanden, sonst nochmal abrufen
    -- Use pre-loaded IDs if available, otherwise fetch again
    local ids = (preloadedIds and #preloadedIds > 0) and preloadedIds
                or GetPlayerIdentifiers(source) or {}
    for _, id in ipairs(ids) do
        local prefix8 = id:sub(1, 8)
        local prefix6 = id:sub(1, 6)
        -- Akzeptiere: steam:, license:, license2:, fivem:
        -- Accept:     steam:, license:, license2:, fivem:
        if prefix6 == "steam:"   then return true end
        if prefix8 == "license:" then return true end
        if prefix8 == "license2" then return true end  -- license2: (9 chars but sub(1,8)="license2")
        if prefix6 == "fivem:"   then return true end
    end
    -- Kein gültiger Token = sehr wahrscheinlich ein Bot / No valid token = very likely a bot
    return false
end

-- Prüft ob ein Spieler Admin-Rechte hat
-- Checks whether a player has admin rights
-- Ebene 1: ACE (txAdmin-Standard-Gruppen + eigene) | Ebene 2: Identifier-Listen
-- Level 1: ACE (txAdmin default groups + custom)   | Level 2: Identifier lists
function AntiTheft.isAdmin(source)
    if not source or source == 0 then return false end
    local src = tostring(source)

    -- ── ACE-Prüfungen / ACE checks ────────────────────────────────────────────
    -- txAdmin setzt group.admin + group.superadmin als ACE-Gruppen
    -- txAdmin sets group.admin + group.superadmin as ACE groups
    if IsPlayerAceAllowed(src, "group.admin")      then return true end
    if IsPlayerAceAllowed(src, "group.superadmin") then return true end
    -- Eigenes ACE / Custom ACE
    if IsPlayerAceAllowed(src, "kriegswabwehr.admin") then return true end
    -- txAdmin grants these to all admins via group.admin – reliable fallback
    -- txAdmin vergibt diese an alle Admins über group.admin – zuverlässiger Fallback
    if IsPlayerAceAllowed(src, "command.ban")  then return true end
    if IsPlayerAceAllowed(src, "command.kick") then return true end

    -- ── Identifier-Prüfungen / Identifier checks ─────────────────────────────
    local identifiers = GetPlayerIdentifiers(source) or {}
    local rawEP = GetPlayerEndpoint(tostring(source)) or ""
    local ipKey = "ip:" .. (rawEP:match("^([^:]+)") or "")

    local function matchesAny(list)
        for _, adminId in ipairs(list or {}) do
            -- Direkte IP-Prüfung / Direct IP check
            if adminId == ipKey then return true end
            -- Identifier-Vergleich / Identifier comparison
            for _, playerId in ipairs(identifiers) do
                if playerId == adminId then return true end
            end
        end
        return false
    end

    if matchesAny(Config.AdminIdentifiers)     then return true end
    if matchesAny(Config.DashboardAccessIDs)   then return true end

    -- ── Debug-Ausgabe (einmalig pro Spieler) / Debug output (once per player) ─
    if Config.Debug then
        Logger.warn(string.format(
            "[ADMIN-CHECK FAIL] src=%s name=%s – kein Admin-ACE/Identifier passt. " ..
            "Tipp: kw_whitelist check %s in txAdmin-Konsole / " ..
            "Tip: run kw_whitelist check %s in txAdmin console",
            src, tostring(GetPlayerName(source)), src, src
        ))
    end

    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Client-Schutz vor Ressourcen-Exfiltration / Client protection from resource exfiltration
-- ─────────────────────────────────────────────────────────────────────────────

-- Überwacht verdächtige Trigger von Clients
-- Monitors suspicious triggers from clients
-- Liste geschützter Events / List of protected events
local protectedEvents = {
    "esx:getSharedObject",
    "esx:onPlayerSpawned",
    "esx_banking:getAccountMoney",
    "esx_property:enterProperty",
    "esx_vehicleshop:buyVehicle",
}

-- Baut eine Whitelist für erlaubte Client->Server-Ereignisse
-- Builds a whitelist for allowed client->server events
local eventWhitelist = {}

function AntiTheft.registerAllowedEvent(eventName)
    eventWhitelist[eventName] = true
end

function AntiTheft.isEventAllowed(eventName)
    -- Alle Events erlauben wenn keine Whitelist konfiguriert
    -- Allow all events if no whitelist is configured
    if next(eventWhitelist) == nil then return true end
    return eventWhitelist[eventName] == true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lizenz-Validierungssystem / License Validation System
-- ─────────────────────────────────────────────────────────────────────────────

-- Validiert eine Ressourcenlizenz (Platzhalter für echte Implementierung)
-- Validates a resource license (placeholder for real implementation)
function AntiTheft.validateLicense(resourceName, licenseKey)
    -- In einer echten Implementierung würde hier eine Lizenz-API abgefragt
    -- In a real implementation, a license API would be queried here
    if not licenseKey or licenseKey == "" then
        Logger.warn("[LICENSE] Keine Lizenz für / No license for: " .. resourceName)
        return false
    end
    Logger.info("[LICENSE] Lizenz validiert für / License validated for: " .. resourceName)
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialisierung / Initialization
-- ─────────────────────────────────────────────────────────────────────────────

-- Periodische Integritätsprüfung alle 5 Minuten
-- Periodic integrity check every 5 minutes
CreateThread(function()
    AntiTheft.initResourceWatch()
    while true do
        Wait(300000)  -- 5 Minuten / 5 minutes
        AntiTheft.checkResourceIntegrity()
    end
end)

Logger.info("AntiTheft initialisiert / AntiTheft initialized")
