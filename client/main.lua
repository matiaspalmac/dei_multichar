-- ===== Dei Multichar - Client Main =====
-- Drop-in replacement for esx_multicharacter
-- Replicates the exact ESX multichar flow with Dei's NUI

nuiReady = false
isMulticharActive = false
local cam = nil
spawned = false
local canRelog = true
Characters = {}
slots = 0
local tempIndex = nil
local finishedCreation = false
playerPed = nil

-- ===== Camera System =====
local function SetupCamera()
    local coords = Config.CamCoords
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        coords.x, coords.y, coords.z,
        0.0, 0.0, coords.w,
        Config.CamFov, false, 0
    )
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 1, true, true)
end

local function DestroyCamera()
    if cam then
        SetCamActive(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        cam = nil
    end
end

-- ===== HUD Management =====
local function HideHud(hide)
    DisplayRadar(not hide)
    DisplayHud(not hide)
    if hide then
        MumbleSetVolumeOverride(ESX.playerId, 0.0)
    else
        MumbleSetVolumeOverride(ESX.playerId, -1.0)
    end
end

-- ===== Close NUI =====
function CloseNUI()
    SendNUIMessage({ action = 'hideMultichar' })
    SetNuiFocus(false, false)
    isMulticharActive = false
end

-- ===== Get skin for a character =====
local function GetSkin(index)
    local character = Characters[index]
    local skin = character and character.skin or Config.Default
    if character and not character.model then
        if character.sex == TranslateCap("female") then
            skin.sex = 1
        else
            skin.sex = 0
        end
    end
    return skin
end

-- ===== Check model for a character =====
function CheckModel(character)
    if not character.model and character.skin then
        if character.skin.model then
            character.model = character.skin.model
        elseif character.skin.sex == 1 then
            character.model = `mp_f_freemode_01`
        else
            character.model = `mp_m_freemode_01`
        end
    end
end

-- ===== Spawn temp ped for preview =====
local function SpawnTempPed(index)
    canRelog = false
    local skin = GetSkin(index)
    ESX.SpawnPlayer(skin, Config.PedCoords, function()
        DoScreenFadeIn(600)
        playerPed = PlayerPedId()
    end)
end

-- ===== Change existing ped appearance =====
local function ChangeExistingPed(index)
    local newCharacter = Characters[index]
    local spawnedCharacter = Characters[spawned]

    if not newCharacter.model then
        newCharacter.model = newCharacter.sex == TranslateCap("male") and `mp_m_freemode_01` or `mp_f_freemode_01`
    end

    if spawnedCharacter and spawnedCharacter.model then
        local model = ESX.Streaming.RequestModel(newCharacter.model)
        if model then
            SetPlayerModel(ESX.playerId, newCharacter.model)
            SetModelAsNoLongerNeeded(newCharacter.model)
        end
    end
    TriggerEvent("skinchanger:loadSkin", newCharacter.skin)
end

-- ===== Setup a character for preview =====
function SetupCharacter(index)
    local character = Characters[index]
    tempIndex = index

    if not spawned then
        SpawnTempPed(index)
    elseif character and character.skin then
        ChangeExistingPed(index)
    end

    spawned = index
    playerPed = PlayerPedId()

    FreezeEntityPosition(playerPed, true)
    SetPedAoBlobRendering(playerPed, true)
    SetEntityAlpha(playerPed, 255, false)
end

-- ===== Get next available slot =====
function GetNextSlot()
    for i = 1, slots do
        if not Characters[i] then
            return i
        end
    end
end

-- ===== Read Dei theme preferences from KVP =====
local function GetDeiThemePrefs()
    local theme = 'dark'
    local lightMode = false

    local prefs = GetResourceKvpString('dei_hud_prefs')
    if prefs and prefs ~= '' then
        local decoded = json.decode(prefs)
        if decoded then
            theme = decoded.theme or 'dark'
            lightMode = decoded.lightMode or false
        end
    end

    return theme, lightMode
end

-- ===== Show the NUI with character data =====
local function ShowNUI(characters)
    -- Convert characters table to format the NUI expects
    local nuiCharacters = {}
    for id, char in pairs(characters) do
        if char then
            table.insert(nuiCharacters, {
                slot = id,
                firstname = char.firstname or '',
                lastname = char.lastname or '',
                job = char.job or 'Desempleado',
                job_grade = char.job_grade or '',
                cash = char.money or 0,
                bank = char.bank or 0,
                dob = char.dateofbirth or '',
                gender = char.sex == TranslateCap("female") and 'female' or 'male',
                nationality = Config.DefaultNationality,
                disabled = char.disabled,
            })
        end
    end

    local theme, lightMode = GetDeiThemePrefs()

    SendNUIMessage({
        action = 'showMultichar',
        characters = nuiCharacters,
        maxSlots = slots,
        theme = theme,
        lightMode = lightMode,
        enableLastPlayed = Config.EnableLastPlayed,
        canDelete = Config.CanDelete,
    })
    SetNuiFocus(true, true)
    isMulticharActive = true
end

-- ===== Setup characters - main entry point =====
local function SetupCharacters()
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}

    spawned = false

    playerPed = PlayerPedId()
    local coords = Config.PedCoords
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z, true, false, false, false)
    SetEntityHeading(playerPed, coords.w)

    SetPlayerControl(ESX.playerId, false, 0)
    SetupCamera()
    HideHud(true)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    TriggerEvent("esx:loadingScreenOff")

    SetTimeout(200, function()
        TriggerServerEvent("esx_multicharacter:SetupCharacters")
    end)
end

