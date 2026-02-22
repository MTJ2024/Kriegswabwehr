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

-- Prüft ob ein Spieler ein gültiges Steam-Token hat
-- Checks whether a player has a valid Steam token
function AntiTheft.validateSteamToken(source)
    if not Config.AttackSignatures.requireSteamToken then return true end
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers or {}) do
        if id:sub(1, 6) == "steam:" then
            return true
        end
    end
    return false
end

-- Prüft ob ein Spieler Admin-Rechte hat
-- Checks whether a player has admin rights
-- Ebene 1: ACE (txAdmin-Standard-Gruppen + eigene) | Ebene 2: Config.AdminIdentifiers
-- Level 1: ACE (txAdmin default groups + custom) | Level 2: Config.AdminIdentifiers
function AntiTheft.isAdmin(source)
    if not source or source == 0 then return false end
    local src = tostring(source)
    -- txAdmin Standard-Gruppen / txAdmin default groups (group.admin, group.superadmin)
    if IsPlayerAceAllowed(src, "group.admin")      then return true end
    if IsPlayerAceAllowed(src, "group.superadmin") then return true end
    -- Eigenes ACE-Recht / Custom ACE permission
    if IsPlayerAceAllowed(src, "kriegswabwehr.admin") then return true end
    -- Config-Fallback (Steam/License/Discord-IDs) / Config fallback
    local identifiers = GetPlayerIdentifiers(source)
    for _, adminId in ipairs(Config.AdminIdentifiers or {}) do
        for _, playerId in ipairs(identifiers or {}) do
            if playerId == adminId then
                return true
            end
        end
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
