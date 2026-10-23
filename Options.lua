local ADDON, addon = ...

local frame
local buttons = {}
local checks = {}

local CATEGORIES = {
    { "levels", "Level-ups", "A moment after gaining a level." },
    { "achievements", "Achievements", "Personal achievement earned." },
    { "criteria", "Achievement criteria", "Individual achievement criteria (frequent)." },
    { "bossKills", "Boss victories", "Successful raid and dungeon encounter completions." },
    { "bossWipes", "Boss wipes", "Failed boss encounters. Includes spectacular wipes." },
    { "deaths", "Deaths", "On your character's death." },
    { "pvpMatches", "Battlegrounds / arenas", "PvP match results." },
    { "pvpKills", "PvP kills", "Kill-count change events, with duplicate protection." },
    { "duels", "Duels", "Duels ending, regardless of result." },
    { "quests", "Quest turn-ins", "Every quest handed in. Deliberately frequent." },
    { "zones", "Main zones", "Entering areas, optionally only on first visit." },
    { "subzones", "Subzones", "New towns or landmarks, optionally only on first visit." },
    { "loot", "Quality loot", "Item loot chat messages, potentially including other players' loot." },
    { "recipes", "New recipes", "Profession recipes learned." },
    { "renown", "Renown / PvP rank", "Renown milestones and PvP rank changes." },
    { "reputation", "Reputation messages", "Every reputation gain message (very frequent)." },
    { "collections", "Pets, mounts, toys", "If the beta client exposes their collection events." },
    { "guildAchievements", "Guild achievements", "Guild achievement chat notifications." },
    { "logins", "Entering the world", "Every login/reload/instance world entry (frequent)." },
    { "scenarios", "Instance completions", "Scenario and challenge-mode events, if supported." },
}

local function Label(parent, value, size, x, y, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetText(value)
    if size and text.SetFont then
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, size, flags) end
    end
    if color then text:SetTextColor(color[1], color[2], color[3]) end
    return text
end

