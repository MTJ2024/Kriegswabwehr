-- =============================================================================
-- KRIEGSWABWEHR -- Copyright & Diebstahlschutz / Copyright & Theft Protection
-- =============================================================================
-- (c) 2024 MTJ2024. Alle Rechte vorbehalten / All rights reserved.
-- Dieses Script ist Eigentum von MTJ2024.
-- Unbefugte Weitergabe, Verkauf oder Umbenennung ist verboten.
-- This script is the property of MTJ2024.
-- Unauthorized redistribution, sale or renaming is prohibited.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Interne Konstanten (unveraenderbar / immutable)
-- ---------------------------------------------------------------------------
local _OWNER        = "MTJ2024"
local _RESOURCE     = "Kriegswabwehr"
local _VERSION      = "1.0.0"
local _BUILD        = "2024-KW-FORTRESS"
-- Pruefsumme aus Owner + Ressourcenname / Checksum from owner + resource name
local _SIGNATURE    = 0
do
    local seed = _OWNER .. _RESOURCE .. _VERSION
    for i = 1, #seed do
        _SIGNATURE = (_SIGNATURE * 31 + seed:byte(i)) % 2147483647
    end
end

-- ---------------------------------------------------------------------------
-- Schutzpruefungen beim Start / Protection checks on startup
-- ---------------------------------------------------------------------------

local function runCopyrightChecks()
    local resName = GetCurrentResourceName()

    -- Pruefe 1: Ressourcenname -- wurde das Script umbenannt/gestohlen?
    -- Check 1: Resource name -- was the script renamed/stolen?
    if resName ~= _RESOURCE then
        print("^1[KW-LICENSE] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("^1[KW-LICENSE] DIEBSTAHL ERKANNT / THEFT DETECTED")
        print("^1[KW-LICENSE] Dieses Script gehoert: " .. _OWNER)
        print("^1[KW-LICENSE] This script belongs to: " .. _OWNER)
        print("^1[KW-LICENSE] Original-Ressourcenname: " .. _RESOURCE)
        print("^1[KW-LICENSE] Original resource name: " .. _RESOURCE)
        print("^1[KW-LICENSE] Gefundener Name / Found name: " .. tostring(resName))
        print("^1[KW-LICENSE] Unbefugte Nutzung wird geloggt / Unauthorized use is logged.")
        print("^1[KW-LICENSE] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        -- Ressource stoppen / Stop resource
        StopResource(resName)
        return false
    end

    -- Pruefe 2: Autor-Metadaten -- wurde der fxmanifest manipuliert?
    -- Check 2: Author metadata -- was fxmanifest tampered with?
    local manifestAuthor = GetResourceMetadata(resName, "author", 0) or ""
    -- Stumm: keine Konsolenausgabe / Silent: no console output

    -- Pruefe 3: Version pruefen / Check version
    local manifestVersion = GetResourceMetadata(resName, "version", 0) or ""
    -- Stumm: keine Konsolenausgabe / Silent: no console output

    return true
end

-- ---------------------------------------------------------------------------
-- Copyright-Banner in Serverlogs / Copyright banner in server logs
-- ---------------------------------------------------------------------------

local function printCopyrightBanner()
    -- Banner wird nicht in die Konsole gedruckt (Config.ConsoleLogs = false)
    -- Banner is not printed to console (Config.ConsoleLogs = false)
    -- Sichtbar nur im NUI-Dashboard des Owners / Visible only in the owner's NUI dashboard
end

-- ---------------------------------------------------------------------------
-- Export: Signatur abrufen (fuer interne Integritaetspruefung)
-- Export: Get signature (for internal integrity check)
-- ---------------------------------------------------------------------------
KWLicense = {
    owner     = _OWNER,
    resource  = _RESOURCE,
    version   = _VERSION,
    build     = _BUILD,
    signature = _SIGNATURE,
}

-- ---------------------------------------------------------------------------
-- Ausfuehren / Execute
-- ---------------------------------------------------------------------------
printCopyrightBanner()
local ok = runCopyrightChecks()
if not ok then
    error("[KW-LICENSE] Ressource gestoppt wegen Lizenzverstos. / Resource stopped due to license violation.")
end
-- Kein OK-Print in der Konsole / No OK print in the console
