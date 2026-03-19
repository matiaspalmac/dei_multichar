-- ===== Dei Multichar - Server Main =====
-- Drop-in replacement for esx_multicharacter server-side
-- Replicates the exact esx_multicharacter flow

-- ===== Server State =====
local Server = {}
Server._index = Server
Server.oneSync = GetConvar("onesync", "off")
Server.slots = Config.Slots or 5
Server.prefix = Config.Prefix or "char"
Server.identifierType = ESX.GetConfig("Identifier") or GetConvar("sv_lan", "") == "true" and "ip" or "license"

-- ===== Database State =====
local Database = {}
Database.connected = false
Database.found = false
Database.tables = { users = "identifier" }

-- ===== Multicharacter State =====
local Multicharacter = {}
Multicharacter.awaitingRegistration = {}

-- ===== Player Tracking =====
-- ESX.Players is used by esx_multicharacter to track player states
-- When ESX Config.Multichar is true, esx_multicharacter manages ESX.Players
ESX.Players = ESX.Players or {}

-- ============================================================
-- Database Functions
-- ============================================================

function Database:GetConnection()
    local connectionString = GetConvar("mysql_connection_string", "")

    if connectionString == "" then
        error(connectionString .. "\n^1Unable to start dei_multichar - unable to determine database from mysql_connection_string^0", 0)
    elseif connectionString:find("mysql://") then
        connectionString = connectionString:sub(9, -1)
        self.name = connectionString:sub(connectionString:find("/") + 1, -1):gsub("[%?]+[%w%p]*$", "")
        self.found = true
    else
        local confPairs = { string.strsplit(";", connectionString) }
        for i = 1, #confPairs do
            local confPair = confPairs[i]
            local key, value = confPair:match("^%s*(.-)%s*=%s*(.-)%s*$")
            if key == "database" then
                self.name = value
                self.found = true
                break
            end
        end
    end
end

