-- ═══════════════════════════════════════════════════════════════════════════
-- Kriegswabwehr – Client / NUI-Bridge
-- ═══════════════════════════════════════════════════════════════════════════
-- Öffnet das Admin-Dashboard als NUI und leitet Server-Daten weiter.
-- Opens the admin dashboard as NUI and forwards server data.
-- ─────────────────────────────────────────────────────────────────────────────
-- HINWEIS: Keinerlei Schutzlogik hier. Alle Schutzmaßnahmen sind server-seitig.
-- NOTE: No protection logic here. All protection is server-side only.
-- ═══════════════════════════════════════════════════════════════════════════

local dashboardOpen = false

-- ─────────────────────────────────────────────────────────────────────────────
-- Dashboard öffnen (lokal) / Open dashboard (local helper)
-- ─────────────────────────────────────────────────────────────────────────────
local function openDashboardLocal()
    if dashboardOpen then return end
    dashboardOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "open" })
    TriggerServerEvent("kriegswabwehr:requestStats")
    TriggerServerEvent("kriegswabwehr:getBanList")
end

-- Vom Server geöffnet / Opened by server
RegisterNetEvent("kriegswabwehr:openDashboard")
AddEventHandler("kriegswabwehr:openDashboard", function()
    openDashboardLocal()
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Server-Daten -> NUI / Forward server data to NUI
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:statsResponse")
AddEventHandler("kriegswabwehr:statsResponse", function(data)
    SendNUIMessage({ type = "statsUpdate", data = data })
end)

RegisterNetEvent("kriegswabwehr:banListResponse")
AddEventHandler("kriegswabwehr:banListResponse", function(data)
    SendNUIMessage({ type = "banListUpdate", data = data })
end)

RegisterNetEvent("kriegswabwehr:unbanResult")
AddEventHandler("kriegswabwehr:unbanResult", function(data)
    SendNUIMessage({ type = "unbanResult", data = data })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- NUI -> Server / Forward NUI callbacks to server
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNUICallback("close", function(data, cb)
    dashboardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "close" })
    cb({})
end)

RegisterNUICallback("requestStats", function(data, cb)
    TriggerServerEvent("kriegswabwehr:requestStats")
    cb({})
end)

RegisterNUICallback("getBanList", function(data, cb)
    TriggerServerEvent("kriegswabwehr:getBanList")
    cb({})
end)

