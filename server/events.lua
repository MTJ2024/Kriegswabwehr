-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Event-Flood-Schutz / Event Flood Protection
-- ═══════════════════════════════════════════════════════════════════════════
-- Schutz vor ESX-Event-Fluten, NUI-Event-Schutz, DB-Rate-Limiting
-- Protection against ESX event floods, NUI event guard, DB rate limiting
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- Zähler für Event-Verstöße / Event violation counters
-- ─────────────────────────────────────────────────────────────────────────────

-- Anzahl der Event-Verstöße pro Spieler / Event violation count per player
-- Format: { [source] = count }
local eventViolations = {}

-- Gesperrte Spieler (zu viele Events) / Blocked players (too many events)
-- Format: { [source] = expiry }
local eventBlocked = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Hilfsfunktionen / Helper functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Verarbeitet einen Event-Verstoß und eskaliert wenn nötig
-- Processes an event violation and escalates if needed
local function handleEventViolation(source, eventName)
    -- Sicherheitsguard: kein echter Spieler → ignorieren
    -- Safety guard: not a real player → ignore
    local rawIP = GetPlayerEndpoint(source) or ""
    local ip    = rawIP:match("^([^:]+)") or rawIP
    if ip == "" or not GetPlayerName(source) then return end

    if not eventViolations[source] then
        eventViolations[source] = 0
    end

    eventViolations[source] = eventViolations[source] + 1
    local violations = eventViolations[source]

    local playerName = GetPlayerName(source) or "Unbekannt"

    Logger.warn(string.format(
        "[EVENT-FLOOD] Spieler=%s (%s) IP=%s Event=%s Verstöße=%d",
        playerName, tostring(source), ip, eventName, violations
    ))

    if violations >= 5 then
        -- Temporär sperren und kicken / Temporary block and kick
        eventBlocked[source] = os.time() + 300  -- 5 Minuten
        IPBlocker.tempBan(ip, "Event-Flood erkannt / Event flood detected", 300, "Event Flood")
        Logger.alertAttack({
            ip              = ip,
            attackType      = "Event Flood",
            escalationLevel = 2,
            action          = "tempban",
            reason          = string.format("Spieler %s flutete Events (Event: %s)", playerName, eventName),
        })
        DropPlayer(source, "🚫 Event-Flood erkannt. Du wurdest temporär gesperrt.")

    elseif violations >= 3 then
        -- Warnung / Warning
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 100, 0},
            args  = {"[KW WARNUNG]", "Zu viele Events! Wiederholung führt zur Sperre."},
        })
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Globale Event-Abfangung / Global event interception
-- ─────────────────────────────────────────────────────────────────────────────

-- Abfangen ALLER eingehenden Netz-Ereignisse per AddEventHandler Wrapper
-- Intercept ALL incoming net events via AddEventHandler wrapper
-- Verwende FiveM's onNet-Hook für Rate-Limiting / Use FiveM's onNet hook for rate limiting

-- Erstelle einen allgemeinen Handler für Rate-Limiting
-- Create a general handler for rate limiting
local originalAddEventHandler = AddEventHandler

-- Rate-Limiter für alle registrierten Events / Rate limiter for all registered events
local function createRateLimitedHandler(eventName, handler)
    return function(...)
        local src = source
        if not src or src == 0 then
            return handler(...)
        end

        -- Temporäre Sperre prüfen / Check temporary block
        if eventBlocked[src] then
            if os.time() < eventBlocked[src] then
                return  -- Ereignis verwerfen / Drop event
            else
                eventBlocked[src] = nil
            end
        end

        -- Rate-Limit prüfen / Check rate limit
        local check = RateLimiter.checkEventRate(src)
        if not check.allowed then
            handleEventViolation(src, eventName)
            return  -- Ereignis verwerfen / Drop event
        end

        return handler(...)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ESX-spezifische Event-Schutz / ESX-specific event protection
-- ─────────────────────────────────────────────────────────────────────────────

-- Liste kritischer ESX-Events die besonders überwacht werden
-- List of critical ESX events that are especially monitored
local criticalESXEvents = {
    "esx:requestModel",
    "esx:playerLoaded",
    "esx:spawnPlayer",
    "esx_vehicleshop:buyVehicle",
    "esx_banking:depositMoney",
    "esx_banking:withdrawMoney",
    "esx_society:transferMoney",
    "esx_addonaccount:getSharedAccount",
    "esx_property:buyProperty",
    "esx_drugseller:sellDrugs",
}

