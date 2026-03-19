-- ===== Dei Multichar - NUI Callbacks =====
-- Handles all NUI ↔ Lua communication
-- Theme sync with Dei ecosystem (KVP + dei:themeChanged)

-- NUI ready callback
RegisterNuiCallback('nuiReady', function(_, cb)
    nuiReady = true
    cb(1)
end)

-- Select a character slot (preview ped)
RegisterNuiCallback('selectChar', function(data, cb)
    local selectedIndex = tonumber(data.slot)
    if selectedIndex and Characters[selectedIndex] then
        CheckModel(Characters[selectedIndex])
        SetupCharacter(selectedIndex)
        playerPed = PlayerPedId()
        SetPedAoBlobRendering(playerPed, true)
        ResetEntityAlpha(playerPed)
    end
    cb('ok')
end)

-- Play selected character (confirm selection)
RegisterNuiCallback('playChar', function(data, cb)
    local slot = tonumber(data.slot)
    if not slot then
        -- Fall back to currently spawned character
        slot = spawned
    end
    if slot and Characters[slot] then
        CloseNUI()
        TriggerServerEvent("esx_multicharacter:CharacterChosen", slot, false)
    end
    cb('ok')
end)

-- Create new character
RegisterNuiCallback('createChar', function(data, cb)
    local slot = GetNextSlot()
    if slot then
        CloseNUI()

        playerPed = PlayerPedId()
        SetPedAoBlobRendering(playerPed, false)
        SetEntityAlpha(playerPed, 0, false)

        TriggerServerEvent("esx_multicharacter:CharacterChosen", slot, true)
        TriggerEvent("esx_identity:showRegisterIdentity")
    end
    cb('ok')
end)

-- Delete character
RegisterNuiCallback('deleteChar', function(data, cb)
    local slot = tonumber(data.slot)
    if Config.CanDelete and slot and type(slot) == "number" then
        TriggerServerEvent("esx_multicharacter:DeleteCharacter", slot)
        spawned = false
    end
    cb('ok')
end)

-- Close NUI (escape) - don't actually close, player must pick a character
RegisterNuiCallback('closeMultichar', function(_, cb)
    cb('ok')
end)

-- ===== Listen for theme changes from dei_hud =====
RegisterNetEvent('dei:themeChanged', function(theme, lightMode)
    if isMulticharActive then
        SendNUIMessage({
            action = 'updateTheme',
            theme = theme,
            lightMode = lightMode,
        })
    end
end)