-- ===== Load skin creator for new characters =====
local function LoadSkinCreator(skin)
    TriggerEvent("skinchanger:loadSkin", skin, function()
        DoScreenFadeIn(600)
        SetPedAoBlobRendering(playerPed, true)
        ResetEntityAlpha(playerPed)

        TriggerEvent("esx_skin:openSaveableMenu", function()
            finishedCreation = true
        end, function()
            finishedCreation = true
        end)
    end)
end

-- ===== Set default skin for new character =====
local function SetDefaultSkin(playerData)
    local skin = Config.Default[playerData.sex]
    skin.sex = playerData.sex == "m" and 0 or 1

    local model = skin.sex == 0 and `mp_m_freemode_01` or `mp_f_freemode_01`
    model = ESX.Streaming.RequestModel(model)

    if not model then
        return
    end

    SetPlayerModel(ESX.playerId, model)
    SetModelAsNoLongerNeeded(model)
    playerPed = PlayerPedId()

    LoadSkinCreator(skin)
end

-- ===== Reset state after character is loaded =====
local function Reset()
    Characters = {}
    tempIndex = nil
    playerPed = PlayerPedId()
    slots = 0
    isMulticharActive = false

    SetTimeout(10000, function()
        canRelog = true
    end)
end

-- ===== PlayerLoaded handler - spawn the character =====
local function PlayerLoaded(playerData, isNew, skin)
    DoScreenFadeOut(750)
    while IsScreenFadingOut() do
        Wait(200)
    end

    local esxSpawns = ESX.GetConfig().DefaultSpawns
    local spawn = esxSpawns[math.random(1, #esxSpawns)]

    if not isNew and playerData.coords then
        spawn = playerData.coords
    end

    if isNew or not skin or #skin == 1 then
        finishedCreation = false
        SetDefaultSkin(playerData)

        while not finishedCreation do
            Wait(200)
        end

        skin = exports["skinchanger"]:GetSkin()
        DoScreenFadeOut(500)
        while IsScreenFadingOut() do
            Wait(200)
        end
    elseif not isNew then
        TriggerEvent("skinchanger:loadSkin", skin or (Characters[spawned] and Characters[spawned].skin))
    end

    DestroyCamera()
    ESX.SpawnPlayer(skin, spawn, function()
        HideHud(false)
        SetPlayerControl(ESX.playerId, true, 0)

        playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, false)
        SetEntityCollision(playerPed, true, true)

        DoScreenFadeIn(750)

        while IsScreenFadingIn() do
            Wait(200)
        end

        TriggerServerEvent("esx:onPlayerSpawn")
        TriggerEvent("esx:onPlayerSpawn")
        TriggerEvent("esx:restoreLoadout")

        Reset()
    end)
end

-- ===== Main thread: intercept initial spawn =====
-- This replicates esx_multicharacter's main thread exactly.
-- When Config.Multichar is true in es_extended, the es_extended client
-- thread does NOT fire esx:onPlayerJoined - it waits forever.
-- esx_multicharacter (and now dei_multichar) takes over this responsibility.
CreateThread(function()
    while not ESX.PlayerLoaded do
        Wait(100)

        if NetworkIsPlayerActive(ESX.playerId) then
            ESX.DisableSpawnManager()
            DoScreenFadeOut(0)
            SetupCharacters()
            break
        end
    end
end)

-- ===== Disable controls while multichar is active =====
CreateThread(function()
    while true do
        if isMulticharActive then
            DisableAllControlActions(0)
        end
        Wait(0)
    end
end)

-- ===== Events =====

-- Server sends us character data + slots
ESX.SecureNetEvent("esx_multicharacter:SetupUI", function(data, playerSlots)
    if not nuiReady then
        print('[dei_multichar] NUI not ready yet, waiting...')
        local timeout = GetGameTimer() + 10000
        while not nuiReady and GetGameTimer() < timeout do
            Wait(100)
        end
        if not nuiReady then
            print('[dei_multichar] WARNING: NUI failed to load after 10s')
        end
    end

    DoScreenFadeOut(0)

    Characters = data or {}
    slots = playerSlots or Config.Slots

    local Character = next(Characters)
    if not Character then
        -- No characters exist at all, create first one
        canRelog = false

        ESX.SpawnPlayer(Config.Default, Config.PedCoords, function()
            DoScreenFadeIn(400)
            while IsScreenFadingIn() do
                Wait(200)
            end

            playerPed = PlayerPedId()
            SetPedAoBlobRendering(playerPed, false)
            SetEntityAlpha(playerPed, 0, false)

            TriggerServerEvent("esx_multicharacter:CharacterChosen", 1, true)
            TriggerEvent("esx_identity:showRegisterIdentity")
        end)
    else
        -- Has characters, show selection UI
        CheckModel(Characters[Character])

        if not spawned then
            SetupCharacter(Character)
        end
        Wait(500)

        ShowNUI(Characters)
    end
end)

-- Character loaded by ESX
RegisterNetEvent('esx:playerLoaded', function(playerData, isNew, skin)
    PlayerLoaded(playerData, isNew, skin)
end)

-- Player logout (for relog)
ESX.SecureNetEvent('esx:onPlayerLogout', function()
    DoScreenFadeOut(500)
    Wait(5000)

    spawned = false
    isMulticharActive = false

    SetupCharacters()
    TriggerEvent("esx_skin:resetFirstSpawn")
end)

-- Relog command
if Config.Relog then
    RegisterCommand("relog", function()
        if canRelog then
            canRelog = false
            TriggerServerEvent("esx_multicharacter:relog")

            ESX.SetTimeout(10000, function()
                canRelog = true
            end)
        end
    end, false)
end

-- NUI callbacks are in client/nui.lua

-- ===== Cleanup on resource stop =====
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    FreezeEntityPosition(ped, false)
    DisplayHud(true)
    DisplayRadar(true)
    if cam and DoesCamExist(cam) then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
    end
end)
