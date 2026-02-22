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
-- Dashboard öffnen / Open dashboard
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:openDashboard", function()
    if dashboardOpen then return end
    dashboardOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "open" })
    -- Erste Datensatz sofort anfordern / Request first dataset immediately
    TriggerServerEvent("kriegswabwehr:requestStats")
    TriggerServerEvent("kriegswabwehr:getBanList")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Server-Daten → NUI / Forward server data to NUI
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent("kriegswabwehr:statsResponse", function(data)
    SendNUIMessage({ type = "statsUpdate", data = data })
end)

RegisterNetEvent("kriegswabwehr:banListResponse", function(data)
    SendNUIMessage({ type = "banListUpdate", data = data })
end)

RegisterNetEvent("kriegswabwehr:unbanResult", function(data)
    SendNUIMessage({ type = "unbanResult", data = data })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- NUI → Server / Forward NUI callbacks to server
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
