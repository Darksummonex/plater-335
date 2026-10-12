setfenv(1, PLATER335_ENV); 

local _, platerInternal = ...
local Plater = Plater
local DF = DetailsFramework

local SEED_VERSION = 4

local MODS = {}

MODS[#MODS+1] = {
	Name = "Totem Icons [WotLK]",
	Icon = [[Interface\Icons\Spell_Nature_StoneClawTotem]],
	Desc = "Replaces totem nameplates with the totem spell icon.",
	Hooks = {
		["Initialization"] = [=[
function (modTable)
    --settings
    modTable.iconSize = 30
    modTable.hidePlate = true --hide health bar, buffs and name of totems
    modTable.enemyOnly = false --only show icons for hostile totems

    modTable.totemIcons = {}
    local totemSpells = {
        8143, 8177, 16190, 2484, 8170, 3599, 5394, 8512, 8075, 8071, 5730,
        5675, 8190, 8227, 8181, 8184, 10595, 3738, 30706, 6495, 2894, 2062,
    }
    for _, spellId in ipairs(totemSpells) do
        local name, _, icon = GetSpellInfo(spellId)
        if (name) then
            modTable.totemIcons[name] = icon
        end
    end

    function modTable.GetTotemIcon(unitId)
        local name = unitId and UnitName(unitId)
        if (not name) then
            return
        end
        if (modTable.enemyOnly and not UnitCanAttack("player", unitId)) then
            return
        end
        return modTable.totemIcons[(name:gsub("%s+[IVXL]+$", ""))]
    end
end
]=],
		["Nameplate Added"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    local icon = modTable.GetTotemIcon(unitId)
    local frame = unitFrame.WotlkTotemIcon

    if (not icon) then
        envTable.isTotem = nil
        if (frame) then
            frame:Hide()
        end
        return
    end

    envTable.isTotem = true

    if (not frame) then
        frame = CreateFrame("Frame", nil, unitFrame)
        frame.Border = frame:CreateTexture(nil, "BACKGROUND")
        frame.Border:SetTexture(0, 0, 0, 1)
        frame.Border:SetPoint("TOPLEFT", -1, 1)
        frame.Border:SetPoint("BOTTOMRIGHT", 1, -1)
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        frame.Icon:SetAllPoints()
        frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        unitFrame.WotlkTotemIcon = frame
    end

    frame:SetSize(modTable.iconSize, modTable.iconSize)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", unitFrame, "CENTER", 0, 0)
    frame:SetFrameLevel(unitFrame:GetFrameLevel() + 20)
    frame.Icon:SetTexture(icon)
    frame:Show()

    if (modTable.hidePlate) then
        Plater.HideHealthBar(unitFrame)
    end
end
]=],
		["Nameplate Updated"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    if (envTable.isTotem and modTable.hidePlate and unitFrame.healthBar:IsShown()) then
        Plater.HideHealthBar(unitFrame)
    end
end
]=],
		["Nameplate Removed"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    envTable.isTotem = nil
    if (unitFrame.WotlkTotemIcon) then
        unitFrame.WotlkTotemIcon:Hide()
    end
end
]=],
	},
}

