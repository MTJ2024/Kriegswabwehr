-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – IP-Rate-Limiter
-- ═══════════════════════════════════════════════════════════════════════════
-- Verfolgt Verbindungsversuche pro IP und setzt automatisch Sperren
-- Tracks connection attempts per IP and automatically enforces bans
-- ═══════════════════════════════════════════════════════════════════════════

RateLimiter = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Interner Status-Speicher / Internal state storage
-- ─────────────────────────────────────────────────────────────────────────────

-- Verbindungs-Zeitstempel pro IP / Connection timestamps per IP
-- Format: { ["ip"] = { timestamps = {}, violations = 0 } }
local ipConnections = {}

-- Aktive simultane Verbindungen / Active simultaneous connections
-- Format: { ["ip"] = count }
local activeConnections = {}

-- Subnetz-Verbindungszähler / Subnet connection counter
-- Format: { ["subnet"] = count }
local subnetConnections = {}

-- Netz-Ereignis-Zähler pro Spieler-ID / Net event counter per player source
-- Format: { [source] = { count = N, resetAt = timestamp } }
local eventCounters = {}

-- Datenbank-Abfrage-Zähler / Database query counters
-- Format: { [source] = { count = N, resetAt = timestamp } }
local dbQueryCounters = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Hilfsfunktionen / Helper functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Extrahiert das /24-Subnetz aus einer IP-Adresse
-- Extracts the /24 subnet from an IP address
local function getSubnet(ip)
    -- IPv4: "1.2.3.4:port" oder "1.2.3.4" -> "1.2.3"
    local stripped = ip:match("^(%d+%.%d+%.%d+)%.%d+") or ip:match("^(%d+%.%d+%.%d+)%.%d+:%d+$")
    if not stripped then
        -- Entferne Port falls vorhanden / Remove port if present
        stripped = ip:gsub(":%d+$", ""):match("^(%d+%.%d+%.%d+)%.%d+$")
    end
    return stripped or ip
end

-- Bereinige abgelaufene Zeitstempel aus einer Liste
-- Clean expired timestamps from a list
local function pruneTimestamps(timestamps, windowSecs)
    local now    = os.time()
    local cutoff = now - windowSecs
    local fresh  = {}
    for _, ts in ipairs(timestamps) do
        if ts > cutoff then
            table.insert(fresh, ts)
        end
    end
    return fresh
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Verbindungs-Rate-Prüfung / Connection rate check
-- ─────────────────────────────────────────────────────────────────────────────

-- Prüft ob eine IP die Verbindungsrate überschreitet
-- Checks whether an IP exceeds the connection rate
-- Gibt zurück: { allowed = bool, violations = number, reason = string }
function RateLimiter.checkConnectionRate(ip)
    if not ipConnections[ip] then
        ipConnections[ip] = { timestamps = {}, violations = 0 }
    end

    local record = ipConnections[ip]
    local window = Config.RateLimit.timeWindow
    local maxConns = Config.RateLimit.connections

    -- Abgelaufene Einträge bereinigen / Prune expired entries
    record.timestamps = pruneTimestamps(record.timestamps, window)

    -- Aktuellen Versuch hinzufügen / Add current attempt
    table.insert(record.timestamps, os.time())

    local count = #record.timestamps

    if count > maxConns then
        record.violations = record.violations + 1
        return {
            allowed    = false,
            violations = record.violations,
            count      = count,
            reason     = string.format(
                "Rate-Limit überschritten: %d Verbindungen in %ds (Max: %d) / Rate limit exceeded: %d connections in %ds (max: %d)",
                count, window, maxConns, count, window, maxConns
            ),
        }
    end

    return { allowed = true, violations = record.violations, count = count }
end

-- Gibt die Anzahl der Verstöße einer IP zurück / Returns violation count for IP
function RateLimiter.getViolations(ip)
    return (ipConnections[ip] and ipConnections[ip].violations) or 0
end

-- Setzt Verstöße zurück (nach Ablauf einer Sperre) / Reset violations (after ban expiry)
function RateLimiter.resetViolations(ip)
    if ipConnections[ip] then
        ipConnections[ip].violations = 0
        ipConnections[ip].timestamps = {}
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Simultane Verbindungen / Simultaneous connections
-- ─────────────────────────────────────────────────────────────────────────────

-- Registriert den Beginn einer Verbindung / Register start of connection
function RateLimiter.registerConnection(ip)
    local subnet = getSubnet(ip)
    activeConnections[ip]     = (activeConnections[ip]     or 0) + 1
    subnetConnections[subnet] = (subnetConnections[subnet] or 0) + 1