RegisterNUICallback("unbanIP", function(data, cb)
    if data and data.ip then
        TriggerServerEvent("kriegswabwehr:unbanIP", data.ip)
    end
    cb({})
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Queue-Verwaltung / Queue management
-- ─────────────────────────────────────────────────────────────────────────────

-- Live-Queue-Update vom Server / Live queue update from server
RegisterNetEvent("kriegswabwehr:queueUpdate")
AddEventHandler("kriegswabwehr:queueUpdate", function(data)
    SendNUIMessage({ type = "queueUpdate", data = data })
end)

-- Ergebnis einer Queue-Aktion / Result of a queue action
RegisterNetEvent("kriegswabwehr:queueActionResult")
AddEventHandler("kriegswabwehr:queueActionResult", function(data)
    SendNUIMessage({ type = "queueActionResult", data = data })
end)

-- NUI: Admin genehmigt Anfrage / Admin approves request
RegisterNUICallback("approveQueue", function(data, cb)
    TriggerServerEvent("kriegswabwehr:approveQueue", data)
    cb({})
end)

-- NUI: Admin lehnt Anfrage ab / Admin denies request
RegisterNUICallback("denyQueue", function(data, cb)
    TriggerServerEvent("kriegswabwehr:denyQueue", data)
    cb({})
end)

-- NUI: Admin fordert Queue-Zustand an / Admin requests queue state
RegisterNUICallback("getQueue", function(data, cb)
    TriggerServerEvent("kriegswabwehr:getQueue")
    cb({})
end)

-- NUI: Whitelist-Eintraege abrufen / Get whitelist entries
RegisterNUICallback("getWhitelist", function(data, cb)
    TriggerServerEvent("kriegswabwehr:getWhitelist")
    cb({})
end)

-- Whitelist-Antwort vom Server / Whitelist response from server
RegisterNetEvent("kriegswabwehr:whitelistResponse")
AddEventHandler("kriegswabwehr:whitelistResponse", function(data)
    SendNUIMessage({ type = "whitelistResponse", data = data })
end)

-- NUI: Whitelist-Eintrag hinzufuegen / Add whitelist entry
RegisterNUICallback("addWhitelist", function(data, cb)
    if data and data.identifier then
        TriggerServerEvent("kriegswabwehr:addWhitelist", data)
    end
    cb({})
end)

-- NUI: Whitelist-Eintrag entfernen / Remove whitelist entry
RegisterNUICallback("removeWhitelist", function(data, cb)
    if data and data.identifier then
        TriggerServerEvent("kriegswabwehr:removeWhitelist", data)
    end
    cb({})
end)

-- Whitelist-Aktion-Ergebnis / Whitelist action result
RegisterNetEvent("kriegswabwehr:whitelistActionResult")
AddEventHandler("kriegswabwehr:whitelistActionResult", function(data)
    SendNUIMessage({ type = "whitelistActionResult", data = data })
end)

-- NUI: Spieler live sperren / Live ban player by server ID
RegisterNUICallback("banPlayer", function(data, cb)
    if data and data.targetSrc then
        TriggerServerEvent("kriegswabwehr:banPlayer", data)
    end
    cb({})
end)

-- NUI: Spieler live whitelisten / Live whitelist player by server ID
RegisterNUICallback("whitelistPlayer", function(data, cb)
    if data and data.targetSrc then
        TriggerServerEvent("kriegswabwehr:whitelistPlayer", data)
    end
    cb({})
end)

-- Ban-Spieler-Ergebnis / Ban player result
RegisterNetEvent("kriegswabwehr:banPlayerResult")
AddEventHandler("kriegswabwehr:banPlayerResult", function(data)
    SendNUIMessage({ type = "banPlayerResult", data = data })
end)



-- ─────────────────────────────────────────────────────────────────────────────
-- Log-Persistenz NUI-Callbacks / Log persistence NUI callbacks
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNUICallback("getLogDates", function(data, cb)
    TriggerServerEvent("kriegswabwehr:getLogDates")
    cb({})
end)

RegisterNUICallback("getLogByDate", function(data, cb)
    TriggerServerEvent("kriegswabwehr:getLogByDate", data)
    cb({})
end)

RegisterNUICallback("extendLogRetention", function(data, cb)
    TriggerServerEvent("kriegswabwehr:extendLogRetention", data)
    cb({})
end)

RegisterNUICallback("exportLog", function(data, cb)
    TriggerServerEvent("kriegswabwehr:exportLog", data)
    cb({})
end)

RegisterNetEvent("kriegswabwehr:logDatesResponse")
AddEventHandler("kriegswabwehr:logDatesResponse", function(data)
    SendNUIMessage({ type = "logDatesResponse", data = data })
end)

RegisterNetEvent("kriegswabwehr:logByDateResponse")
AddEventHandler("kriegswabwehr:logByDateResponse", function(data)
    SendNUIMessage({ type = "logByDateResponse", data = data })
end)

RegisterNetEvent("kriegswabwehr:logRetentionResult")
AddEventHandler("kriegswabwehr:logRetentionResult", function(data)
    SendNUIMessage({ type = "logRetentionResult", data = data })
end)

RegisterNetEvent("kriegswabwehr:logExportResponse")
AddEventHandler("kriegswabwehr:logExportResponse", function(data)
    SendNUIMessage({ type = "logExportResponse", data = data })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Periodische Aktualisierung alle 3 Sekunden wenn Dashboard offen
-- Periodic update every 3 seconds while dashboard is open
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(3000)
        if dashboardOpen then
            TriggerServerEvent("kriegswabwehr:requestStats")
        end
    end
end)

-- NUI: Queue-Modus umschalten / Toggle queue mode
RegisterNUICallback("setQueueMode", function(data, cb)
    TriggerServerEvent("kriegswabwehr:setQueueMode", data)
    cb({})
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- /kwdashboard – Chat-Befehl direkt im FiveM-Chat
-- ─────────────────────────────────────────────────────────────────────────────

RegisterCommand("kwdashboard", function()
    openDashboardLocal()
end, false)

TriggerEvent("chat:addSuggestion", "/kwdashboard", "Kriegswabwehr Admin-Dashboard öffnen (nur Admins)")

-- ─────────────────────────────────────────────────────────────────────────────
-- ESC-Taste schließt Dashboard / ESC key closes dashboard
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(0)
        if dashboardOpen and IsControlJustReleased(0, 200) then -- ESC
            dashboardOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ type = "close" })
        end
    end
end)