MODS[#MODS+1] = {
	Name = "Healer Markers [WotLK]",
	Icon = [[Interface\Icons\Spell_Holy_FlashHeal]],
	Desc = "Marks enemy players seen casting healer-only spells.",
	Hooks = {
		["Initialization"] = [=[
function (modTable)
    --settings
    modTable.iconSize = 24
    modTable.pvpOnly = true --only show in battlegrounds and arenas

    modTable.healers = modTable.healers or {}
    modTable.healerSpells = {}
    local spells = {
        20473, 53563, 31842, --paladin: holy shock, beacon of light, divine illumination
        47540, 33206, 10060, --priest: penance, pain suppression, power infusion
        34861, 47788, 724,   --priest: circle of healing, guardian spirit, lightwell
        18562, 48438, 33891, 17116, --druid: swiftmend, wild growth, tree of life, nature's swiftness
        61295, 974, 16190, 51886, 16188, --shaman: riptide, earth shield, mana tide, cleanse spirit, nature's swiftness
    }
    for _, spellId in ipairs(spells) do
        local name = GetSpellInfo(spellId)
        if (name) then
            modTable.healerSpells[name] = true
        end
    end

    function modTable.UpdateIcon(unitFrame)
        local plate = unitFrame.PlateFrame
        local guid = plate and plate.namePlateUnitGUID
        local show = guid and modTable.healers[guid]
        if (show and modTable.pvpOnly) then
            local _, instanceType = IsInInstance()
            show = instanceType == "pvp" or instanceType == "arena"
        end

        local icon = unitFrame.WotlkHealerIcon
        if (not show) then
            if (icon) then
                icon:Hide()
            end
            return
        end

        if (not icon) then
            icon = unitFrame:CreateTexture(nil, "OVERLAY")
            icon:SetTexture([[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]])
            icon:SetTexCoord(20/64, 39/64, 1/64, 20/64)
            unitFrame.WotlkHealerIcon = icon
        end
        icon:SetSize(modTable.iconSize, modTable.iconSize)
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", unitFrame.healthBar, "LEFT", -2, 0)
        icon:Show()
    end

    function modTable.RefreshAll()
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            if (plate.unitFrame) then
                modTable.UpdateIcon(plate.unitFrame)
            end
        end
    end

    local validEvents = {
        SPELL_CAST_START = true,
        SPELL_CAST_SUCCESS = true,
        SPELL_HEAL = true,
        SPELL_PERIODIC_HEAL = true,
        SPELL_AURA_APPLIED = true,
    }

    modTable.eventFrame = modTable.eventFrame or CreateFrame("Frame")
    local eventFrame = modTable.eventFrame
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self, event)
        if (event == "PLAYER_ENTERING_WORLD") then
            wipe(modTable.healers)
            modTable.RefreshAll()
            return
        end

        local _, subEvent, _, srcGUID, _, srcFlags, _, _, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()
        if (not srcGUID or not validEvents[subEvent] or modTable.healers[srcGUID]) then
            return
        end
        if (not spellName or not modTable.healerSpells[spellName]) then
            return
        end
        --hostile (0x40) player (0x400)
        srcFlags = srcFlags or 0
        if (bit.band(srcFlags, 0x400) == 0 or bit.band(srcFlags, 0x40) == 0) then
            return
        end

        modTable.healers[srcGUID] = true
        modTable.RefreshAll()
    end)
end
]=],
		["Deinitialization"] = [=[
function (modTable)
    if (modTable.eventFrame) then
        modTable.eventFrame:UnregisterAllEvents()
        modTable.eventFrame:SetScript("OnEvent", nil)
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if (plate.unitFrame and plate.unitFrame.WotlkHealerIcon) then
            plate.unitFrame.WotlkHealerIcon:Hide()
        end
    end
end
]=],
		["Nameplate Added"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    modTable.UpdateIcon(unitFrame)
end
]=],
		["Nameplate Removed"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    if (unitFrame.WotlkHealerIcon) then
        unitFrame.WotlkHealerIcon:Hide()
    end
end
]=],
	},
}

