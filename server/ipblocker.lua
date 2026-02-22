-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – IP-Blocker
-- ═══════════════════════════════════════════════════════════════════════════
-- Permanente und temporäre Sperrlisten, Subnetzblockierung, Geo-Blocking
-- Permanent and temporary ban lists, subnet blocking, geo blocking
-- ═══════════════════════════════════════════════════════════════════════════

IPBlocker = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Interne Datenspeicher / Internal data stores
-- ─────────────────────────────────────────────────────────────────────────────

-- Permanente IP-Sperren / Permanent IP bans
-- Format: { ["ip"] = { reason, timestamp, attackType } }
local permBans = {}

-- Temporäre IP-Sperren / Temporary IP bans
-- Format: { ["ip"] = { reason, expiry, attackType } }
local tempBans = {}

-- Gesperrte Subnetze (/24) / Blocked subnets (/24)
-- Format: { ["subnet"] = { reason, timestamp } }
local blockedSubnets = {}

-- Gesperrte Länder / Blocked countries
-- Format: { ["CC"] = true }
local blockedCountries = {}

-- IP-Geo-Cache / IP geo cache
-- Format: { ["ip"] = { country, isp, isVPN, isProxy, isTor, cachedAt } }
local geoCache = {}

-- Gesperrte IDs (Steam, License, etc.) / Blocked identifiers
-- Format: { ["identifier"] = { reason, timestamp } }
local blockedIdentifiers = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialisierung / Initialization
-- ─────────────────────────────────────────────────────────────────────────────

-- Geo-Block-Liste aus Config laden (Config.GeoBlock + Config.Blocklist.countries)
-- Load geo block list from config (both sources merged)
for _, cc in ipairs(Config.GeoBlock or {}) do
    blockedCountries[cc] = true
end
for _, cc in ipairs((Config.Blocklist or {}).countries or {}) do
    blockedCountries[cc] = true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Config.Blocklist beim Start laden / Load Config.Blocklist on startup
-- ─────────────────────────────────────────────────────────────────────────────
-- Alle manuellen Einträge aus config.lua werden sofort in die Live-Sperrlisten
-- übernommen. Kein Serverneustart nötig wenn du die Werte zur Laufzeit neu lädst.
-- All manual entries from config.lua are loaded into live ban lists immediately.
-- ─────────────────────────────────────────────────────────────────────────────

local function loadBlocklist()
    local bl      = Config.Blocklist or {}
    local count   = { ips = 0, subnets = 0, ids = 0 }

    -- Einzelne IPs / Single IPs
    for _, entry in ipairs(bl.ips or {}) do
        if entry.ip and entry.ip ~= "" then
            local clean = cleanIP(entry.ip)
            permBans[clean] = {
                reason     = entry.reason or "Config.Blocklist",
                timestamp  = 0,   -- 0 = statischer Eintrag / static entry
                attackType = "Static Blocklist",
                static     = true,
            }
            count.ips = count.ips + 1
        end
    end

    -- Subnetze / Subnets
    for _, entry in ipairs(bl.subnets or {}) do
        if entry.subnet and entry.subnet ~= "" then
            -- Sicherstellen dass nur 3 Oktette übergeben werden / Ensure only 3 octets
            local subnet = entry.subnet:match("^(%d+%.%d+%.%d+)") or entry.subnet
            blockedSubnets[subnet] = {
                reason    = entry.reason or "Config.Blocklist",
                timestamp = 0,
                static    = true,
            }
            count.subnets = count.subnets + 1
        end
    end

    -- Identifier / Identifiers
    for _, entry in ipairs(bl.identifiers or {}) do
        if entry.id and entry.id ~= "" then
            blockedIdentifiers[entry.id] = {
                reason    = entry.reason or "Config.Blocklist",
                timestamp = 0,
                static    = true,
            }
            count.ids = count.ids + 1
        end
    end

    Logger.info(string.format(
        "[BLOCKLIST] Geladen / Loaded: %d IPs, %d Subnetze/Subnets, %d Identifier/Identifiers",
        count.ips, count.subnets, count.ids
    ))
end

loadBlocklist()

-- ─────────────────────────────────────────────────────────────────────────────
-- Hilfsfunktionen / Helper functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Extrahiere reine IP ohne Port / Extract pure IP without port
local function cleanIP(ip)
    return ip and ip:match("^([^:]+)") or ip
end

