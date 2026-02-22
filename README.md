# 🛡️ Kriegswabwehr – DDoS-Schutz & Datensicherheitssystem
### FiveM ESX Legacy GTA V RP Server Protection

> **(c) 2024 MTJ2024 – Alle Rechte vorbehalten / All rights reserved**
> Privates Script – Weitergabe, Verkauf oder Modifikation verboten.

---

## 📋 Inhaltsverzeichnis / Table of Contents
1. [Features](#-features)
2. [Voraussetzungen / Requirements](#-voraussetzungen--requirements)
3. [Installation](#-installation)
4. [Konfiguration / Configuration](#-konfiguration--configuration)
5. [Befehle / Commands](#-befehle--commands)
6. [Whitelist-System](#-whitelist-system)
7. [Blocklist / Sperrliste](#-blocklist--sperrliste)
8. [Admin-Dashboard](#-admin-dashboard)
9. [Wie Angreifer abgeschreckt werden](#-wie-angreifer-abgeschreckt-werden)
10. [Rechtlicher Hinweis / Legal Disclaimer](#-rechtlicher-hinweis--legal-disclaimer)

---

## 🔥 Features

### PRIORITÄT 1 – DDoS-Schutz (Ladebildschirm-Festung)
| Feature | Beschreibung |
|---|---|
| **playerConnecting-Fortress** | Alle Angriffe werden bereits beim Ladebildschirm abgefangen |
| **IP-Rate-Limiter** | Max. 3 Verbindungsversuche in 10 Sekunden pro IP |
| **Simultane Verbindungen** | Max. 5 gleichzeitig pro IP, max. 3 pro /24-Subnetz |
| **Eskalations-Engine** | Warnung → Temp-Ban (1h) → Perm-Ban + Subnetz-Block |
| **Verbindungsanalyse-Engine** | Auffällige Verbindungen werden bis zu 45 Sekunden einem Sicherheitsprotokoll unterzogen |
| **Sperrvalidierungsprotokoll** | Gesperrte IPs durchlaufen eine erweiterte Verbindungsprüfung |
| **Bot-Erkennung** | Kein Steam-Token = sofortiger Block |

### PRIORITÄT 2 – Visuelle Abschreckung (am Ladebildschirm)
| Feature | Beschreibung |
|---|---|
| **Adaptive Card** | Großes rotes Warndisplay direkt im FiveM-Ladebildschirm |
| **Alarm-Blink** | 4x rotes Aufblinken vor der Warnanzeige |
| **Öffentliche Daten** | Zeigt dem Angreifer seine IP, ISP, Stadt, Land, Subnetz, ASN |
| **Referenz-ID** | Eindeutige ID für jede Blockierung (für Strafanzeigen) |
| **Gesetzliche Hinweise** | § 303b StGB, § 202a StGB, CFAA, Computer Misuse Act |
| **ISP-Abuse-Report** | Automatische RFC-5965-ARF-Meldung an Discord |

### PRIORITÄT 3 – Datenschutz & Anti-Diebstahl
| Feature | Beschreibung |
|---|---|
| **Copyright-Schutz** | Script prüft beim Start ob es gestohlen/umbenannt wurde |
| **SQL-Injection-Schutz** | 25+ erkannte Muster, automatische Bereinigung |
| **Ressourcen-Integrität** | Prüft ESX-Ressourcen alle 5 Minuten auf Manipulation |
| **Admin-Action-Logging** | Alle Admin-Aktionen mit Timestamp, IP und Identifier geloggt |
| **Discord-Webhooks** | Alle kritischen Events sofort auf Discord |

---

## 📦 Voraussetzungen / Requirements

| Anforderung | Version |
|---|---|
| FiveM Server (txAdmin empfohlen) | Artifacts 5500+ |
| ESX Legacy | 1.8+ |
| oxmysql oder mysql-async | Beliebige aktuelle Version |
| txAdmin | Optional, aber empfohlen für ACE-Whitelist |

---

## 🚀 Installation

### Schritt 1 – Script herunterladen
```
Kopiere den Ordner "Kriegswabwehr" in dein /resources Verzeichnis.
Copy the "Kriegswabwehr" folder into your /resources directory.
```

### Schritt 2 – server.cfg konfigurieren
Füge folgende Zeilen in deine `server.cfg` ein **VOR** `ensure es_extended`:
```cfg
# Kriegswabwehr – DDoS Protection
ensure Kriegswabwehr

# Für ACE-Admin-Rechte (optional aber empfohlen):
add_ace group.admin kriegswabwehr.admin allow
add_ace group.admin kriegswabwehr.whitelist allow
add_principal identifier.steam:DEINE_STEAM_ID group.admin
```

### Schritt 3 – config.lua öffnen
Editiere `config.lua` und trage mindestens ein:
```lua
Config.DiscordWebhook = "https://discord.com/api/webhooks/..."
Config.AdminIdentifiers = {
    "steam:110000100000001",   -- Deine Steam-ID
}
Config.Whitelist = {
    "steam:110000100000001",   -- Deine Steam-ID (überspringt alle Checks)
}
```

### Schritt 4 – Server starten
Starte deinen Server. Im txAdmin/Server-Log siehst du:
```
╔══════════════════════════════════════════════════════════════╗
║                    KRIEGSWABWEHR  v1.0.0                     ║
║  (c) 2024 MTJ2024 -- Alle Rechte vorbehalten                ║
╚══════════════════════════════════════════════════════════════╝
[KW-LICENSE] OK -- Script läuft als legitime Kopie von MTJ2024
```

---

## ⚙️ Konfiguration / Configuration

### `config.lua` – Alle Optionen

```lua
-- Discord Webhook für Angriffswarnungen
Config.DiscordWebhook = "https://discord.com/api/webhooks/ID/TOKEN"

-- Verbindungsschutz
Config.MaxConnectionsPerIP     = 5     -- Max. gleichzeitige Verbindungen pro IP
Config.MaxConnectionsPerSubnet = 3     -- Max. gleichzeitige Verbindungen pro /24-Subnetz

-- Rate-Limiting
Config.RateLimit = {
    connections = 3,    -- Max. Versuche im Zeitfenster
    timeWindow  = 10,   -- Zeitfenster in Sekunden
    events      = 50,   -- Max. Events/Sekunde pro Spieler
    dbQueries   = 30,   -- Max. DB-Queries/Minute pro Spieler
}

-- Geo-Blocking (ISO 3166-1 Alpha-2 Ländercodes)
Config.GeoBlock = {}  -- z.B. {"CN", "RU", "KP"}

-- VPN/Proxy/Tor blockieren
Config.BlockVPN   = false
Config.BlockTor   = false
Config.BlockProxy = false

-- Tarpit (Fake-Verbindung für Angreifer)
Config.Tarpit = {
    enabled      = true,
    maxDurationMs = 45000,  -- Max. 45 Sekunden Wartezeit
    minViolations = 1,
}

-- Visuelle Abschreckung (Adaptive Card am Ladebildschirm)
Config.VisualDeterrence = {
    enabled          = true,
    showIP           = true,
    showISP          = true,
    showLocation     = true,
    showSubnet       = true,
    showAbuseWarning = true,
    showRefID        = true,
    cardDisplaySeconds = 8,  -- Anzeigedauer in Sekunden
}

-- Honeypot (Gebannte IPs in Fake-Loop halten)
Config.Honeypot = {
    enabled     = true,
    durationMs  = 30000,  -- 30 Sekunden
    permBanOnly = false,
}

-- ISP-Abuse-Report
Config.AbuseReporting = {
    enabled  = true,
    minLevel = 3,  -- Ab Eskalationsstufe 3
}
```

---

## 💬 Befehle / Commands

| Befehl | Berechtigung | Beschreibung |
|---|---|---|
| `/kwdashboard` | Admin | Admin-Dashboard öffnen |
| `kw_whitelist add [ID]` | Admin/Konsole | Spieler per Server-ID whitelisten |
| `kw_whitelist add [license:xxx]` | Admin/Konsole | Identifier direkt whitelisten |
| `kw_whitelist remove [identifier]` | Admin/Konsole | Identifier aus Whitelist entfernen |
| `kw_whitelist list` | Admin/Konsole | Alle Whitelist-Einträge anzeigen |
| `kw_whitelist addid [ID]` | Admin/Konsole | Identifier eines Spielers anzeigen |
| `kw_whitelist help` | Admin/Konsole | Hilfe anzeigen |

### Beispiele / Examples
```
# Spieler der gerade online ist (ID = 5) sofort whitelisten:
kw_whitelist add 5

# Eigene Steam-ID direkt eintragen:
kw_whitelist add steam:110000100000001

# Alle Einträge anzeigen:
kw_whitelist list
```

---

## 🔓 Whitelist-System

Das System nutzt **3 Ebenen** – du musst Spieler nicht mehr manuell in config.lua eintragen:

### Ebene 1 – txAdmin / ACE (empfohlen)
```cfg
# In server.cfg einmalig einrichten:
add_ace group.kriegswabwehr_whitelist kriegswabwehr.whitelist allow

# Spieler hinzufügen (license aus txAdmin kopieren):
add_principal identifier.license:XXXXXXXXXXXX group.kriegswabwehr_whitelist
```
→ Kein Serverneustart nötig. Funktioniert über txAdmin "Permissions" Panel.

### Ebene 2 – Dynamische Datei-Whitelist
```
# Im Spiel oder txAdmin-Konsole:
kw_whitelist add 3       # Spieler mit Server-ID 3 (alle Identifier auf einmal)
```
→ Wird in `data/whitelist.json` gespeichert, überlebt Neustarts.

### Ebene 3 – Statisch in config.lua
```lua
Config.Whitelist = {
    "steam:110000100000001",
    "license:xxxxxxxxxxxx",
    "ip:1.2.3.4",
}
```

---

## 🔒 Blocklist / Sperrliste

Trage IPs, Subnetze, Identifier und Länder direkt in `config.lua` ein:

```lua
Config.Blocklist = {
    -- Einzelne IPs permanent sperren
    ips = {
        { ip = "1.2.3.4",       reason = "DDoS Angreifer" },
        { ip = "185.220.101.1", reason = "Tor Exit Node" },
    },

    -- Komplette /24-Subnetze sperren (x.x.x.0 bis x.x.x.255)
    subnets = {
        { subnet = "185.220.101", reason = "Tor-Netzwerk" },
        { subnet = "45.155.205",  reason = "Bekannte DDoS-Range" },
    },

    -- Spieler-Identifier sperren (Steam, License, Discord)
    identifiers = {
        { id = "steam:110000100000001",  reason = "Cheater" },
        { id = "license:xxxxxxxxxxxx",   reason = "Ban-Umgehung" },
    },

    -- Länder-Blocking (ISO 3166-1 Alpha-2)
    countries = { "CN", "KP" },
}
```

---

## 🖥️ Admin-Dashboard

Öffne das Dashboard mit dem Befehl `/kwdashboard` (nur für Admins).

### Dashboard-Bereiche:
- **Live-Monitor-Kacheln** – Verbindungsversuche, Geblockt/Min, Legitime Verbindungen, Online-Spieler, Aktive Tarpits, Permanente Sperren
- **Angriffsintensitäts-Balken** – Echtzeitanzeige der aktuellen Angriffsstärke
- **Live-Graph** – Verbindungen/s und Blockierungen/s über Zeit (Chart.js)
- **Angriffskarte** – Canvas-Weltkarte mit animierten Angriffs-Markern
- **Loading-Screen-Monitor** – Vollständige Angriffslog-Tabelle (IP, Land, ISP, Typ, Status)
- **Ban-Liste** – Alle gesperrten IPs mit Unban-Funktion
- **Toast-Benachrichtigungen** – Popup-Alerts bei neuen Angriffen

---

## 🎭 Wie Angreifer abgeschreckt werden

Wenn ein Angreifer erkannt wird, läuft dieser Ablauf **automatisch**:

```
Phase 1: TARPIT
   Angreifer bleibt 8–45 Sekunden in einer Fake-"Verbindung" hängen.
   Sein Angriffstool blockiert dabei einen Thread.
   Fake-Fortschrittsbalken: "Verbindung wird hergestellt... 23%... 47%..."

Phase 2: ALARM-BLINK
   4x schnelles rotes Aufblinken im Ladebildschirm.
   Psychological shock effect.

Phase 3: ADAPTIVE CARD (Grafische Warnanzeige)
   Großes rotes Panel direkt im FiveM-Ladebildschirm zeigt:
   - Seine eigene IP-Adresse
   - Seinen ISP/Provider
   - Seine Stadt und sein Land
   - Sein /24-Subnetz
   - ASN-Nummer
   - Referenz-ID der Blockierung
   - Gesetzliche Hinweise (§303b StGB, CFAA, etc.)
   - "Dein ISP wurde benachrichtigt" (wenn Level 3)

Phase 4: ISP-ABUSE-REPORT (bei Level-3-Angriff)
   Automatischer RFC-5965-ARF Bericht über Discord-Webhook.
   Kann direkt an abuse@[isp].com weitergeleitet werden.
```

> **Warum das legal ist:** Wir zeigen dem Angreifer nur seine eigenen öffentlich zugänglichen Daten zurück. Kein aktiver Angriff, keine privaten Daten, keine Gegenaktion.

---

## ⚖️ Rechtlicher Hinweis / Legal Disclaimer

```
DIESES SCRIPT DIENT AUSSCHLIESSLICH DER DEFENSIVEN SCHUTZWIRKUNG.

Alle implementierten Maßnahmen sind rein passiver Natur:
  - IP-Blocking: Verweigerung eigener Serverressourcen
  - Tarpit: Verlangsamung eingehender Verbindungen auf UNSEREM Server
  - Visuelle Abschreckung: Anzeige öffentlicher Daten des Angreifers
  - ISP-Reports: Legale Benachrichtigung von Internetanbietern

NICHT implementiert und VERBOTEN:
  - Aktive Gegenangriffe (DDoS/DoS gegen Angreifer)
  - Unbefugter Zugriff auf Systeme Dritter
  - Einsatz von Schadsoftware
  - Exfiltration privater Daten

Rechtsgrundlagen (defensiver Einsatz erlaubt):
  - § 202a StGB (Datenschutz durch Zugangsverweigerung)
  - § 303b StGB (Computersabotage: Schutzmaßnahmen gegen diese)
  - EU-DSGVO Art. 32 (Technische Sicherheitsmaßnahmen)
  - Computer Misuse Act 1990 (UK) Section 3A (defensive tools permitted)

THIS SOFTWARE IS PROVIDED FOR DEFENSIVE PURPOSES ONLY.
The author (MTJ2024) accepts no liability for misuse.
```

---

## 📁 Dateistruktur / File Structure

```
Kriegswabwehr/
├── fxmanifest.lua          -- Resource manifest
├── config.lua              -- Alle Einstellungen / All settings
├── server/
│   ├── license.lua         -- Copyright & Diebstahlschutz (lädt als ERSTES)
│   ├── logger.lua          -- Logging + Discord Webhooks
│   ├── ratelimiter.lua     -- IP/Event/DB Rate-Limiter
│   ├── ipblocker.lua       -- Perm/Temp-Bans, Subnetz-, Geo-Blocking
│   ├── antiTheft.lua       -- SQL-Injection, Integrität, Admin-Auth
│   ├── whitelist.lua       -- 3-Ebenen-Whitelist + kw_whitelist Befehl
│   ├── tarpit.lua          -- Fake-Verbindungs-Verlangsamung
│   ├── abuseReporter.lua   -- RFC-5965-ARF ISP-Abuse-Reports
│   ├── events.lua          -- ESX-Event-Flood-Schutz
│   └── main.lua            -- playerConnecting-Festung (Hauptmodul)
├── client/
│   └── main.lua            -- NUI-Bridge (nur Dashboard, keine Schutzlogik)
├── ui/
│   ├── index.html          -- Admin-Dashboard HTML
│   ├── css/style.css       -- Dark-Theme Stylesheet
│   └── js/
│       ├── app.js          -- Dashboard-Controller
│       ├── charts.js       -- Chart.js Live-Graphen
│       └── map.js          -- Canvas-Weltkarte mit Angriffs-Markern
└── data/
    └── whitelist.json      -- Dynamische Whitelist (automatisch verwaltet)
```

---

*Kriegswabwehr (c) 2024 MTJ2024 – Privates FiveM-Schutzsystem*