MODS[#MODS+1] = {
	Name = "Interrupt Ready [WotLK]",
	Icon = [[Interface\Icons\Ability_Kick]],
	Desc = "Colors interruptible cast bars when your interrupt is off cooldown.",
	Hooks = {
		["Initialization"] = [=[
function (modTable)
    --settings
    modTable.readyColor = {0.1, 0.9, 0.2}
    modTable.enemyOnly = true

    local interrupts = {
        ROGUE = {1766},         --kick
        WARRIOR = {6552, 72},   --pummel, shield bash
        DEATHKNIGHT = {47528},  --mind freeze
        MAGE = {2139},          --counterspell
        SHAMAN = {57994},       --wind shear
        HUNTER = {34490},       --silencing shot
        PRIEST = {15487},       --silence
        DRUID = {16979},        --feral charge - bear
    }

    local _, class = UnitClass("player")
    modTable.interruptNames = {}
    for _, spellId in ipairs(interrupts[class] or {}) do
        local name = GetSpellInfo(spellId)
        if (name) then
            tinsert(modTable.interruptNames, name)
        end
    end

    modTable.lastCheck = 0
    modTable.lastResult = false

    function modTable.IsInterruptReady()
        local now = GetTime()
        if (now == modTable.lastCheck) then
            return modTable.lastResult
        end
        modTable.lastCheck = now

        local ready = false
        for _, name in ipairs(modTable.interruptNames) do
            local start, duration = GetSpellCooldown(name)
            local usable, noMana = IsUsableSpell(name)
            --ignore the global cooldown
            if (start and (usable or noMana) and (start == 0 or duration <= 1.5)) then
                ready = true
                break
            end
        end

        modTable.lastResult = ready
        return ready
    end
end
]=],
		["Cast Start"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    envTable.wotlkReady = false
    envTable.wotlkOriginalColor = nil
end
]=],
		["Cast Update"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    local ready = envTable._CanInterrupt and modTable.IsInterruptReady()
    if (ready and modTable.enemyOnly) then
        ready = UnitCanAttack("player", unitId)
    end
    ready = ready and true or false

    if (ready == envTable.wotlkReady) then
        return
    end
    envTable.wotlkReady = ready

    if (ready) then
        envTable.wotlkOriginalColor = {self:GetStatusBarColor()}
        self:SetStatusBarColor(unpack(modTable.readyColor))
    elseif (envTable.wotlkOriginalColor) then
        self:SetStatusBarColor(unpack(envTable.wotlkOriginalColor))
    end
end
]=],
		["Cast Stop"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    envTable.wotlkReady = false
    envTable.wotlkOriginalColor = nil
end
]=],
	},
}

