-- =============================================================================
-- Kriegswabwehr -- Live-Whitelist-Anfragen-Queue / Live Whitelist Approval Queue
-- =============================================================================
-- Wenn Config.WhitelistQueue.enabled = true:
--   Spieler die ALLE Sicherheitsprüfungen bestehen aber NICHT whitelisted sind,
--   werden in eine Warteschlange gelegt. Der Admin sieht sie live im Dashboard
--   und kann mit einem Klick Freigeben (Approve) oder Ablehnen (Deny).
--
-- Technisch: der playerConnecting-Thread schläft in einer While-Schleife.
--   Approve/Deny setzt ein Flag -> Thread wacht auf -> deferrals.done()
-- =============================================================================

WhitelistQueue = {}

-- Laufende Anfragen / Pending requests
-- Format: [token] = { name, ip, identifiers, geoData, addedAt, resolved, allow, denyReason }
local pending = {}
local tokenCounter = 0

-- ─────────────────────────────────────────────────────────────────────────────
-- Token erstellen / Create token
-- ─────────────────────────────────────────────────────────────────────────────
local function makeToken()
    tokenCounter = tokenCounter + 1
    return string.format("WLQ-%s-%04d", os.date("%H%M%S"), tokenCounter)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Alle Online-Admins benachrichtigen / Notify all online admins
-- ─────────────────────────────────────────────────────────────────────────────
local function notifyAdmins(payload)
    local players = GetPlayers()
    for _, pidStr in ipairs(players) do
        local pid = tonumber(pidStr)
        if pid and AntiTheft.isOwner(pid) then
            TriggerClientEvent("kriegswabwehr:queueUpdate", pid, payload)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot aller aktiven Anfragen / Snapshot of all active requests
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.getAll()
    local now    = os.time()
    local result = {}
    for token, req in pairs(pending) do
        if not req.resolved then
            table.insert(result, {
                token       = token,
                name        = req.name,
                ip          = req.ip,
                identifiers = req.identifiers,
                geoData     = req.geoData or {},
                addedAt     = req.addedAt,
                waitSecs    = now - req.addedAt,
                timeout     = (Config.WhitelistQueue and Config.WhitelistQueue.timeoutSeconds or 120),
            })
        end
    end
    -- Aelteste zuerst / Oldest first
    table.sort(result, function(a, b) return a.addedAt < b.addedAt end)
    return result
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anfrage hinzufuegen / Add request
-- Gibt ein Token zurück. Der playerConnecting-Thread wartet auf req.resolved.
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.add(src, name, ip, identifiers, geoData)
    local token = makeToken()
    pending[token] = {
        token       = token,
        src         = src,
        name        = name,
        ip          = ip,
        identifiers = identifiers or {},
        geoData     = geoData or {},
        addedAt     = os.time(),
        resolved    = false,
        allow       = false,
        denyReason  = "",
    }

    Logger.info(string.format(
        "[QUEUE] Neue Anfrage / New request: %s (%s) IP=%s Token=%s",
        name, tostring(src), ip, token
    ))

    -- Alle Admins benachrichtigen / Notify all admins
    notifyAdmins({
        type    = "new",
        pending = WhitelistQueue.getAll(),
    })

    return token
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anfrage genehmigen / Approve request
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.approve(token, adminSrc, addToWhitelist)
    local req = pending[token]
    if not req or req.resolved then
        return false, "Token nicht gefunden oder bereits abgeschlossen / Token not found or already resolved"
    end

    req.allow    = true
    req.resolved = true

    -- Optional: Spieler dauerhaft zur Whitelist hinzufuegen
    -- Optional: Add player permanently to whitelist
    if addToWhitelist then
        local primary = req.identifiers[1] or ("ip:" .. req.ip)
        for _, id in ipairs(req.identifiers) do
            if id:sub(1, 8) == "license:" then primary = id; break end
        end
        Whitelist.add(primary, "admin:" .. tostring(adminSrc),
            "Dashboard-Freigabe fuer / Dashboard approval for: " .. req.name)
        Logger.info(string.format(
            "[QUEUE] Freigegeben + Whitelisted: %s von Admin %s",
            req.name, tostring(adminSrc)
        ))
    else
        Logger.info(string.format(
            "[QUEUE] Freigegeben (nur diese Sitzung) / Approved (session only): %s von Admin %s",
            req.name, tostring(adminSrc)
        ))
    end

    -- Admins aktualisieren / Update admins
    notifyAdmins({
        type    = "resolved",
        token   = token,
        action  = "approved",
        pending = WhitelistQueue.getAll(),
    })

    return true, "OK"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anfrage ablehnen / Deny request
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.deny(token, adminSrc, reason)
    local req = pending[token]
    if not req or req.resolved then
        return false, "Token nicht gefunden oder bereits abgeschlossen / Token not found or already resolved"
    end

    req.allow      = false
    req.denyReason = reason or "Verbindung abgelehnt / Connection denied by admin."
    req.resolved   = true

    Logger.info(string.format(
        "[QUEUE] Abgelehnt / Denied: %s von Admin %s | Grund: %s",
        req.name, tostring(adminSrc), req.denyReason
    ))

    -- Admins aktualisieren / Update admins
    notifyAdmins({
        type    = "resolved",
        token   = token,
        action  = "denied",
        pending = WhitelistQueue.getAll(),
    })

    return true, "OK"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ergebnis einer Anfrage lesen (vom playerConnecting-Thread verwendet)