-- Strenge Rate-Limiter für kritische Events (max 5 pro Minute)
-- Strict rate limiter for critical events (max 5 per minute)
local criticalEventCounters = {}

local function checkCriticalEvent(source, eventName)
    local key = source .. "_" .. eventName
    local now = os.time()

    if not criticalEventCounters[key] then
        criticalEventCounters[key] = { count = 0, resetAt = now + 60 }
    end

    local counter = criticalEventCounters[key]
    if now >= counter.resetAt then
        counter.count   = 0
        counter.resetAt = now + 60
    end

    counter.count = counter.count + 1

    if counter.count > 5 then
        local playerName = GetPlayerName(source) or "?"
        local rawIP      = GetPlayerEndpoint(source) or ""
        local ip         = rawIP:match("^([^:]+)") or rawIP
        Logger.warn(string.format(
            "[ESX-EVENT-FLOOD] Spieler=%s (%s) IP=%s kritisches Event=%s (%d/min)",
            playerName, tostring(source), ip, eventName, counter.count
        ))
        return false
    end
    return true
end

-- Registriere Handler für kritische ESX-Events
-- Register handlers for critical ESX events
for _, eventName in ipairs(criticalESXEvents) do
    local eName = eventName  -- Closure-Variable / closure variable
    AddEventHandler(eName, function(...)
        local src = source
        if src and src ~= 0 then
            if not checkCriticalEvent(src, eName) then
                -- Kritischen Event-Flood melden / Report critical event flood
                handleEventViolation(src, eName)
                return  -- Handler abbrechen / Cancel handler
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NUI-Event-Schutz / NUI event guard
-- ─────────────────────────────────────────────────────────────────────────────

-- Überwacht NUI-Callbacks auf Missbrauch / Monitors NUI callbacks for abuse
local nuiCallbackCounters = {}

-- Hilfslogik für NUI-Callbacks / Helper logic for NUI callbacks
local function checkNUICallback(source, callbackName)
    local key = source .. "_nui_" .. (callbackName or "unknown")
    local now = os.time()

    if not nuiCallbackCounters[key] then
        nuiCallbackCounters[key] = { count = 0, resetAt = now + 10 }
    end

    local counter = nuiCallbackCounters[key]
    if now >= counter.resetAt then
        counter.count   = 0
        counter.resetAt = now + 10
    end

    counter.count = counter.count + 1
    return counter.count <= 20  -- Max 20 NUI-Callbacks in 10 Sekunden
end

-- Dashboard-NUI-Callback schützen / Protect dashboard NUI callback
RegisterNetEvent("kriegswabwehr:nuiCallback", function(data)
    local src = source
    if not checkNUICallback(src, data and data.type or "unknown") then
        Logger.warn(string.format("[NUI-FLOOD] Spieler %s überflutet NUI-Callbacks", tostring(src)))
        DropPlayer(src, "🚫 NUI-Event-Flood erkannt.")
        return
    end

    -- Nur Admins dürfen Dashboard-Callbacks senden / Only admins can send dashboard callbacks
    if not AntiTheft.isAdmin(src) then return end

    -- Dashboard-Anfragen verarbeiten / Process dashboard requests
    if data and data.type == "requestStats" then
        TriggerEvent("kriegswabwehr:requestStats", src)
    elseif data and data.type == "unbanIP" and data.ip then
        TriggerEvent("kriegswabwehr:unbanIP", src, data.ip)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- MySQL-Rate-Limiter Integration / MySQL Rate Limiter Integration
-- ─────────────────────────────────────────────────────────────────────────────

-- Export-Funktion für DB-Rate-Limiting (andere Ressourcen können dies verwenden)
-- Export function for DB rate limiting (other resources can use this)
exports("checkDBRateLimit", function(source)
    if not source or source == 0 then return true end
    local check = RateLimiter.checkDBRate(source)
    if not check.allowed then
        Logger.warn(string.format(
            "[DB-FLOOD] Spieler %s überschreitet DB-Rate-Limit (%d/min)",
            tostring(source), check.count
        ))
        return false
    end
    return true
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Spieler-Bereinigung beim Trennen / Player cleanup on disconnect
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler("playerDropped", function(reason)
    local src = source
    eventViolations[src] = nil
    eventBlocked[src]    = nil
    -- Kritische Event-Zähler bereinigen / Clean critical event counters
    for key, _ in pairs(criticalEventCounters) do
        if key:sub(1, #tostring(src) + 1) == tostring(src) .. "_" then
            criticalEventCounters[key] = nil
        end
    end
end)

Logger.info("Event-Flood-Schutz aktiv / Event flood protection active")