-- Extrahiere /24-Subnetz / Extract /24 subnet
local function getSubnet(ip)
    local clean = cleanIP(ip)
    return clean and clean:match("^(%d+%.%d+%.%d+)%.%d+$") or clean
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Temporäre Sperre / Temporary ban
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.tempBan(ip, reason, duration, attackType)
    duration = duration or Config.TempBanDuration
    local clean = cleanIP(ip)
    tempBans[clean] = {
        reason     = reason,
        expiry     = os.time() + duration,
        attackType = attackType or "unknown",
        timestamp  = os.time(),
    }
    Logger.warn(string.format(
        "[TEMPBAN] IP=%s Dauer=%ds Grund=%s / Duration=%ds Reason=%s",
        clean, duration, reason, duration, reason
    ))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Permanente Sperre / Permanent ban
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.permBan(ip, reason, attackType)
    local clean = cleanIP(ip)
    permBans[clean] = {
        reason     = reason,
        timestamp  = os.time(),
        attackType = attackType or "unknown",
    }
    Logger.warn(string.format(
        "[PERMBAN] IP=%s Grund=%s / Reason=%s", clean, reason, reason
    ))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Subnetz-Blockierung / Subnet blocking
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.blockSubnet(ip, reason)
    local subnet = getSubnet(ip)
    if not subnet then return end
    blockedSubnets[subnet] = {
        reason    = reason,
        timestamp = os.time(),
    }
    Logger.warn(string.format(
        "[SUBNET-BLOCK] Subnetz=%s.0/24 Grund=%s / Subnet=%s.0/24 Reason=%s",
        subnet, reason, subnet, reason
    ))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Identifier-Sperre / Identifier ban
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.banIdentifier(identifier, reason)
    blockedIdentifiers[identifier] = {
        reason    = reason,
        timestamp = os.time(),
    }
    Logger.warn(string.format("[ID-BAN] ID=%s Grund=%s", identifier, reason))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Prüfungen / Checks
-- ─────────────────────────────────────────────────────────────────────────────

-- Prüft ob eine IP gesperrt ist (temp oder perm oder subnet)
-- Checks whether an IP is banned (temp, perm, or subnet)
-- Gibt zurück: { blocked = bool, reason = string, type = "perm"|"temp"|"subnet"|nil }
function IPBlocker.isBlocked(ip)
    local clean  = cleanIP(ip)
    local subnet = getSubnet(ip)

    -- Permanente Sperre / Permanent ban
    if permBans[clean] then
        return {
            blocked = true,
            reason  = permBans[clean].reason,
            type    = "perm",
        }
    end

    -- Temporäre Sperre (auf Ablauf prüfen) / Temporary ban (check expiry)
    if tempBans[clean] then
        if os.time() < tempBans[clean].expiry then
            local remaining = tempBans[clean].expiry - os.time()
            return {
                blocked   = true,
                reason    = tempBans[clean].reason,
                type      = "temp",
                remaining = remaining,
            }
        else
            -- Abgelaufen – entfernen / Expired – remove
            tempBans[clean] = nil
        end
    end

    -- Subnetz-Blockierung / Subnet block
    if subnet and blockedSubnets[subnet] then
        return {
            blocked = true,
            reason  = blockedSubnets[subnet].reason,
            type    = "subnet",
        }
    end

    return { blocked = false }
end

-- Prüft ob ein Identifier gesperrt ist / Checks whether an identifier is banned
function IPBlocker.isIdentifierBlocked(identifier)
    return blockedIdentifiers[identifier] ~= nil,
           blockedIdentifiers[identifier] and blockedIdentifiers[identifier].reason or nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Geo-IP-Prüfung / Geo IP check
-- ─────────────────────────────────────────────────────────────────────────────