-- Read result of a request (used by playerConnecting thread)
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.getResult(token)
    local req = pending[token]
    if not req then return true, nil, "Token abgelaufen / Token expired" end
    return req.resolved, req.allow, req.denyReason
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Eintrag bereinigen / Cleanup entry
-- ─────────────────────────────────────────────────────────────────────────────
function WhitelistQueue.cleanup(token)
    pending[token] = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-Timeout: Anfragen ablaufen lassen wenn kein Admin antwortet
-- Auto-timeout: expire requests if no admin responds
-- ─────────────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)
        if not Config.WhitelistQueue then goto continue end

        local now     = os.time()
        local timeout = Config.WhitelistQueue.timeoutSeconds or 120
        local expired = {}

        for token, req in pairs(pending) do
            if not req.resolved and (now - req.addedAt) >= timeout then
                table.insert(expired, token)
            end
        end

        for _, token in ipairs(expired) do
            local req = pending[token]
            if req then
                req.resolved   = true
                req.allow      = false
                req.denyReason = Config.WhitelistQueue.timeoutMessage
                    or "Zeitüberschreitung: Kein Admin hat geantwortet. / Timeout: No admin responded."
                Logger.warn("[QUEUE] Timeout fuer / Timeout for: " .. (req.name or "?") .. " Token=" .. token)
                notifyAdmins({
                    type    = "timeout",
                    token   = token,
                    pending = WhitelistQueue.getAll(),
                })
            end
        end

        ::continue::
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Net-Events fuer Admin-Dashboard / Net events for admin dashboard
-- ─────────────────────────────────────────────────────────────────────────────

-- Admin genehmigt eine Anfrage / Admin approves a request
RegisterNetEvent("kriegswabwehr:approveQueue")
AddEventHandler("kriegswabwehr:approveQueue", function(data)
    local adminSrc       = source
    if not AntiTheft.isOwner(adminSrc) then return end
    local token          = data and data.token
    local addToWhitelist = data and data.permanent == true
    if not token then return end
    local ok, msg = WhitelistQueue.approve(token, adminSrc, addToWhitelist)
    TriggerClientEvent("kriegswabwehr:queueActionResult", adminSrc, {
        success = ok,
        token   = token,
        action  = "approve",
        msg     = msg,
    })
end)

-- Admin lehnt eine Anfrage ab / Admin denies a request
RegisterNetEvent("kriegswabwehr:denyQueue")
AddEventHandler("kriegswabwehr:denyQueue", function(data)
    local adminSrc = source
    if not AntiTheft.isOwner(adminSrc) then return end
    local token  = data and data.token
    local reason = data and data.reason
    if not token then return end
    local ok, msg = WhitelistQueue.deny(token, adminSrc, reason)
    TriggerClientEvent("kriegswabwehr:queueActionResult", adminSrc, {
        success = ok,
        token   = token,
        action  = "deny",
        msg     = msg,
    })
end)

-- Admin fordert aktuellen Queue-Zustand an / Admin requests current queue state
RegisterNetEvent("kriegswabwehr:getQueue")
AddEventHandler("kriegswabwehr:getQueue", function()
    local src = source
    if not AntiTheft.isOwner(src) then return end
    TriggerClientEvent("kriegswabwehr:queueUpdate", src, {
        type    = "snapshot",
        pending = WhitelistQueue.getAll(),
    })
end)

-- Queue-Modus ein/ausschalten (vom Dashboard-Toggle) / Toggle queue mode from dashboard
local queueModeEnabled = (Config.WhitelistQueue and Config.WhitelistQueue.enabled) or false

RegisterNetEvent("kriegswabwehr:setQueueMode")
AddEventHandler("kriegswabwehr:setQueueMode", function(data)
    local src = source
    if not AntiTheft.isOwner(src) then return end
    queueModeEnabled = (data and data.enabled == true)
    Logger.info(string.format(
        "[QUEUE] Modus geaendert von Admin %s: %s",
        tostring(src), queueModeEnabled and "AKTIV" or "INAKTIV"
    ))
    -- Config live aktualisieren / Update config live
    if Config.WhitelistQueue then
        Config.WhitelistQueue.enabled = queueModeEnabled
    end
    notifyAdmins({ type = "modeChange", enabled = queueModeEnabled })
end)

function WhitelistQueue.isEnabled()
    return queueModeEnabled
end

Logger.info("WhitelistQueue aktiv / WhitelistQueue active")
