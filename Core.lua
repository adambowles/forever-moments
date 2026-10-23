-- Forever Moments 1.0.0: a standalone screenshot journal for WoW: Forever.
-- No external libraries or protected combat-data processing.
local ADDON, addon = ...

addon.version = "1.0.0"
addon.defaults = {
    enabled = true,
    delay = 1.1,
    gap = 3,
    periodicMinutes = 0, -- disabled by default
    hideUI = false,
    notify = false,
    firstZonesOnly = true,
    minLootQuality = 3, -- 3 rare, 4 epic, 5 legendary, 0 any
    categories = {
        levels = true,
        achievements = true,
        criteria = true,
        bossKills = true,
        bossWipes = true,
        deaths = true,
        pvpMatches = true,
        pvpKills = true,
        duels = true,
        quests = true,
        zones = true,
        subzones = false,
        loot = true,
        recipes = true,
        renown = true,
        reputation = false,
        collections = true,
        guildAchievements = false,
        logins = false,
        scenarios = true,
    },
    stats = { succeeded = 0, failed = 0, triggered = 0 },
}

local function FillDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            if type(v) == "table" then
                t[k] = {}
                FillDefaults(t[k], v)
            else
                t[k] = v
            end
        elseif type(v) == "table" and type(t[k]) == "table" then
            FillDefaults(t[k], v)
        end
    end
end

