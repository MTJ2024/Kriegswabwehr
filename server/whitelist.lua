-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Whitelist-System
-- ═══════════════════════════════════════════════════════════════════════════
-- 3-EBENEN-SYSTEM / 3-LAYER SYSTEM:
--
--  Ebene 1 – txAdmin / ACE (native FiveM-Rechte)
--             IsPlayerAceAllowed(src, "kriegswabwehr.whitelist")
--             Spieler per txAdmin-Konsole hinzufügen:
--               add_principal identifier.steam:HEX group.kriegswabwehr_whitelist
--               add_ace group.kriegswabwehr_whitelist kriegswabwehr.whitelist allow
--
--  Ebene 2 – Datei-Whitelist (data/whitelist.json, persistent)
--             Per In-Game-Befehl befüllen:
--               /kw_whitelist add [Spieler-ID]
--               /kw_whitelist remove [Identifier]
--
--  Ebene 3 – Config-Fallback (config.lua)
--             Config.Whitelist + Config.AdminIdentifiers
-- ═══════════════════════════════════════════════════════════════════════════

Whitelist = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Datei-Whitelist im Speicher / File whitelist in memory
-- ─────────────────────────────────────────────────────────────────────────────
-- Format: { ["identifier"] = { addedBy, addedAt, note } }
local fileWhitelist = {}
local DATA_FILE     = "data/whitelist.json"

-- ─────────────────────────────────────────────────────────────────────────────
-- Datei laden / Load file
-- ─────────────────────────────────────────────────────────────────────────────
local function loadFile()
    local raw = LoadResourceFile(GetCurrentResourceName(), DATA_FILE)
    if not raw or raw == "" then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= "table" then
        Logger.warn("[WHITELIST] Fehler beim Laden der Datei / Error loading file: " .. DATA_FILE)
        return
    end
    local count = 0
    for _, entry in ipairs(data.entries or {}) do
        if entry.identifier and entry.identifier ~= "" then
            fileWhitelist[entry.identifier] = {
                addedBy  = entry.addedBy  or "system",
                addedAt  = entry.addedAt  or 0,
                note     = entry.note     or "",
            }
            count = count + 1
        end
    end
    Logger.info(string.format("[WHITELIST] %d Einträge aus Datei geladen / %d entries loaded from file", count, count))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Datei speichern / Save file
-- ─────────────────────────────────────────────────────────────────────────────
local function saveFile()
    local entries = {}
    for id, data in pairs(fileWhitelist) do
        table.insert(entries, {
            identifier = id,
            addedBy    = data.addedBy,
            addedAt    = data.addedAt,
            note       = data.note,
        })
    end
    -- Nach Datum sortieren / Sort by date
    table.sort(entries, function(a, b) return (a.addedAt or 0) > (b.addedAt or 0) end)

    local payload = {
        _info    = "Kriegswabwehr – Dynamische Whitelist / Dynamic Whitelist",
        _hint    = "Nicht manuell bearbeiten! Benutze: kw_whitelist add / Do not edit manually! Use: kw_whitelist add",
        _updated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        entries  = entries,
    }
    local ok, encoded = pcall(json.encode, payload)
    if ok then
        SaveResourceFile(GetCurrentResourceName(), DATA_FILE, encoded, -1)
    else
        Logger.warn("[WHITELIST] Fehler beim Speichern / Save error: " .. tostring(encoded))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Haupt-Check – alle 3 Ebenen / Main check – all 3 layers
-- ─────────────────────────────────────────────────────────────────────────────