MODS[#MODS+1] = {
	Name = "Abbreviate NPC Names [WotLK]",
	Icon = [[Interface\Icons\INV_Misc_Note_01]],
	Desc = "Shortens long NPC names: every word but the last becomes an initial (Scourge Necromancer Lieutenant -> S. N. Lieutenant).",
	Hooks = {
		["Initialization"] = [=[
function (modTable)
    --settings
    modTable.maxLength = 16 --names longer than this many letters get abbreviated
    modTable.skipLowercase = true --drop lowercase words like "of" and "the" instead of turning them into initials
    modTable.useDots = true --"S. N. Lieutenant" instead of "SN Lieutenant"

    modTable.cache = {}

    local function utf8len(text)
        local _, count = text:gsub("[^\128-\191]", "")
        return count
    end

    function modTable.Abbreviate(name)
        local cached = modTable.cache[name]
        if (cached) then
            return cached
        end

        local result = name
        if (utf8len(name) > modTable.maxLength) then
            local words = {}
            for word in name:gmatch("%S+") do
                words[#words + 1] = word
            end

            if (#words > 1) then
                local initials = {}
                for i = 1, #words - 1 do
                    local initial = words[i]:match("^[%z\1-\127\194-\244][\128-\191]*")
                    if (initial and not (modTable.skipLowercase and initial:match("^%l"))) then
                        initials[#initials + 1] = initial .. (modTable.useDots and "." or "")
                    end
                end
                local prefix = table.concat(initials, modTable.useDots and " " or "")
                result = (prefix ~= "" and (prefix .. " ") or "") .. words[#words]
            end
        end

        modTable.cache[name] = result
        return result
    end

    function modTable.Apply(unitId, unitFrame)
        if (not unitId or UnitIsPlayer(unitId)) then
            return
        end
        local plateFrame = unitFrame.PlateFrame
        local nameString = plateFrame and plateFrame.CurrentUnitNameString
        local name = UnitName(unitId)
        if (not nameString or not name) then
            return
        end
        local short = modTable.Abbreviate(name)
        if (short ~= name and nameString:GetText() ~= short) then
            nameString:SetText(short)
        end
    end
end
]=],
		["Nameplate Added"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    modTable.Apply(unitId, unitFrame)
end
]=],
		["Name Updated"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    modTable.Apply(unitId, unitFrame)
end
]=],
		["Nameplate Updated"] = [=[
function (self, unitId, unitFrame, envTable, modTable)
    modTable.Apply(unitId, unitFrame)
end
]=],
	},
}

local function buildMod(info)
	local mod = {
		Enabled = true,
		Name = info.Name,
		Icon = info.Icon,
		Desc = info.Desc,
		Author = "Plater 3.3.5 port",
		Time = time(),
		Revision = 1,
		PlaterCore = Plater.CoreVersion,
		Hooks = {},
		HooksTemp = {},
		LastHookEdited = "",
		LoadConditions = DF:UpdateLoadConditionsTable({}),
		Options = {},
		url = "",
		version = -1,
		semver = "",
	}
	for hookName, code in pairs(info.Hooks) do
		mod.Hooks[hookName] = code
	end
	if (Plater.CreateOptionTableForScriptObject) then
		Plater.CreateOptionTableForScriptObject(mod)
	end
	return mod
end

--scripts built for retail-only content or APIs
local RETAIL_SCRIPTS = {
	["Explosion Affix M+ [Plater]"] = true,
	["M+ Spiteful"] = true,
	["Countdown"] = true,
	["Aura is Shield [P]"] = true,
	["Cast - Shield Interrupt [P]"] = true,
	["Relics 9.2 M Dungeons"] = true,
}

--mods built for retail-only content or APIs
local RETAIL_MODS = {
	["M+ Renamer"] = true, --Shadowlands/Dragonflight dungeon mob names and encrypted affix relics
}
local RETAIL_LIBRARY_KEYS = {"Explosion Affix M+", "Spiteful Affix", "Countdown", "Aura is Shield [P]", "Cast - Shield Interrupt"}

--highest spell / creature IDs that exist in 3.3.5 data
local MAX_WOTLK_SPELLID = 80864
local MAX_WOTLK_NPCID = 40500

if (PlaterScriptLibrary) then
	for _, key in ipairs(RETAIL_LIBRARY_KEYS) do
		PlaterScriptLibrary[key] = nil
	end
end

do
	local castScripts = platerInternal and platerInternal.Scripts and platerInternal.Scripts.DefaultCastScripts
	if (castScripts) then
		for i = #castScripts, 1, -1 do
			if (RETAIL_SCRIPTS[castScripts[i]]) then
				tremove(castScripts, i)
			end
		end
	end
end

local function stripRetailTriggers(list, maxId)
	if (type(list) ~= "table") then
		return false
	end
	local changed = false
	for i = #list, 1, -1 do
		local id = tonumber(list[i])
		if (id and id > maxId) then
			tremove(list, i)
			changed = true
		end
	end
	return changed
end

local function removeRetailMods(profile)
	local changed = false
	local mods = profile.hook_data
	if (type(mods) == "table") then
		for i = #mods, 1, -1 do
			if (RETAIL_MODS[mods[i].Name]) then
				tremove(mods, i)
				changed = true
			end
		end
	end
	return changed
end

local function removeRetailScripts(profile)
	local changed = false
	local scripts = profile.script_data
	if (type(scripts) == "table") then
		for i = #scripts, 1, -1 do
			local script = scripts[i]
			if (RETAIL_SCRIPTS[script.Name]) then
				tremove(scripts, i)
				changed = true
			else
				if (stripRetailTriggers(script.SpellIds, MAX_WOTLK_SPELLID)) then changed = true end
				if (stripRetailTriggers(script.NpcNames, MAX_WOTLK_NPCID)) then changed = true end
			end
		end
	end
	return changed
end

local function seed()
	local profile = Plater.db and Plater.db.profile
	if (not profile or not profile.hook_data) then
		return
	end
	if (profile.wotlk_mods_version == SEED_VERSION) then
		return
	end

	if (removeRetailScripts(profile)) then
		C_Timer.After(1, function()
			Plater.WipeAndRecompileAllScripts("script")
		end)
	end

	local existing = {}
	for _, mod in ipairs(profile.hook_data) do
		if (mod.Name) then
			existing[mod.Name] = true
		end
	end

	local added = removeRetailMods(profile)
	for _, info in ipairs(MODS) do
		if (not existing[info.Name]) then
			tinsert(profile.hook_data, buildMod(info))
			added = true
		end
	end
	profile.wotlk_mods_version = SEED_VERSION

	if (added) then
		C_Timer.After(1, function()
			Plater.WipeAndRecompileAllScripts("hook")
		end)
	end
end

Plater.RegisterRefreshDBCallback(seed)
