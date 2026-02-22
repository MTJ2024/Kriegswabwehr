-- Kriegswabwehr – DDoS-Schutz und Datendiebstahlprävention für FiveM ESX Legacy
-- FiveM Resource Manifest / FiveM Ressourcen-Manifest

fx_version 'cerulean'
game 'gta5'

name        'Kriegswabwehr'
description 'DDoS-Schutzschild & Datenschutzsystem für ESX Legacy FiveM Server'
author      'MTJ2024'
version     '1.0.0'

-- ─────────────────────────────────────────────────────────────────────────────
-- Server-seitige Skripte / Server-side scripts
-- ─────────────────────────────────────────────────────────────────────────────
server_scripts {
    'server/license.lua',        -- Copyright-Schutz zuerst / Copyright protection first
    'config.lua',
    'server/logger.lua',
    'server/ratelimiter.lua',
    'server/ipblocker.lua',
    'server/antiTheft.lua',
    'server/whitelist.lua',
    'server/whitelistQueue.lua',   -- Live-Queue muss nach Whitelist geladen werden / Queue must load after whitelist
    'server/tarpit.lua',
    'server/abuseReporter.lua',
    'server/events.lua',
    'server/main.lua',
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Client-seitige Skripte / Client-side scripts
-- ─────────────────────────────────────────────────────────────────────────────
client_scripts {
    'client/main.lua',
}

-- ─────────────────────────────────────────────────────────────────────────────
-- NUI / Admin-Dashboard Dateien / Admin dashboard files
-- ─────────────────────────────────────────────────────────────────────────────
ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/css/style.css',
    'ui/js/app.js',
    'ui/js/charts.js',
    'ui/js/map.js',
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Abhängigkeiten / Dependencies (ESX Legacy)
-- ─────────────────────────────────────────────────────────────────────────────
dependencies {
    'es_extended',
}

lua54 'yes'