-- Ruft Geo-IP-Informationen ab und führt Länder-/VPN-Checks durch
-- Fetches geo IP information and performs country/VPN checks
-- Callback: function(result) – result = { country, isp, isVPN, isProxy, isTor, blocked, reason }
function IPBlocker.checkGeoIP(ip, callback)
    local clean = cleanIP(ip)

    -- Cache-Treffer? / Cache hit?
    if geoCache[clean] then
        local cached = geoCache[clean]
        -- Cache 10 Minuten gültig / Cache valid for 10 minutes
        if os.time() - cached.cachedAt < 600 then
            return callback(cached)
        end
    end

    -- API-Anfrage / API request
    local url = Config.IPApiUrl .. clean .. "?fields=status,country,countryCode,isp,org,as,proxy,hosting,query"

    PerformHttpRequest(url, function(err, text, headers)
        if err ~= 200 or not text then
            Logger.warn("[GeoIP] API-Anfrage fehlgeschlagen für / API request failed for " .. clean)
            return callback({ country = "XX", isp = "Unknown", isVPN = false, isProxy = false, isTor = false, blocked = false })
        end

        local data = json.decode(text)
        if not data or data.status == "fail" then
            return callback({ country = "XX", isp = "Unknown", isVPN = false, isProxy = false, isTor = false, blocked = false })
        end

        local result = {
            ip        = clean,
            country   = data.countryCode or "XX",
            countryName = data.country or "Unknown",
            isp       = data.isp or data.org or "Unknown",
            asn       = data.as or "",
            isVPN     = data.proxy or false,
            isProxy   = data.proxy or false,
            isTor     = false,  -- ip-api.com erkennt kein Tor direkt / ip-api.com doesn't detect Tor directly
            isHosting = data.hosting or false,
            blocked   = false,
            cachedAt  = os.time(),
        }

        -- Länder-Sperre prüfen / Check country block
        if blockedCountries[result.country] then
            result.blocked = true
            result.reason  = "Geo-Block: Land/Country " .. result.country
        end

        -- VPN-Sperre prüfen / Check VPN block
        if Config.BlockVPN and result.isVPN then
            result.blocked = true
            result.reason  = "VPN/Proxy erkannt / VPN/Proxy detected"
        end

        -- Proxy-Sperre prüfen / Check proxy block
        if Config.BlockProxy and result.isProxy then
            result.blocked = true
            result.reason  = "Proxy erkannt / Proxy detected"
        end

        -- Cache speichern / Save to cache
        geoCache[clean] = result

        callback(result)
    end, "GET", "", {})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entsperren / Unban
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.unban(ip)
    local clean = cleanIP(ip)
    local removed = permBans[clean] ~= nil or tempBans[clean] ~= nil
    permBans[clean] = nil
    tempBans[clean] = nil
    if removed then
        Logger.info("[UNBAN] IP=" .. clean)
    end
    return removed
end

function IPBlocker.unblockSubnet(subnet)
    local removed = blockedSubnets[subnet] ~= nil
    blockedSubnets[subnet] = nil
    if removed then
        Logger.info("[SUBNET-UNBLOCK] Subnetz=" .. subnet)
    end
    return removed
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Export-Funktionen für Dashboard / Export functions for dashboard
-- ─────────────────────────────────────────────────────────────────────────────

function IPBlocker.getBanList()
    local list = {}
    for ip, data in pairs(permBans) do
        table.insert(list, {
            ip         = ip,
            type       = "permanent",
            reason     = data.reason,
            attackType = data.attackType,
            timestamp  = data.timestamp,
        })
    end
    for ip, data in pairs(tempBans) do
        if os.time() < data.expiry then
            table.insert(list, {
                ip         = ip,
                type       = "temporary",
                reason     = data.reason,
                attackType = data.attackType,
                expiry     = data.expiry,
                remaining  = data.expiry - os.time(),
                timestamp  = data.timestamp,
            })
        end
    end
    return list
end

function IPBlocker.getSubnetList()
    local list = {}
    for subnet, data in pairs(blockedSubnets) do
        table.insert(list, {
            subnet    = subnet .. ".0/24",
            reason    = data.reason,
            timestamp = data.timestamp,
        })
    end
    return list
end

function IPBlocker.getStats()
    local tempCount = 0
    for _, data in pairs(tempBans) do
        if os.time() < data.expiry then tempCount = tempCount + 1 end
    end
    return {
        permBans       = 0,  -- wird unten gezählt
        tempBans       = tempCount,
        blockedSubnets = 0,
        blockedCountries = #Config.GeoBlock,
    }
end

-- Zähle perm bans richtig / Count perm bans correctly
function IPBlocker.getStats()
    local permCount   = 0
    local tempCount   = 0
    local subnetCount = 0
    for _ in pairs(permBans)         do permCount   = permCount   + 1 end
    for _, d in pairs(tempBans)      do if os.time() < d.expiry then tempCount = tempCount + 1 end end
    for _ in pairs(blockedSubnets)   do subnetCount = subnetCount + 1 end
    return {
        permBans         = permCount,
        tempBans         = tempCount,
        blockedSubnets   = subnetCount,
        blockedCountries = #Config.GeoBlock,
    }
end

Logger.info("IPBlocker initialisiert / IPBlocker initialized")