--- Prüft ob ein Spieler whitelisted ist / Checks if a player is whitelisted
--- @param src          number    FiveM source ID
--- @param ip           string    Spieler-IP (ohne Port)
--- @param preloadedIds table|nil Bereits abgerufene Identifiers (optional, verhindert Doppel-Abruf)
--- @return boolean, string  (whitelisted, grund/reason)
function Whitelist.check(src, ip, preloadedIds)
    -- ── Ebene 1: txAdmin / ACE ────────────────────────────────────────────────
    -- Funktioniert mit txAdmin "Permissions" und server.cfg ACE-Regeln
    -- Works with txAdmin "Permissions" and server.cfg ACE rules
    if IsPlayerAceAllowed(tostring(src), "kriegswabwehr.whitelist") then
        return true, "ACE/txAdmin"
    end

    -- ── Ebene 2 & 3: Identifier-Checks ───────────────────────────────────────
    -- Verwende vorgeladene Identifiers wenn vorhanden (vermeidet Timing-Probleme)
    -- Use pre-loaded identifiers if provided (avoids timing issues)
    local playerIds = (preloadedIds and #preloadedIds > 0) and preloadedIds
                      or GetPlayerIdentifiers(src) or {}

    -- IP-Direkteintrag prüfen / Check direct IP entry
    local ipKey = "ip:" .. (ip or "")
    if fileWhitelist[ipKey] then return true, "Datei-Whitelist" end
    for _, wl in ipairs(Config.Whitelist or {}) do
        if wl == ipKey then return true, "Config-Whitelist" end
    end

    -- Identifier durchsuchen / Search identifiers
    for _, pid in ipairs(playerIds) do
        -- Ebene 2: Datei-Whitelist
        if fileWhitelist[pid] then return true, "Datei-Whitelist" end
        -- Ebene 3a: Config.Whitelist
        for _, wl in ipairs(Config.Whitelist or {}) do
            if pid == wl then return true, "Config-Whitelist" end
        end
        -- Ebene 3b: Config.AdminIdentifiers
        for _, aid in ipairs(Config.AdminIdentifiers or {}) do
            if pid == aid then return true, "Admin" end
        end
    end

    return false, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Whitelist-Eintrag hinzufügen / Add whitelist entry
-- ─────────────────────────────────────────────────────────────────────────────

--- Fügt einen Identifier zur Datei-Whitelist hinzu
--- Adds an identifier to the file whitelist
function Whitelist.add(identifier, addedBy, note)
    if not identifier or identifier == "" then return false, "Leerer Identifier / Empty identifier" end
    fileWhitelist[identifier] = {
        addedBy = addedBy or "console",
        addedAt = os.time(),
        note    = note or "",
    }
    saveFile()
    Logger.info(string.format(
        "[WHITELIST] ✅ Hinzugefügt: %s von %s / Added: %s by %s",
        identifier, tostring(addedBy), identifier, tostring(addedBy)
    ))
    return true, "OK"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Whitelist-Eintrag entfernen / Remove whitelist entry
-- ─────────────────────────────────────────────────────────────────────────────

function Whitelist.remove(identifier)
    if not fileWhitelist[identifier] then
        return false, "Nicht gefunden / Not found: " .. tostring(identifier)
    end
    fileWhitelist[identifier] = nil
    saveFile()
    Logger.info("[WHITELIST] 🗑️ Entfernt / Removed: " .. identifier)
    return true, "OK"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Alle Einträge auflisten / List all entries
-- ─────────────────────────────────────────────────────────────────────────────

function Whitelist.list()
    return fileWhitelist
end

-- ─────────────────────────────────────────────────────────────────────────────
-- In-Game / Konsolen-Befehle / In-game / console commands
-- ─────────────────────────────────────────────────────────────────────────────

RegisterCommand("kw_whitelist", function(src, args, raw)
    local isConsole = (src == 0)
    local isAdmin   = isConsole or AntiTheft.isAdmin(src)

    if not isAdmin then
        if src ~= 0 then
            TriggerClientEvent("chat:addMessage", src, {
                color = {255, 50, 50},
                args  = {"[KW]", "Keine Berechtigung / No permission."},
            })
        end
        return
    end

    local sub = args[1] and args[1]:lower() or "help"

    -- ── kw_whitelist add [Spieler-ID | Identifier] [Notiz] ──────────────────
    if sub == "add" then
        local target = args[2]
        if not target then
            print("[KW] Verwendung / Usage: kw_whitelist add [Spieler-ID oder Identifier] [Notiz]")
            return
        end

        local identifierToAdd = target
        local note = args[3] or ""

        -- Wenn eine Nummer übergeben wird, alle Identifier des Spielers holen
        -- If a number is passed, get all identifiers of that player
        local targetNum = tonumber(target)
        if targetNum then
            local ids = GetPlayerIdentifiers(targetNum) or {}
            if #ids == 0 then
                print("[KW] ❌ Spieler-ID " .. target .. " nicht gefunden / Player ID " .. target .. " not found")
                return
            end
            -- Bevorzuge license: Identifier / Prefer license: identifier
            local primary = ids[1]
            for _, id in ipairs(ids) do
                if id:sub(1, 8) == "license:" then primary = id break end
            end
            identifierToAdd = primary
            note = note ~= "" and note or ("Player: " .. (GetPlayerName(targetNum) or "?"))
            print("[KW] Füge alle Identifier von Spieler " .. target .. " hinzu...")
            -- Alle Identifier des Spielers whitelisten / Whitelist all player identifiers
            for _, id in ipairs(ids) do
                Whitelist.add(id, isConsole and "console" or tostring(src), note)
            end
            print("[KW] ✅ " .. #ids .. " Identifier von Spieler " .. (GetPlayerName(targetNum) or target) .. " whitelisted")
            return
        end

        -- Einzelner Identifier direkt / Single identifier directly
        local ok, msg = Whitelist.add(identifierToAdd, isConsole and "console" or tostring(src), note)
        print("[KW] " .. (ok and "✅ Whitelisted: " or "❌ Fehler: ") .. identifierToAdd)

    -- ── kw_whitelist remove [Identifier] ────────────────────────────────────
    elseif sub == "remove" or sub == "del" or sub == "delete" then
        local id = args[2]
        if not id then
            print("[KW] Verwendung / Usage: kw_whitelist remove [Identifier]")
            return
        end
        local ok, msg = Whitelist.remove(id)
        print("[KW] " .. (ok and "✅ Entfernt / Removed: " or "❌ " .. msg))

    -- ── kw_whitelist list ────────────────────────────────────────────────────
    elseif sub == "list" then
        local entries = Whitelist.list()
        local count   = 0
        print("[KW] ════ Whitelist (Datei / File) ════")
        for id, data in pairs(entries) do
            print(string.format("  %-55s  von/by %-15s  %s",
                id,
                tostring(data.addedBy),
                data.note ~= "" and ("| " .. data.note) or ""
            ))
            count = count + 1
        end
        print(string.format("[KW] %d Einträge / entries", count))
        print("[KW] Config.Whitelist: " .. #(Config.Whitelist or {}) .. " Einträge")
        print("[KW] Config.AdminIdentifiers: " .. #(Config.AdminIdentifiers or {}) .. " Einträge")

    -- ── kw_whitelist check [Spieler-ID] ──────────────────────────────────────
    -- Diagnose: zeigt genau welche IDs erkannt wurden und ob sie matchen
    -- Diagnose: shows exactly which IDs were detected and whether they match
    elseif sub == "check" then
        local targetNum = tonumber(args[2])
        if not targetNum then
            print("[KW] Verwendung / Usage: kw_whitelist check [Spieler-ID]")
            return
        end
        local ids   = GetPlayerIdentifiers(targetNum) or {}
        local rawIP = GetPlayerEndpoint(targetNum) or ""
        local ip    = rawIP:match("^([^:]+)") or rawIP
        local pName = GetPlayerName(targetNum) or "?"
        local aceOk = IsPlayerAceAllowed(tostring(targetNum), "kriegswabwehr.whitelist")

        print("[KW] ==== Whitelist-Diagnose fuer " .. pName .. " (ID " .. targetNum .. ") ====")
        print("[KW] IP (GetPlayerEndpoint): " .. (ip ~= "" and ip or "LEER/EMPTY"))
        print("[KW] ACE kriegswabwehr.whitelist: " .. (aceOk and "YES" or "NO"))
        print("[KW] Identifier (" .. #ids .. " gefunden / found):")
        if #ids == 0 then
            print("[KW]   WARNUNG: KEINE Identifier! Steam offline? / WARNING: NO identifiers! Steam offline?")
        end
        for _, id in ipairs(ids) do
            local inFile   = fileWhitelist[id] ~= nil
            local inConfig = false
            for _, wl in ipairs(Config.Whitelist or {}) do
                if wl == id then inConfig = true; break end
            end
            local isAdm = false
            for _, aid in ipairs(Config.AdminIdentifiers or {}) do
                if aid == id then isAdm = true; break end
            end
            local match = inFile and "Datei-WL" or inConfig and "Config-WL" or isAdm and "Admin" or "KEIN MATCH"
            print(string.format("[KW]   %-55s  -> %s", id, match))
        end
        local ipKey    = "ip:" .. ip
        local ipFile   = fileWhitelist[ipKey] ~= nil
        local ipConfig = false
        for _, wl in ipairs(Config.Whitelist or {}) do
            if wl == ipKey then ipConfig = true; break end
        end
        print(string.format("[KW]   %-55s  -> %s",
            ipKey,
            ipFile and "Datei-WL (IP)" or ipConfig and "Config-WL (IP)" or "KEIN IP-MATCH"
        ))
        print("[KW] -- Ergebnis / Result --")
        local ok, reason = Whitelist.check(targetNum, ip, ids)
        print("[KW]   " .. (ok and ("WHITELISTED via " .. reason) or "NICHT whitelisted"))
        if not ok then
            print("[KW] -- Wie whitelisten / How to whitelist --")
            print("[KW]   Option A (sofort aktiv): kw_whitelist add " .. targetNum)
            print("[KW]   Option B (in config.lua unter Config.Whitelist eintragen):")
            if #ids > 0 then
                local preferred = ids[1]
                for _, id in ipairs(ids) do
                    if id:sub(1,8) == "license:" then preferred = id; break end
                end
                print('[KW]     "' .. preferred .. '",')
            else
                print("[KW]     KEINE Identifier – Steam starten oder license: per txAdmin pruefen!")
            end
            print('[KW]   Option C (IP in Config.Whitelist): "' .. ipKey .. '",')
        end

    -- ── kw_whitelist addid [Spieler-ID] ──────────────────────────────────────
    elseif sub == "addid" or sub == "addplayer" then
        local targetNum = tonumber(args[2])
        if not targetNum then
            print("[KW] Verwendung / Usage: kw_whitelist addid [Spieler-ID]")
            return
        end
        local ids = GetPlayerIdentifiers(targetNum) or {}
        if #ids == 0 then
            print("[KW] Spieler nicht gefunden / Player not found: " .. tostring(args[2]))
            return
        end
        local pName = GetPlayerName(targetNum) or "?"
        print("[KW] Identifier von " .. pName .. ":")
        for _, id in ipairs(ids) do
            print("  " .. id)
        end
        print("[KW] Trage einen der obigen in Config.Whitelist ein oder nutze:")
        print("[KW]   kw_whitelist add " .. tostring(targetNum))

    -- ── kw_whitelist help ────────────────────────────────────────────────────
    else
        print("[KW] ==== kw_whitelist Befehle / Commands ====")
        print("[KW]  kw_whitelist add [Spieler-ID]    - Spieler per Server-ID whitelisten (alle Identifier)")
        print("[KW]  kw_whitelist add [Identifier]    - Einzelnen Identifier whitelisten (z.B. license:xxx)")
        print("[KW]  kw_whitelist remove [Identifier] - Identifier entfernen")
        print("[KW]  kw_whitelist list                - Alle Eintraege anzeigen")
        print("[KW]  kw_whitelist check [Spieler-ID]  - Diagnose: welche IDs erkannt, welche matchen")
        print("[KW]  kw_whitelist addid [Spieler-ID]  - Identifier eines Spielers anzeigen")
        print("[KW] == txAdmin / ACE (kein Neustart noetig) ==")
        print("[KW]  add_ace group.kriegswabwehr_whitelist kriegswabwehr.whitelist allow")
        print("[KW]  add_principal identifier.license:HEX group.kriegswabwehr_whitelist")
    end
end, true)

-- ─────────────────────────────────────────────────────────────────────────────
-- Beim Start laden / Load on startup
-- ─────────────────────────────────────────────────────────────────────────────
loadFile()

Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
Logger.info("  🔓 Whitelist-System aktiv / Whitelist system active   ")
Logger.info("  Ebene 1: ACE/txAdmin  |  Ebene 2: Datei  |  Ebene 3: Config")
Logger.info("  Befehl / Command: kw_whitelist help")
Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
