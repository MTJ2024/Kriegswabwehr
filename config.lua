-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Konfigurationsdatei / Configuration File
-- ═══════════════════════════════════════════════════════════════════════════
-- ACHTUNG: Diese Datei wird NUR server-seitig geladen. Niemals dem Client
--          zugänglich machen! / NOTE: This file is server-side ONLY.
--          Never expose to the client!
-- ═══════════════════════════════════════════════════════════════════════════

Config = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Discord-Integration / Discord Integration
-- ─────────────────────────────────────────────────────────────────────────────
-- Discord Webhook URL für automatische Angriffswarnungen
-- Discord webhook URL for automatic attack alerts
Config.DiscordWebhook = ""

-- Farben für Discord-Embeds (Dezimalwerte)
-- Colors for Discord embeds (decimal values)
Config.DiscordColors = {
    warning  = 16776960,  -- Gelb / Yellow
    tempban  = 16744272,  -- Orange
    permban  = 16711680,  -- Rot / Red
    info     = 3447003,   -- Blau / Blue
    success  = 3066993,   -- Grün / Green
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Verbindungsschutz / Connection Protection
-- ─────────────────────────────────────────────────────────────────────────────
-- Maximale gleichzeitige Verbindungen pro IP-Adresse
-- Maximum simultaneous connections per IP address
Config.MaxConnectionsPerIP = 5

-- Maximale gleichzeitige Verbindungen pro /24-Subnetz
-- Maximum simultaneous connections per /24 subnet
Config.MaxConnectionsPerSubnet = 3

-- Dauer einer temporären Sperre in Sekunden (Standard: 1 Stunde)
-- Duration of a temporary ban in seconds (default: 1 hour)
Config.TempBanDuration = 3600

-- ─────────────────────────────────────────────────────────────────────────────
-- Rate-Limiting-Einstellungen / Rate Limiting Settings
-- ─────────────────────────────────────────────────────────────────────────────
Config.RateLimit = {
    -- Maximale Verbindungsversuche im Zeitfenster
    -- Maximum connection attempts within time window
    connections = 3,
    -- Zeitfenster in Sekunden / Time window in seconds
    timeWindow  = 10,
    -- Maximale Netz-Ereignisse pro Sekunde pro Spieler
    -- Maximum net events per second per player
    events      = 50,
    -- Maximale Datenbankabfragen pro Minute pro Spieler
    -- Maximum database queries per minute per player
    dbQueries   = 30,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Geo-Blocking / Geo Blocking
-- ─────────────────────────────────────────────────────────────────────────────
-- Liste der zu blockierenden Ländercodes (ISO 3166-1 Alpha-2)
-- List of country codes to block (ISO 3166-1 Alpha-2)
-- Beispiel/Example: {"CN", "RU", "KP"}
Config.GeoBlock = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- VPN / Proxy / Tor-Erkennung / VPN / Proxy / Tor Detection
-- ─────────────────────────────────────────────────────────────────────────────
-- VPN-Verbindungen blockieren / Block VPN connections
Config.BlockVPN = false

-- Tor-Exit-Knoten blockieren / Block Tor exit nodes
Config.BlockTor = false

-- Bekannte Proxy-Server blockieren / Block known proxy servers
Config.BlockProxy = false

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin-Konfiguration / Admin Configuration
-- ─────────────────────────────────────────────────────────────────────────────
-- Steam/License-IDs der Admins (Format: "steam:XXXXXXXXXXXXXXX" oder "license:XXXX")
-- Steam/License IDs of admins
Config.AdminIdentifiers = {
    -- "steam:110000100000001",
    -- "license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
}

-- Admin-Dashboard-Freigabe über NUI / Admin dashboard via NUI
Config.AdminDashboardEnabled = true

-- ─────────────────────────────────────────────────────────────────────────────
-- Datenbanksicherheit / Database Security
-- ─────────────────────────────────────────────────────────────────────────────
-- Datenverschlüsselung aktivieren (benötigt zusätzliche Einrichtung)
-- Enable data encryption (requires additional setup)
Config.DatabaseEncryption = false

-- SQL-Injection-Schutz aktivieren / Enable SQL injection protection
Config.SQLInjectionProtection = true

-- ─────────────────────────────────────────────────────────────────────────────
-- Protokollierung / Logging
-- ─────────────────────────────────────────────────────────────────────────────
-- Ausführliches Logging aktivieren / Enable verbose logging
Config.VerboseLogging = true

-- Logging-Level: "DEBUG", "INFO", "WARN", "ERROR"
Config.LogLevel = "INFO"

-- Protokolldatei-Rotation (Einträge pro Datei) / Log file rotation (entries per file)
Config.MaxLogEntries = 10000

-- ─────────────────────────────────────────────────────────────────────────────
-- Eskalationsstufen / Escalation Levels
-- ─────────────────────────────────────────────────────────────────────────────
Config.Escalation = {
    -- Stufe 1: Warnung / Level 1: Warning
    [1] = { action = "warn",    message = "Verbindungsversuch-Limit überschritten / Connection attempt limit exceeded" },
    -- Stufe 2: Temporäre Sperre / Level 2: Temporary ban
    [2] = { action = "tempban", duration = 3600, message = "Temporäre Sperre 1 Stunde / Temporary ban 1 hour" },
    -- Stufe 3: Permanente Sperre + Subnetzblockierung / Level 3: Permanent ban + subnet block
    [3] = { action = "permban", subnetBlock = true, discordAlert = true, message = "Permanente Sperre + Subnetzblockierung / Permanent ban + subnet block" },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- IP-Intelligence-API / IP Intelligence API
-- ─────────────────────────────────────────────────────────────────────────────
-- Kostenlose IP-API verwenden (ip-api.com) / Use free IP API (ip-api.com)
Config.IPApiUrl = "http://ip-api.com/json/"

-- API-Key (falls vorhanden, für kommerzielle API) / API key (if available, for commercial API)
Config.IPApiKey = ""

-- ─────────────────────────────────────────────────────────────────────────────
-- Ressourcen-Integritätsprüfung / Resource Integrity Check
-- ─────────────────────────────────────────────────────────────────────────────
-- Ressourcen beim Start überprüfen / Check resources on startup
Config.ResourceIntegrityCheck = true

-- Zu überwachende Ressourcen / Resources to monitor
Config.MonitoredResources = {
    "es_extended",
    "esx_identity",
    "esx_vehicleshop",
    "esx_policejob",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Angriffssignatur-Erkennung / Attack Signature Detection
-- ─────────────────────────────────────────────────────────────────────────────
Config.AttackSignatures = {
    -- Minimale Verbindungszeit in ms (zu schnell = Bot)
    -- Minimum connection time in ms (too fast = bot)
    minConnectionTimeMs = 100,
    -- Erfordert gültiges Steam-Token / Require valid Steam token
    requireSteamToken = true,
    -- Maximale identische Verbindungspakete / Maximum identical connection packets
    maxIdenticalPackets = 3,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Tarpit-Konfiguration / Tarpit Configuration
-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL: Verlangsamt NUR eingehende Verbindungen auf unserem Server.
--        Kein aktiver Angriff – reines Ressourcen-Erschöpfungs-Prinzip.
-- LEGAL: Only slows incoming connections on OUR server.
--        No active attack – pure resource exhaustion principle.
Config.Tarpit = {
    -- Tarpit aktivieren / Enable tarpit
    enabled = true,
    -- Maximale Tarpit-Dauer in ms / Maximum tarpit duration in ms
    -- (Angreifer muss Verbindung so lange offen halten / Attacker must keep connection open this long)
    maxDurationMs = 45000,   -- 45 Sekunden / seconds
    -- Mindest-Verletzungen vor Tarpit / Minimum violations before tarpit
    minViolations = 1,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Visuelle Abschreckung / Visual Deterrence
-- ─────────────────────────────────────────────────────────────────────────────
-- Zeigt dem Angreifer seine eigenen öffentlichen Daten im Ladebildschirm.
-- LEGAL: Öffentliche IP-Informationen – keine privaten Daten.
-- Shows the attacker their own PUBLIC data on the loading screen.
-- LEGAL: Public IP information only – no private data.
Config.VisualDeterrence = {
    -- Aktivieren / Enable
    enabled = true,
    -- Eigene IP anzeigen / Show own IP
    showIP = true,
    -- ISP/Anbieter anzeigen / Show ISP/provider
    showISP = true,
    -- Land und Stadt anzeigen / Show country and city
    showLocation = true,
    -- Subnetz anzeigen / Show subnet
    showSubnet = true,
    -- Warnung über ISP-Meldung anzeigen / Show ISP report warning
    showAbuseWarning = true,
    -- Referenz-ID für Strafanzeige anzeigen / Show reference ID for police report
    showRefID = true,
    -- Anzeigedauer der Adaptive Card in Sekunden (Angreifer muss warten)
    -- Display duration of the Adaptive Card in seconds (attacker must wait)
    cardDisplaySeconds = 8,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Honeypot-Modus / Honeypot Mode
-- ─────────────────────────────────────────────────────────────────────────────
-- Gebannte IPs erhalten KEINE sofortige Ablehnung, sondern werden in einer
-- Fake-Verbindungsschleife gehalten. Sie denken, sie verbinden sich, während
-- alles protokolliert wird.
-- Banned IPs do NOT get an immediate rejection – they are held in a fake
-- connection loop, thinking they are connecting while everything is logged.
Config.Honeypot = {
    -- Aktivieren / Enable
    enabled = true,
    -- Dauer der Honeypot-Täuschung in ms / Honeypot illusion duration in ms
    durationMs = 30000,   -- 30 Sekunden / seconds
    -- Nur für permanente Sperren / Only for permanent bans
    permBanOnly = false,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Automatische ISP-Missbrauchsmeldung / Automatic ISP Abuse Reporting
-- ─────────────────────────────────────────────────────────────────────────────
-- Generiert RFC-5965-ARF-Berichte und sendet sie via Discord zum Weiterleiten.
-- Generates RFC 5965 ARF reports and sends them via Discord for forwarding.
Config.AbuseReporting = {
    -- Aktivieren / Enable
    enabled = true,
    -- Ab welcher Eskalationsstufe melden / From which escalation level to report
    minLevel = 3,
}