local function MakeButton(caption, x, y, width, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width, 25)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(caption)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeCheck(caption, x, y, onClick, tip)
    local b = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(24, 24)
    b:SetScript("OnClick", onClick)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", b, "RIGHT", 1, 0)
    text:SetText(caption)
    local hitArea = CreateFrame("Button", nil, frame)
    hitArea:SetPoint("LEFT", text, "LEFT")
    hitArea:SetSize(245, 24)
    hitArea:SetScript("OnClick", function() b:Click() end)
    if tip then
        local function ShowTip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(caption)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
        b:SetScript("OnEnter", ShowTip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hitArea:SetScript("OnEnter", ShowTip)
        hitArea:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local QUALITY = {
    { 0, "Any" }, { 2, "Uncommon+" }, { 3, "Rare+" },
    { 4, "Epic+" }, { 5, "Legendary+" },
}
local INTERVALS = { 0, 5, 10, 15, 30, 60 }
local GAPS = { 1, 2, 3, 5, 8 }
local DELAYS = { 0, 0.5, 1.1, 2, 3 }

local function Cycle(current, values)
    for i, v in ipairs(values) do
        if v == current then return values[(i % #values) + 1] end
    end
    return values[1]
end

function addon.RefreshOptions()
    if not frame then return end
    local db = addon.db
    if not db then return end
    for key, b in pairs(checks) do
        if key == "enabled" or key == "hideUI" or key == "notify" or key == "firstZonesOnly" then
            b:SetChecked(db[key])
        else
            b:SetChecked(db.categories[key])
        end
    end
    local qual = "?"
    for _, q in ipairs(QUALITY) do
        if db.minLootQuality == q[1] then qual = q[2] end
    end
    buttons.quality:SetText("Loot: " .. qual)
    buttons.period:SetText("Automatic: " .. (db.periodicMinutes == 0 and "Off" or (db.periodicMinutes .. " min")))
    buttons.gap:SetText("Spacing: " .. db.gap .. " sec")
    buttons.delay:SetText("Event delay: " .. db.delay .. " sec")
end

local function SetPreset(kind)
    local db = addon.db
    if kind == "many" then
        for key in pairs(db.categories) do db.categories[key] = true end
        db.gap = 1
        db.delay = 0.5
        db.periodicMinutes = 5
        db.minLootQuality = 2
        db.firstZonesOnly = false
    elseif kind == "default" then
        for key, value in pairs(addon.defaults.categories) do db.categories[key] = value end
        db.gap = addon.defaults.gap
        db.delay = addon.defaults.delay
        db.periodicMinutes = addon.defaults.periodicMinutes
        db.minLootQuality = addon.defaults.minLootQuality
        db.firstZonesOnly = addon.defaults.firstZonesOnly
    else -- conservative preset
        for key in pairs(db.categories) do db.categories[key] = false end
        for _, key in ipairs({ "levels", "achievements", "bossKills", "pvpMatches", "renown" }) do
            db.categories[key] = true
        end
        db.gap = 5
        db.delay = 1.1
        db.periodicMinutes = 0
        db.minLootQuality = 4
        db.firstZonesOnly = true
    end
    db.enabled = true
    addon.ResetPeriodic()
    addon.RefreshOptions()
    addon.Say("Applied preset: " .. kind .. ".")
end

function addon.BuildOptions()
    if frame or not addon.db then return end
    frame = CreateFrame("Frame", "ForeverMomentsOptions", UIParent, "BackdropTemplate")
    frame:SetSize(642, 667)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })
    frame:Hide()

    Label(frame, "FOREVER MOMENTS", 19, 24, -20, { 0.65, 0.85, 1.0 })
    Label(frame, "Automatic screenshots - check the events you want to capture", 12, 25, -48,
        { 0.8, 0.8, 0.8 })
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() frame:Hide() end)

    for i, item in ipairs(CATEGORIES) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local key, caption, tip = item[1], item[2], item[3]
        checks[key] = MakeCheck(caption, col == 0 and 24 or 326, -82 - 27 * row,
            function(self) addon.db.categories[key] = self:GetChecked() end, tip)
    end

    Label(frame, "CAPTURE BEHAVIOUR", 15, 25, -365, { 0.65, 0.85, 1 })
    checks.enabled = MakeCheck("Enable automatic shots", 24, -395,
        function(self) addon.db.enabled = self:GetChecked() end)
    checks.hideUI = MakeCheck("Hide interface (out of combat)", 326, -395,
        function(self) addon.db.hideUI = self:GetChecked() end,
        "Requires a brief HUD hide. During combat, screenshots keep the HUD visible.")
    checks.notify = MakeCheck("Chat notification after saving", 24, -425,
        function(self) addon.db.notify = self:GetChecked() end)
    checks.firstZonesOnly = MakeCheck("Capture each zone only once", 326, -425,
        function(self) addon.db.firstZonesOnly = self:GetChecked() end,
        "Remembers explored main zones and subzones separately for each character.")

    buttons.quality = MakeButton("Loot: Rare+", 24, -464, 280, function()
        local qualityValues = { 0, 2, 3, 4, 5 }
        addon.db.minLootQuality = Cycle(addon.db.minLootQuality, qualityValues)
        addon.RefreshOptions()
    end)
    buttons.period = MakeButton("Automatic: Off", 326, -464, 280, function()
        addon.db.periodicMinutes = Cycle(addon.db.periodicMinutes, INTERVALS)
        addon.ResetPeriodic()
        addon.RefreshOptions()
    end)
    buttons.delay = MakeButton("Event delay", 24, -494, 280, function()
        addon.db.delay = Cycle(addon.db.delay, DELAYS)
        addon.RefreshOptions()
    end)
    buttons.gap = MakeButton("Spacing", 326, -494, 280, function()
        addon.db.gap = Cycle(addon.db.gap, GAPS)
        addon.RefreshOptions()
    end)

    Label(frame, "PRESETS", 14, 25, -538, { 0.65, 0.85, 1 })
    MakeButton("Capture everything", 24, -567, 180, function() SetPreset("many") end)
    MakeButton("Default", 228, -567, 180, function() SetPreset("default") end)
    MakeButton("Only big milestones", 428, -567, 179, function() SetPreset("quiet") end)
    MakeButton("Take a screenshot now", 24, -605, 280, function()
        addon.Queue("manual", GetTime(), "Manual screenshot", 0, true)
    end)
    MakeButton("Reset visited zones", 326, -605, 280, function()
        wipe(addon.charDB.zones)
        wipe(addon.charDB.subzones)
        addon.Say("Visited zone history cleared for this character.")
    end)
    Label(frame, "Screenshots folder: _classic_beta_/Screenshots  |  /fm status  |  v" .. addon.version,
        11, 25, -642, { 0.7, 0.7, 0.7 })
    addon.RefreshOptions()
end

function addon.ToggleOptions()
    if not frame then addon.BuildOptions() end
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        addon.RefreshOptions()
        frame:Show()
    end
end

if addon.db then addon.BuildOptions() end