end

-- Hebt die Registrierung einer Verbindung auf / Deregister a connection
function RateLimiter.deregisterConnection(ip)
    local subnet = getSubnet(ip)
    activeConnections[ip]     = math.max(0, (activeConnections[ip]     or 1) - 1)
    subnetConnections[subnet] = math.max(0, (subnetConnections[subnet] or 1) - 1)
    if activeConnections[ip]     == 0 then activeConnections[ip]     = nil end
    if subnetConnections[subnet] == 0 then subnetConnections[subnet] = nil end
end

-- Prüft simultane Verbindungslimits / Checks simultaneous connection limits
-- Gibt zurück: { allowed = bool, reason = string }
function RateLimiter.checkSimultaneous(ip)
    local subnet      = getSubnet(ip)
    local ipCount     = (activeConnections[ip]     or 0)
    local subnetCount = (subnetConnections[subnet] or 0)

    if ipCount >= Config.MaxConnectionsPerIP then
        return {
            allowed = false,
            reason  = string.format(
                "Zu viele simultane Verbindungen von IP %s (%d/%d) / Too many simultaneous connections from IP %s (%d/%d)",
                ip, ipCount, Config.MaxConnectionsPerIP,
                ip, ipCount, Config.MaxConnectionsPerIP
            ),
        }
    end

    if subnetCount >= Config.MaxConnectionsPerSubnet then
        return {
            allowed = false,
            reason  = string.format(
                "Zu viele simultane Verbindungen vom Subnetz %s.x (%d/%d) / Too many simultaneous connections from subnet %s.x (%d/%d)",
                subnet, subnetCount, Config.MaxConnectionsPerSubnet,
                subnet, subnetCount, Config.MaxConnectionsPerSubnet
            ),
        }
    end

    return { allowed = true }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ereignis-Rate-Limiter / Event rate limiter
-- ─────────────────────────────────────────────────────────────────────────────

-- Prüft ob ein Spieler zu viele Netz-Ereignisse sendet
-- Checks whether a player is sending too many net events
-- Gibt zurück: { allowed = bool }
function RateLimiter.checkEventRate(source)
    local now = os.time()
    if not eventCounters[source] then
        eventCounters[source] = { count = 0, resetAt = now + 1 }
    end

    local counter = eventCounters[source]

    -- Zurücksetzen wenn Zeitfenster abgelaufen / Reset if time window expired
    if now >= counter.resetAt then
        counter.count   = 0
        counter.resetAt = now + 1
    end

    counter.count = counter.count + 1

    if counter.count > Config.RateLimit.events then
        return { allowed = false, count = counter.count }
    end

    return { allowed = true, count = counter.count }
end

-- Bereinigt Ereignis-Zähler eines getrennt verbundenen Spielers
-- Cleans up event counters for a disconnected player
function RateLimiter.cleanupPlayer(source)
    eventCounters[source]  = nil
    dbQueryCounters[source] = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Datenbank-Abfrage-Rate-Limiter / Database query rate limiter
-- ─────────────────────────────────────────────────────────────────────────────

-- Prüft ob ein Spieler zu viele DB-Abfragen auslöst
-- Checks whether a player triggers too many DB queries
function RateLimiter.checkDBRate(source)
    local now = os.time()
    if not dbQueryCounters[source] then
        dbQueryCounters[source] = { count = 0, resetAt = now + 60 }
    end

    local counter = dbQueryCounters[source]
    if now >= counter.resetAt then
        counter.count   = 0
        counter.resetAt = now + 60
    end

    counter.count = counter.count + 1

    if counter.count > Config.RateLimit.dbQueries then
        return { allowed = false, count = counter.count }
    end

    return { allowed = true, count = counter.count }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Statistik-Export (für Dashboard) / Statistics export (for dashboard)
-- ─────────────────────────────────────────────────────────────────────────────
function RateLimiter.getStats()
    local totalViolations = 0
    local uniqueIPs       = 0
    for ip, rec in pairs(ipConnections) do
        uniqueIPs = uniqueIPs + 1
        totalViolations = totalViolations + (rec.violations or 0)
    end
    return {
        uniqueIPs       = uniqueIPs,
        totalViolations = totalViolations,
        activeConns     = activeConnections,
        subnetConns     = subnetConnections,
    }
end

Logger.info("RateLimiter initialisiert / RateLimiter initialized")