MySQL.ready(function()
    local length = 42 + #Server.prefix
    local DB_COLUMNS = MySQL.query.await(('SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = "%s" AND DATA_TYPE = "varchar" AND COLUMN_NAME IN (?)'):format(Database.name), {
        { "identifier", "owner" },
    })

    if DB_COLUMNS then
        local columns = {}
        local count = 0

        for i = 1, #DB_COLUMNS do
            local column = DB_COLUMNS[i]
            Database.tables[column.TABLE_NAME] = column.COLUMN_NAME

            if column?.CHARACTER_MAXIMUM_LENGTH < length then
                count = count + 1
                columns[column.TABLE_NAME] = column.COLUMN_NAME
            end
        end

        if next(columns) then
            local query = "ALTER TABLE `%s` MODIFY COLUMN `%s` VARCHAR(%s)"
            local queries = table.create(count, 0)

            for k, v in pairs(columns) do
                queries[#queries + 1] = { query = query:format(k, v, length) }
            end

            if MySQL.transaction.await(queries) then
                print(("[^2INFO^7] Updated ^5%s^7 columns to use ^5VARCHAR(%s)^7"):format(count, length))
            else
                print(("[^2INFO^7] Unable to update ^5%s^7 columns to use ^5VARCHAR(%s)^7"):format(count, length))
            end
        end

        Database.connected = true

        ESX.Jobs = ESX.GetJobs()
        while not next(ESX.Jobs) do
            Wait(500)
            ESX.Jobs = ESX.GetJobs()
        end
    end
end)

function Database:DeleteCharacter(source, charid)
    local identifier = ("%s%s:%s"):format(Server.prefix, charid, ESX.GetIdentifier(source))
    local query = "DELETE FROM `%s` WHERE %s = ?"
    local queries = {}
    local count = 0

    for tableName, column in pairs(self.tables) do
        count = count + 1
        queries[count] = { query = query:format(tableName, column), values = { identifier } }
    end

    MySQL.transaction(queries, function(result)
        if result then
            local name = GetPlayerName(source)
            print(("[^2INFO^7] Player ^5%s %s^7 has deleted a character ^5(%s)^7"):format(name, source, identifier))
            Wait(50)
            Multicharacter:SetupCharacters(source)
        else
            error("\n^1Transaction failed while trying to delete " .. identifier .. "^0")
        end
    end)
end

function Database:GetPlayerSlots(identifier)
    return MySQL.scalar.await("SELECT slots FROM multicharacter_slots WHERE identifier = ?", { identifier }) or
        Server.slots
end

function Database:GetPlayerInfo(identifier, playerSlots)
    return MySQL.query.await(
        "SELECT identifier, accounts, job, job_grade, firstname, lastname, dateofbirth, sex, skin, disabled FROM users WHERE identifier LIKE ? LIMIT ?",
        { identifier, playerSlots })
end

function Database:SetSlots(identifier, playerSlots)
    MySQL.insert("INSERT INTO `multicharacter_slots` (`identifier`, `slots`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `slots` = VALUES(`slots`)", {
        identifier,
        playerSlots,
    })
end

function Database:RemoveSlots(identifier)
    local playerSlots = MySQL.scalar.await("SELECT `slots` FROM `multicharacter_slots` WHERE identifier = ?", {
        identifier,
    })

    if playerSlots then
        MySQL.update("DELETE FROM `multicharacter_slots` WHERE `identifier` = ?", {
            identifier,
        })
        return true
    end
    return false
end

function Database:EnableSlot(identifier, slot)
    local selectedCharacter = ("char%s:%s"):format(slot, identifier)
    local updated = MySQL.update.await("UPDATE `users` SET `disabled` = 0 WHERE identifier = ?", { selectedCharacter })
    return updated > 0
end

function Database:DisableSlot(identifier, slot)
    local selectedCharacter = ("char%s:%s"):format(slot, identifier)
    local updated = MySQL.update.await("UPDATE `users` SET `disabled` = 1 WHERE identifier = ?", { selectedCharacter })
    return updated > 0
end

Database:GetConnection()

-- ============================================================
-- Multicharacter Functions
-- ============================================================

function Multicharacter:SetupCharacters(source)
    SetPlayerRoutingBucket(source, source)
    while not Database.connected do
        Wait(100)
    end

    local identifier = ESX.GetIdentifier(source)
    ESX.Players[identifier] = source

    local playerSlots = Database:GetPlayerSlots(identifier)
    local searchIdentifier = Server.prefix .. "%:" .. identifier

    local rawCharacters = Database:GetPlayerInfo(searchIdentifier, playerSlots)
    local characters

    if rawCharacters then
        local characterCount = #rawCharacters
        characters = table.create(0, characterCount)

        for i = 1, characterCount, 1 do
            local v = rawCharacters[i]
            local job, grade = v.job or "unemployed", tostring(v.job_grade)

            if ESX.Jobs[job] and ESX.Jobs[job].grades[grade] then
                if job ~= "unemployed" then
                    grade = ESX.Jobs[job].grades[grade].label
                else
                    grade = ""
                end
                job = ESX.Jobs[job].label
            end

            local accounts = json.decode(v.accounts)
            local idString = string.sub(v.identifier, #Server.prefix + 1, string.find(v.identifier, ":") - 1)
            local id = tonumber(idString)
            if id then
                characters[id] = {
                    id = id,
                    bank = accounts.bank,
                    money = accounts.money,
                    job = job,
                    job_grade = grade,
                    firstname = v.firstname,
                    lastname = v.lastname,
                    dateofbirth = v.dateofbirth,
                    skin = v.skin and json.decode(v.skin) or {},
                    disabled = v.disabled,
                    sex = v.sex == "m" and TranslateCap("male") or TranslateCap("female"),
                }
            end
        end
    end

    TriggerClientEvent("esx_multicharacter:SetupUI", source, characters, playerSlots)
end

function Multicharacter:CharacterChosen(source, charid, isNew)
    if type(charid) ~= "number" or string.len(charid) > 2 or type(isNew) ~= "boolean" then
        return
    end

    if isNew then
        self.awaitingRegistration[source] = charid
    else
        SetPlayerRoutingBucket(source, 0)
        if not ESX.GetConfig().EnableDebug then
            local identifier = ("%s%s:%s"):format(Server.prefix, charid, ESX.GetIdentifier(source))

            if ESX.GetPlayerFromIdentifier(identifier) then
                DropPlayer(source, "[dei_multichar] Your identifier " .. identifier .. " is already on the server!")
                return
            end
        end

        local charIdentifier = ("%s%s"):format(Server.prefix, charid)
        TriggerEvent("esx:onPlayerJoined", source, charIdentifier)
        ESX.Players[ESX.GetIdentifier(source)] = charIdentifier
    end
end

function Multicharacter:RegistrationComplete(source, data)
    local charId = self.awaitingRegistration[source]
    local charIdentifier = ("%s%s"):format(Server.prefix, charId)
    self.awaitingRegistration[source] = nil
    ESX.Players[ESX.GetIdentifier(source)] = charIdentifier

    SetPlayerRoutingBucket(source, 0)
    TriggerEvent("esx:onPlayerJoined", source, charIdentifier, data)
end

function Multicharacter:PlayerDropped(player)
    self.awaitingRegistration[player] = nil
    ESX.Players[ESX.GetIdentifier(player)] = nil
end

-- ============================================================
-- Server Functions (connection handling)
-- ============================================================

local function ResetPlayers()
    if next(ESX.Players) then
        local players = table.clone(ESX.Players)
        table.wipe(ESX.Players)

        for _, v in pairs(players) do
            if type(v) == "table" and v.source then
                ESX.Players[ESX.GetIdentifier(v.source)] = v.identifier
            end
        end
    else
        ESX.Players = {}
    end
end

local function OnConnecting(source, deferrals)
    deferrals.defer()
    Wait(0) -- Required
    local identifier
    local correctLicense, _ = pcall(function()
        identifier = ESX.GetIdentifier(source)
    end)

    -- luacheck: ignore
    if not SetEntityOrphanMode then
        return deferrals.done(("[dei_multichar] ESX Requires a minimum Artifact version of 10188, Please update your server."))
    end

    if Server.oneSync == "off" or Server.oneSync == "legacy" then
        return deferrals.done(("[dei_multichar] ESX Requires Onesync Infinity to work. This server currently has Onesync set to: %s"):format(Server.oneSync))
    end

    if not Database.found then
        deferrals.done("[dei_multichar] Cannot find the server's mysql_connection_string. Please make sure it is correctly configured in your server.cfg")
    end

    if not Database.connected then
        deferrals.done("[dei_multichar] OxMySQL was unable to connect to your database. Please make sure it is turned on and correctly configured in your server.cfg")
    end

    if not identifier or not correctLicense then
        return deferrals.done(("[dei_multichar] Unable to retrieve player identifier.\nIdentifier type: %s"):format(Server.identifierType))
    end

    if ESX.GetConfig().EnableDebug or not ESX.Players[identifier] then
        ESX.Players[identifier] = source
        return deferrals.done()
    end

    local function cleanupStalePlayer(staleSrc)
        deferrals.update("[dei_multichar] Cleaning stale player entry...")
        TriggerEvent("esx:onPlayerDropped", staleSrc, "esx_stale_player_obj", function()
            ESX.Players[identifier] = source
            deferrals.done()
        end)
    end

    local function reject()
        return deferrals.done(
            ("[dei_multichar] There was an error loading your character!\nError code: identifier-active\n\nThis error is caused by a player on this server who has the same identifier as you have. Make sure you are not playing on the same account.\n\nYour identifier: %s"):format(identifier)
        )
    end

    local plyRef = ESX.Players[identifier]
    if type(plyRef) == "number" then
        if GetPlayerPing(plyRef --[[@as string]]) > 0 then
            return reject()
        end
        return cleanupStalePlayer(plyRef)
    end

    local xPlayer = ESX.GetPlayerFromIdentifier(("%s:%s"):format(plyRef, identifier))
    if not xPlayer then
        ESX.Players[identifier] = source
        return deferrals.done()
    end

    if GetPlayerPing(xPlayer.source --[[@as string]]) > 0 then
        return reject()
    end

    return cleanupStalePlayer(xPlayer.source)
end

-- ============================================================
-- Event Handlers
-- ============================================================

AddEventHandler("playerConnecting", function(_, _, deferrals)
    local source = source
    OnConnecting(source, deferrals)
end)

RegisterNetEvent("esx_multicharacter:SetupCharacters", function()
    local source = source
    Multicharacter:SetupCharacters(source)
end)

RegisterNetEvent("esx_multicharacter:CharacterChosen", function(charid, isNew)
    local source = source
    Multicharacter:CharacterChosen(source, charid, isNew)
end)

AddEventHandler("esx_identity:completedRegistration", function(source, data)
    Multicharacter:RegistrationComplete(source, data)
end)

AddEventHandler("playerDropped", function()
    local source = source
    Multicharacter:PlayerDropped(source)
end)

RegisterNetEvent("esx_multicharacter:DeleteCharacter", function(charid)
    if not Config.CanDelete or type(charid) ~= "number" or string.len(charid) > 2 then
        return
    end
    local source = source
    Database:DeleteCharacter(source, charid)
end)

RegisterNetEvent("esx_multicharacter:relog", function()
    local source = source
    TriggerEvent("esx:playerLogout", source)
end)

-- ============================================================
-- Admin Commands
-- ============================================================

ESX.RegisterCommand(
    "setslots",
    "admin",
    function(xPlayer, args)
        Database:SetSlots(args.identifier, args.slots)
        xPlayer.triggerEvent("esx:showNotification", TranslateCap("slotsadd", args.slots, args.identifier))
    end,
    true,
    {
        help = TranslateCap("command_setslots"),
        validate = true,
        arguments = {
            { name = "identifier", help = TranslateCap("command_identifier"), type = "string" },
            { name = "slots", help = TranslateCap("command_slots"), type = "number" },
        },
    }
)

ESX.RegisterCommand(
    "remslots",
    "admin",
    function(xPlayer, args)
        local removed = Database:RemoveSlots(args.identifier)
        if removed then
            xPlayer.triggerEvent("esx:showNotification", TranslateCap("slotsrem", args.identifier))
        end
    end,
    true,
    {
        help = TranslateCap("command_remslots"),
        validate = true,
        arguments = {
            { name = "identifier", help = TranslateCap("command_identifier"), type = "string" },
        },
    }
)

ESX.RegisterCommand(
    "enablechar",
    "admin",
    function(xPlayer, args)
        local enabled = Database:EnableSlot(args.identifier, args.charslot)
        if enabled then
            xPlayer.triggerEvent("esx:showNotification", TranslateCap("charenabled", args.charslot, args.identifier))
        else
            xPlayer.triggerEvent("esx:showNotification", TranslateCap("charnotfound", args.charslot, args.identifier))
        end
    end,
    true,
    {
        help = TranslateCap("command_enablechar"),
        validate = true,
        arguments = {
            { name = "identifier", help = TranslateCap("command_identifier"), type = "string" },
            { name = "charslot", help = TranslateCap("command_charslot"), type = "number" },
        },
    }
)

ESX.RegisterCommand(
    "disablechar",
    "admin",
    function(xPlayer, args)
        local disabled = Database:DisableSlot(args.identifier, args.charslot)
        if disabled then
            xPlayer.triggerEvent("esx:showNotification", TranslateCap("chardisabled", args.charslot, args.identifier))
        else
            xPlayer.triggerEvent("esx:showNotification", TranslateCap("charnotfound", args.charslot, args.identifier))
        end
    end,
    true,
    {
        help = TranslateCap("command_disablechar"),
        validate = true,
        arguments = {
            { name = "identifier", help = TranslateCap("command_identifier"), type = "string" },
            { name = "charslot", help = TranslateCap("command_charslot"), type = "number" },
        },
    }
)

RegisterCommand("forcelog", function(source)
    TriggerEvent("esx:playerLogout", source)
end, true)

-- ============================================================
-- Initialize
-- ============================================================

ResetPlayers()

CreateThread(function()
    Wait(500)
    local v = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.1'
    print('^4[Dei]^0 dei_multichar v' .. v .. ' - ^2Iniciado^0 (esx_multicharacter replacement)')
end)