local function Say(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff77d5ffForever Moments|r: " .. tostring(message))
    end
end
addon.Say = Say

local eventFrame = CreateFrame("Frame")
local registered = {}
local pending = {}
local dedup = {}
local busy = false
local lastAttempt = -100
local attempt = 0
local lastPeriodic = GetTime()
local nextPeriodic = nil
local hudHidden = false
local currentReason = nil

function addon.IsOn(key)
    return addon.db and addon.db.enabled and addon.db.categories[key] == true
end

local function SafeRegister(event)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if ok then registered[event] = true end
    return ok
end
addon.supportedEvents = registered

local function RestoreUI()
    if hudHidden then
        hudHidden = false
        UIParent:Show()
    end
end

local ProcessQueue
local function Schedule(delay)
    -- Multiple independent schedules are harmless: ProcessQueue is guarded.
    C_Timer.After(math.max(delay, 0.02), function() ProcessQueue() end)
end

local function CompleteScreenshot(success, timeout)
    if not busy then return end
    busy = false
    RestoreUI()
    if success then
        addon.db.stats.succeeded = addon.db.stats.succeeded + 1
        if addon.db.notify then Say("Saved: " .. (currentReason or "Moment")) end
    elseif not timeout then
        addon.db.stats.failed = addon.db.stats.failed + 1
        Say("Screenshot failed (check the game's Screenshots folder and permissions).")
    end
    currentReason = nil
    Schedule(0.05)
end

local function Capture(entry)
    if type(Screenshot) ~= "function" then
        Say("The Screenshot() API is not available in this client.")
        busy = false
        return
    end
    busy = true
    attempt = attempt + 1
    local thisAttempt = attempt
    currentReason = entry.reason
    lastAttempt = GetTime()

    local function Take()
        if not busy or attempt ~= thisAttempt then return end
        local ok = pcall(Screenshot)
        if not ok then CompleteScreenshot(false, false) end
    end

    -- The HUD remains visible by default. Hiding it in combat is forbidden.
    if addon.db.hideUI and not InCombatLockdown() and UIParent:IsShown() then
        UIParent:Hide()
        hudHidden = true
        C_Timer.After(0.10, Take)
    else
        Take()
    end

    -- Screenshot events normally arrive quickly. This is only a recovery
    -- mechanism, NOT a claim that a screenshot was successfully written.
    C_Timer.After(3.0, function()
        if busy and attempt == thisAttempt then
            CompleteScreenshot(false, true)
        end
    end)
end

ProcessQueue = function()
    if busy or not addon.db then return end
    if #pending == 0 then return end
    if not addon.db.enabled then
        -- Manual screenshots remain available while automation is paused.
        for i = #pending, 1, -1 do
            if not pending[i].forced then table.remove(pending, i) end
        end
        if #pending == 0 then return end
    end

    local now = GetTime()
    local entry = pending[1]
    -- Do not take a screenshot for a moment that has become very stale.
    if now - entry.queuedAt > 18 then
        table.remove(pending, 1)
        Schedule(0.02)
        return
    end
    local wait = math.max(entry.readyAt - now, addon.db.gap - (now - lastAttempt))
    if wait > 0 then
        Schedule(wait)
        return
    end
    table.remove(pending, 1)
    Capture(entry)
end

-- Event snapshots are delayed slightly to preserve the level-up effect,
-- completion toast, victory animation, or newly looted item on the HUD.
function addon.Queue(category, token, reason, customDelay, forced)
    if not addon.db then return end
    if not forced and (not addon.db.enabled or not addon.db.categories[category]) then return end
    local now = GetTime()
    local key = category .. ":" .. tostring(token or "event")
    if not forced and dedup[key] and now - dedup[key] < 6 then return end
    dedup[key] = now
    if #pending >= 8 then
        -- Prefer the latest meaningful moment over building a stale backlog.
        table.remove(pending, #pending)
    end
    local delay = customDelay
    if delay == nil then delay = addon.db.delay end
    local item = { reason = reason, queuedAt = now, readyAt = now + delay, forced = forced }
    local index = #pending + 1
    for i = 1, #pending do
        if pending[i].readyAt > item.readyAt then index = i; break end
    end
    table.insert(pending, index, item)
    addon.db.stats.triggered = addon.db.stats.triggered + 1
    Schedule(0.02)
end

local function ZoneCapture(isSubzone)
    local category = isSubzone and "subzones" or "zones"
    if not addon.IsOn(category) then return end
    local zone = isSubzone and GetSubZoneText() or GetZoneText()
    if type(zone) ~= "string" or zone == "" then return end
    -- Avoid counting the same subzone twice in two separate main zones.
    if isSubzone then zone = (GetZoneText() or "") .. "/" .. zone end
    local ledger = isSubzone and addon.charDB.subzones or addon.charDB.zones
    if addon.db.firstZonesOnly and ledger[zone] then return end
    ledger[zone] = true
    addon.Queue(category, zone, (isSubzone and "Subzone: " or "Zone: ") .. zone, 2)
end

local function CheckLoot(message)
    if not addon.IsOn("loot") or type(message) ~= "string" then return end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    if not itemID then return end

    local function Evaluate()
        local quality
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
            if ok then quality = q end
        end
        -- Chat links already carry the quality colour. Useful while item
        -- details are still being fetched from the server / item cache.
        if quality == nil then
            local hex = message:lower():match("|cff(%x%x%x%x%x%x)|hitem:")
            local colours = {
                ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
                ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
                ["e6cc80"] = 6, ["00ccff"] = 7,
            }
            quality = hex and colours[hex]
        end
        -- Unknown-quality or protected linked loot is saved too: prefer extra
        -- screenshots to errors or losing a memorable drop.
        local ok, eligible = pcall(function()
            return quality == nil or quality >= addon.db.minLootQuality
        end)
        if not ok or eligible then
            addon.Queue("loot", itemID, "Item loot #" .. itemID, 1.1)
        end
    end
    Evaluate()
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON then return end
        if type(ForeverMomentsDB) ~= "table" then ForeverMomentsDB = {} end
        if type(ForeverMomentsCharDB) ~= "table" then ForeverMomentsCharDB = {} end
        FillDefaults(ForeverMomentsDB, addon.defaults)
        addon.db = ForeverMomentsDB
        addon.charDB = ForeverMomentsCharDB
        addon.charDB.zones = addon.charDB.zones or {}
        addon.charDB.subzones = addon.charDB.subzones or {}

        -- An absent beta-only event must not prevent the addon loading.
        for _, name in ipairs({
            "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
            "PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED", "CRITERIA_EARNED",
            "ENCOUNTER_END", "PLAYER_DEAD", "PVP_MATCH_COMPLETE", "PLAYER_PVP_KILLS_CHANGED",
            "DUEL_FINISHED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
            "CHAT_MSG_LOOT", "NEW_RECIPE_LEARNED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
            "PLAYER_PVP_RANK_CHANGED", "CHAT_MSG_COMBAT_FACTION_CHANGE",
            "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED",
            "CHAT_MSG_GUILD_ACHIEVEMENT", "SCENARIO_COMPLETED", "CHALLENGE_MODE_COMPLETED",
        }) do
            SafeRegister(name)
        end
        if addon.BuildOptions then addon.BuildOptions() end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        return
    end

    if not addon.db then return end
    if event == "SCREENSHOT_SUCCEEDED" then
        CompleteScreenshot(true, false)
        return
    elseif event == "SCREENSHOT_FAILED" then
        CompleteScreenshot(false, false)
        return
    elseif event == "PLAYER_LOGIN" then
        lastPeriodic = GetTime()
        -- Periodic screenshots run on a low-frequency lightweight ticker.
        C_Timer.NewTicker(15, function()
            if not addon.db or not addon.db.enabled then return end
            local minutes = tonumber(addon.db.periodicMinutes) or 0
            if minutes <= 0 then
                nextPeriodic = nil
                return
            end
            local now = GetTime()
            if not nextPeriodic then nextPeriodic = now + 60 * minutes end
            if now >= nextPeriodic then
                nextPeriodic = now + 60 * minutes
                addon.Queue("periodic", math.floor(now / 60), "Adventure snapshot", 0.2, true)
            end
        end)
        C_Timer.After(4, function()
            if addon.db then ZoneCapture(false) end
        end)
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon.Queue("logins", "enter", "Entered the world", 4)
        return
    end

    if not addon.db.enabled then return end
    if event == "PLAYER_LEVEL_UP" then
        addon.Queue("levels", select(1, ...), "Level up", 1.2)
    elseif event == "ACHIEVEMENT_EARNED" then
        addon.Queue("achievements", select(1, ...), "Achievement earned", 1.3)
    elseif event == "CRITERIA_EARNED" then
        addon.Queue("criteria", select(1, ...), "Achievement criterion", 1.2)
    elseif event == "ENCOUNTER_END" then
        local success = select(5, ...)
        -- The event may contain guarded values in the Forever beta. Avoid
        -- inspecting them if the modern combat privacy rules prohibit it.
        local safe, won = pcall(function() return success == 1 or success == true end)
        if safe and won then
            addon.Queue("bossKills", "victory", "Boss victory", 1.5)
        elseif safe and not won then
            addon.Queue("bossWipes", "wipe", "Boss wipe", 0.5)
        else
            addon.Queue("bossKills", "end", "Encounter ended", 1.3)
        end
    elseif event == "PLAYER_DEAD" then
        addon.Queue("deaths", "death", "Death", 0)
    elseif event == "PVP_MATCH_COMPLETE" then
        addon.Queue("pvpMatches", "result", "PvP match completed", 1)
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        local unit = select(1, ...)
        if unit == nil or unit == "player" then
            addon.Queue("pvpKills", "kill", "PvP kill", 0.4)
        end
    elseif event == "DUEL_FINISHED" then
        addon.Queue("duels", "duel", "Duel ended", 0.8)
    elseif event == "QUEST_TURNED_IN" then
        addon.Queue("quests", select(1, ...), "Quest completed", 0.9)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ZoneCapture(false)
    elseif event == "ZONE_CHANGED" then
        ZoneCapture(true)
    elseif event == "CHAT_MSG_LOOT" then
        CheckLoot(select(1, ...))
    elseif event == "NEW_RECIPE_LEARNED" then
        addon.Queue("recipes", select(1, ...), "Recipe learned", 0.9)
    elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        addon.Queue("renown", select(1, ...), "Renown level increased", 1)
    elseif event == "PLAYER_PVP_RANK_CHANGED" then
        local unit = select(1, ...)
        if unit == nil or unit == "player" then
            addon.Queue("renown", "rank", "PvP rank changed", 1)
        end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        addon.Queue("reputation", "gain", "Reputation changed", 1)
    elseif event == "NEW_MOUNT_ADDED" or event == "NEW_PET_ADDED" or event == "NEW_TOY_ADDED" then
        addon.Queue("collections", event, "Collection expanded", 1.1)
    elseif event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
        addon.Queue("guildAchievements", "guild", "Guild achievement", 1)
    elseif event == "SCENARIO_COMPLETED" or event == "CHALLENGE_MODE_COMPLETED" then
        addon.Queue("scenarios", event, "Instance completed", 1.5)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")

function addon.ResetPeriodic()
    nextPeriodic = nil
end

function addon.PendingCount()
    return #pending
end

SLASH_FOREVERMOMENTS1 = "/fm"
SLASH_FOREVERMOMENTS2 = "/moments"
SlashCmdList.FOREVERMOMENTS = function(input)
    local arg = (input or ""):lower():match("^%s*(.-)%s*$")
    if arg == "" or arg == "options" or arg == "config" then
        if addon.ToggleOptions then addon.ToggleOptions() end
    elseif arg == "snap" or arg == "shot" or arg == "screenshot" then
        addon.Queue("manual", GetTime(), "Manual screenshot", 0, true)
        Say("Screenshot queued.")
    elseif arg == "on" or arg == "off" then
        addon.db.enabled = (arg == "on")
        Say("Automatic captures " .. (addon.db.enabled and "enabled" or "disabled") .. ".")
    elseif arg == "status" then
        local s = addon.db.stats
        Say("Enabled: " .. tostring(addon.db.enabled) .. " | saved: " .. s.succeeded
            .. " | failed: " .. s.failed .. " | triggers: " .. s.triggered
            .. " | queued: " .. #pending .. " | periodic: " .. addon.db.periodicMinutes .. " min")
    else
        Say("/fm - settings | /fm snap - screenshot | /fm on/off | /fm status")
    end
end

function ForeverMoments_OnCompartmentClick()
    if addon.ToggleOptions then addon.ToggleOptions() end
end
