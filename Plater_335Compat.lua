-- Plater 3.3.5 compatibility layer (self-contained, no !!!ClassicAPI).
-- Everything Plater-specific lives in PLATER335_ENV; every Plater/DF source file runs inside it via setfenv.
-- Only missing widget methods are added to the shared metatables.

local realG = _G
local origCreateFrame = CreateFrame
local GetTime = GetTime
local pairs, ipairs, type, select, tonumber, tostring, unpack, next = pairs, ipairs, type, select, tonumber, tostring, unpack, next
local wipe = wipe or table.wipe

-- __newindex (passing Plater's own globals through to _G) is installed at the end of this file,
-- so every env.X assignment below stays private to Plater
local envMeta = {__index = realG}
local env = setmetatable({}, envMeta)
env._G = env
PLATER335_ENV = env
PLATER335_VERSION = 16

local Compat = {}
env.Plater335 = Compat

-- Lua 5.1 xpcall drops extra arguments; retail passes them to the function
local realXpcall = xpcall
env.xpcall = function(func, handler, ...)
	local n = select("#", ...)
	if n == 0 then return realXpcall(func, handler) end
	local args = {...}
	return realXpcall(function() return func(unpack(args, 1, n)) end, handler)
end

local noop = function() end
local retFalse = function() return false end
local retTrue = function() return true end
local retZero = function() return 0 end
local retNil = function() return nil end
local retEmptyTable = function() return {} end

---------------------------------------------------------------------------------------------------
-- game flavor

env.WOW_PROJECT_MAINLINE = 1
env.WOW_PROJECT_CLASSIC = 2
env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
env.WOW_PROJECT_WRATH_CLASSIC = 11
env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
env.WOW_PROJECT_ID = 11

env.LE_EXPANSION_CLASSIC = 0
env.LE_EXPANSION_BURNING_CRUSADE = 1
env.LE_EXPANSION_WRATH_OF_THE_LICH_KING = 2
env.LE_EXPANSION_CATACLYSM = 3
env.LE_EXPANSION_LEVEL_CURRENT = 2
env.ClassicExpansionAtLeast = function(expansion) return (expansion or 0) <= 2 end
env.GetClassicExpansionLevel = function() return 2 end
env.GetExpansionLevel = realG.GetExpansionLevel or function() return 2 end

---------------------------------------------------------------------------------------------------
-- lua / FrameXML helpers

env.Mixin = function(object, ...)
	for i = 1, select("#", ...) do
		local mixin = select(i, ...)
		if type(mixin) == "table" then
			for k, v in pairs(mixin) do object[k] = v end
		end
	end
	return object
end
env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
env.CreateAndInitFromMixin = function(mixin, ...)
	local object = env.CreateFromMixins(mixin)
	if object.Init then object:Init(...) end
	return object
end

env.Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
env.Saturate = function(v) return env.Clamp(v, 0, 1) end
env.Lerp = function(a, b, t) return a + (b - a) * t end
env.Round = function(v) if v < 0 then return math.ceil(v - .5) end return math.floor(v + .5) end
env.PercentageBetween = function(v, lo, hi) if lo == hi then return 0 end return (v - lo) / (hi - lo) end
env.ClampedPercentageBetween = function(v, lo, hi) return env.Saturate(env.PercentageBetween(v, lo, hi)) end
env.CopyTable = function(t, shallow)
	local copy = {}
	for k, v in pairs(t) do
		if type(v) == "table" and not shallow then copy[k] = env.CopyTable(v) else copy[k] = v end
	end
	return copy
end
env.tInvert = function(t) local r = {} for k, v in pairs(t) do r[v] = k end return r end
env.tIndexOf = function(t, value) for i = 1, #t do if t[i] == value then return i end end end
if not realG.tContains then
	env.tContains = function(t, value) for _, v in pairs(t) do if v == value then return true end end return false end
end
env.WrapTextInColorCode = function(text, hex) return "|c" .. hex .. text .. "|r" end

local ColorMixin = {}
function ColorMixin:OnLoad(r, g, b, a) self:SetRGBA(r, g, b, a) end
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:SetRGB(r, g, b) self:SetRGBA(r, g, b, nil) end
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a or 1 end
function ColorMixin:GetRGBAsBytes() return self.r * 255, self.g * 255, self.b * 255 end
function ColorMixin:IsEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b and self.a == o.a end
function ColorMixin:GenerateHexColor() return ("ff%.2x%.2x%.2x"):format(self.r * 255, self.g * 255, self.b * 255) end
function ColorMixin:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
function ColorMixin:WrapTextInColorCode(text) return "|c" .. self:GenerateHexColor() .. text .. "|r" end
env.ColorMixin = ColorMixin
env.CreateColor = function(r, g, b, a)
	local c = env.CreateFromMixins(ColorMixin)
	c:OnLoad(r, g, b, a)
	return c
end

local classColors = {}
for class, c in pairs(realG.RAID_CLASS_COLORS or {}) do
	local color = env.CreateColor(c.r, c.g, c.b, 1)
	color.colorStr = c.colorStr or color:GenerateHexColor()
	classColors[class] = color
end
env.RAID_CLASS_COLORS = classColors
env.GetClassColor = function(class)
	local c = classColors[class]
	if c then return c.r, c.g, c.b, c.colorStr end
	return 1, 1, 1, "ffffffff"
end
env.C_ClassColor = { GetClassColor = function(class) return classColors[class] end }

local Vector2DMixin = {}
function Vector2DMixin:GetXY() return self.x, self.y end
function Vector2DMixin:SetXY(x, y) self.x, self.y = x, y end
function Vector2DMixin:ScaleBy(s) self.x, self.y = self.x * s, self.y * s end
function Vector2DMixin:Add(o) self.x, self.y = self.x + o.x, self.y + o.y end
function Vector2DMixin:Subtract(o) self.x, self.y = self.x - o.x, self.y - o.y end
function Vector2DMixin:GetLength() return math.sqrt(self.x * self.x + self.y * self.y) end
function Vector2DMixin:Clone() return env.CreateVector2D(self.x, self.y) end
env.CreateVector2D = function(x, y) local v = env.CreateFromMixins(Vector2DMixin) v:SetXY(x, y) return v end

env.GetPhysicalScreenSize = function()
	local res = realG.GetCVar("gxResolution") or ""
	local w, h = res:match("(%d+)x(%d+)")
	w, h = tonumber(w), tonumber(h)
	if w and h then return w, h end
	local scale = UIParent:GetEffectiveScale()
	return realG.GetScreenWidth() * scale, realG.GetScreenHeight() * scale
end

local PixelUtil = {}
function PixelUtil.GetPixelToUIUnitFactor() local _, h = env.GetPhysicalScreenSize() return 768 / h end
function PixelUtil.GetNearestPixelSize(size) return size end
function PixelUtil.SetWidth(region, w) region:SetWidth(w) end
function PixelUtil.SetHeight(region, h) region:SetHeight(h) end
function PixelUtil.SetSize(region, w, h) region:SetWidth(w) region:SetHeight(h) end
function PixelUtil.SetPoint(region, ...) region:SetPoint(...) end
function PixelUtil.SetStatusBarValue(bar, v) bar:SetValue(v) end
env.PixelUtil = PixelUtil

-- object pools
local ObjectPoolMixin = {}
function ObjectPoolMixin:OnLoad(creationFunc, resetterFunc)
	self.creationFunc, self.resetterFunc = creationFunc, resetterFunc
	self.activeObjects, self.inactiveObjects, self.numActiveObjects = {}, {}, 0
end
function ObjectPoolMixin:Acquire()
	local obj = tremove(self.inactiveObjects)
	local new = obj == nil
	if new then obj = self.creationFunc(self) end
	self.activeObjects[obj] = true
	self.numActiveObjects = self.numActiveObjects + 1
	return obj, new
end
function ObjectPoolMixin:Release(obj)
	if not self.activeObjects[obj] then return false end
	if self.resetterFunc then self.resetterFunc(self, obj) end
	self.activeObjects[obj] = nil
	self.numActiveObjects = self.numActiveObjects - 1
	tinsert(self.inactiveObjects, obj)
	return true
end
function ObjectPoolMixin:ReleaseAll() for obj in pairs(self.activeObjects) do self:Release(obj) end end
function ObjectPoolMixin:EnumerateActive() return pairs(self.activeObjects) end
function ObjectPoolMixin:GetNumActive() return self.numActiveObjects end
env.ObjectPoolMixin = ObjectPoolMixin
env.CreateObjectPool = function(creationFunc, resetterFunc)
	local pool = env.CreateFromMixins(ObjectPoolMixin)
	pool:OnLoad(creationFunc, resetterFunc)
	return pool
end
local hideAndClear = function(_, obj) obj:Hide() obj:ClearAllPoints() end
env.CreateFramePool = function(frameType, parent, template, resetterFunc)
	return env.CreateObjectPool(function() return env.CreateFrame(frameType, nil, parent, template) end, resetterFunc or hideAndClear)
end
env.CreateTexturePool = function(parent, layer, subLayer, template, resetterFunc)
	return env.CreateObjectPool(function() return parent:CreateTexture(nil, layer, template, subLayer) end, resetterFunc or hideAndClear)
end
env.CreateFontStringPool = function(parent, layer, subLayer, template, resetterFunc)
	return env.CreateObjectPool(function() return parent:CreateFontString(nil, layer, template) end, resetterFunc or hideAndClear)
end

---------------------------------------------------------------------------------------------------
-- C_Timer

do
	local active, due = {}, {}
	local timerFrame = origCreateFrame("Frame")
	timerFrame:Hide()

	local Timer = {}
	Timer.__index = Timer
	function Timer:Cancel() self._cancelled = true active[self] = nil end
	function Timer:IsCancelled() return self._cancelled == true end
	function Timer:Invoke(...) return self._cb(...) end

	local errorHandler = function(err) return geterrorhandler()(err) end

	timerFrame:SetScript("OnUpdate", function(self)
		local now = GetTime()
		local n = 0
		for t in pairs(active) do
			if t._end <= now then n = n + 1 due[n] = t end
		end
		for i = 1, n do
			local t = due[i]
			due[i] = nil
			if not t._cancelled then
				if t._remaining then t._remaining = t._remaining - 1 end
				if t._ticker and (not t._remaining or t._remaining > 0) then
					t._end = now + t._duration
				else
					active[t] = nil
				end
				if t._passSelf then xpcall(function() t._cb(t) end, errorHandler) else xpcall(t._cb, errorHandler) end
			end
		end
		if not next(active) then self:Hide() end
	end)

	local function newTimer(duration, callback, isTicker, iterations, passSelf)
		local t = setmetatable({_duration = duration or 0, _cb = callback, _ticker = isTicker, _remaining = iterations, _passSelf = passSelf}, Timer)
		t._end = GetTime() + t._duration
		active[t] = true
		timerFrame:Show()
		return t
	end

	env.C_Timer = {
		After = function(duration, callback) newTimer(duration, callback, false, nil, false) end,
		NewTimer = function(duration, callback) return newTimer(duration, callback, false, nil, true) end,
		NewTicker = function(duration, callback, iterations) return newTimer(duration, callback, true, iterations, true) end,
	}
end

---------------------------------------------------------------------------------------------------
-- Enum

local function autoTable(t)
	return setmetatable(t, {__index = function(self, k) local v = {} rawset(self, k, v) return v end})
end
env.Enum = autoTable({
	PowerType = {
		HealthCost = -2, None = -1, Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6,
		SoulShards = 7, LunarPower = 8, HolyPower = 9, Alternate = 10, Maelstrom = 11, Chi = 12, Insanity = 13,
		Obsolete = 14, Obsolete2 = 15, ArcaneCharges = 16, Fury = 17, Pain = 18, Essence = 19,
	},
	TooltipDataLineType = { None = 0, Blank = 1, UnitName = 2, GemSocket = 3, AzeriteEssenceSlot = 4, AzeriteEssencePower = 5, LearnableSpell = 6, UnitThreat = 7, QuestObjective = 8, AzeriteItemPowerDescription = 9, RuneforgeLegendaryPowerDescription = 10, SellPrice = 11, ProfessionCraftingQuality = 12, SpellName = 13, CurrencyTotal = 14, ItemEnchantmentPermanent = 15, UnitOwner = 16, QuestTitle = 17, QuestPlayer = 18, NestedBlock = 19, ItemBinding = 20 },
	TraitNodeEntryType = { SpendSquare = 0, SpendCircle = 1, SpendSmallCircle = 2, ModifySpell = 3, CreateAndModifySpell = 4, SpendHex = 5, SpendInfinite = 6, RedButton = 7, RankedPassive = 8, ProfPath = 9, ProfPerk = 10, ProfPathUnlock = 11, SpendDiamond = 12 },
})
env.SOUNDKIT = setmetatable({}, {__index = function() return nil end})

---------------------------------------------------------------------------------------------------
-- unit / spell / aura API in the format Plater expects (Wrath Classic 3.4)

local origUnitAura, origUnitBuff, origUnitDebuff = UnitAura, UnitBuff, UnitDebuff
local origUnitCastingInfo, origUnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local origGetSpellInfo = GetSpellInfo

local function convertAura(name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId)
	if not name then return nil end
	local castByPlayer = unitCaster == "player" or unitCaster == "pet" or unitCaster == "vehicle"
	return name, icon, count or 0, debuffType, duration or 0, expirationTime or 0, unitCaster, isStealable, false, spellId, false, false, castByPlayer, false, 1
end
env.UnitAura = function(unit, index, filter, extra)
	if type(index) == "string" and extra then return convertAura(origUnitAura(unit, index, filter, extra)) end
	return convertAura(origUnitAura(unit, index, filter))
end
env.UnitBuff = function(unit, index, filter) return convertAura(origUnitBuff(unit, index, filter)) end
env.UnitDebuff = function(unit, index, filter) return convertAura(origUnitDebuff(unit, index, filter)) end
env.UnitAuraBySlot = false
env.UnitAuraSlots = false
env.C_UnitAuras = { AddPrivateAuraAnchor = noop, RemovePrivateAuraAnchor = noop }
env.AuraUtil = {
	UnpackAuraData = function(a) if not a then return nil end return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId, a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet, a.nameplateShowAll, a.timeMod end,
	FindAuraByName = function(auraName, unit, filter)
		for i = 1, 40 do
			local name = origUnitAura(unit, i, filter)
			if not name then return end
			if name == auraName then return env.UnitAura(unit, i, filter) end
		end
	end,
	ForEachAura = function(unit, filter, maxCount, func)
		for i = 1, maxCount or 40 do
			if not origUnitAura(unit, i, filter) then return end
			if func(env.UnitAura(unit, i, filter)) then return end
		end
	end,
}

-- spell id lookup for casts (3.3.5 casts have no spell id): combat log SPELL_CAST_START / SUCCESS per caster GUID
local castSpellByGUID = {}
local spellIdByName = {}
local function spellIdFromLink(name)
	if not name then return end
	local cached = spellIdByName[name]
	if cached ~= nil then return cached or nil end
	local link = realG.GetSpellLink(name)
	local id = link and tonumber(link:match("spell:(%d+)"))
	spellIdByName[name] = id or false
	return id
end
function Compat.GetCastSpellID(unit, spellName)
	local guid = unit and realG.UnitGUID(unit)
	local cached = guid and castSpellByGUID[guid]
	if cached and (not spellName or cached.name == spellName) then return cached.id end
	return spellIdFromLink(spellName)
end

env.UnitCastingInfo = function(unit)
	local name, rank, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = origUnitCastingInfo(unit)
	if not name then return nil end
	return name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, Compat.GetCastSpellID(unit, name)
end
env.UnitChannelInfo = function(unit)
	local name, rank, text, texture, startTime, endTime, isTradeSkill, notInterruptible = origUnitChannelInfo(unit)
	if not name then return nil end
	return name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, Compat.GetCastSpellID(unit, name), false, 0
end
env.CastingInfo = function() return env.UnitCastingInfo("player") end
env.ChannelInfo = function() return env.UnitChannelInfo("player") end

env.GetSpellInfo = function(spell, book)
	if spell == nil then return nil end
	local name, rank, icon, powerCost, isFunnel, powerType, castTime, minRange, maxRange
	if book then
		name, rank, icon, powerCost, isFunnel, powerType, castTime, minRange, maxRange = origGetSpellInfo(spell, book)
	else
		name, rank, icon, powerCost, isFunnel, powerType, castTime, minRange, maxRange = origGetSpellInfo(spell)
	end
	if not name then return nil end
	local spellID = type(spell) == "number" and not book and spell or spellIdFromLink(name)
	return name, rank, icon, castTime or 0, minRange or 0, maxRange or 0, spellID, icon
end
env.GetSpellTexture = function(spell, book)
	if book then return realG.GetSpellTexture(spell, book) end
	local _, _, icon = origGetSpellInfo(spell)
	return icon
end
env.GetSpellBookItemTexture = function(index, book) return realG.GetSpellTexture(index, book) end
env.GetSpellBookItemName = function(index, book)
	local name, rank = realG.GetSpellName(index, book)
	return name, rank, spellIdFromLink(name)
end
env.GetSpellDescription = function() return "" end
env.GetSpellCharges = retNil
env.GetSpellPowerCost = function(spell)
	local _, _, _, cost, _, powerType = origGetSpellInfo(spell)
	if cost and cost > 0 then return {{type = powerType, cost = cost, minCost = cost}} end
	return {}
end
env.IsPlayerSpell = function(spellID)
	local name = origGetSpellInfo(spellID)
	return name ~= nil and origGetSpellInfo(name) ~= nil
end
env.IsSpellKnownOrOverridesKnown = env.IsPlayerSpell
if not realG.IsSpellKnown then env.IsSpellKnown = env.IsPlayerSpell end
env.C_SpellBook = { GetOverrideSpell = function(id) return id end }

-- combat log in the modern argument layout
local cleuBuffer, cleuCount = {}, 0
function Compat.SetCombatLogArgs(...)
	local n = select("#", ...)
	local ts, subEvent, third = ...
	if type(third) == "boolean" then
		for i = 1, n do cleuBuffer[i] = select(i, ...) end
		cleuCount = n
		return
	end
	local _, _, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags = ...
	cleuBuffer[1], cleuBuffer[2], cleuBuffer[3] = ts, subEvent, false
	cleuBuffer[4], cleuBuffer[5], cleuBuffer[6], cleuBuffer[7] = srcGUID, srcName, srcFlags, 0
	cleuBuffer[8], cleuBuffer[9], cleuBuffer[10], cleuBuffer[11] = dstGUID, dstName, dstFlags, 0
	local idx = 11
	for i = 9, n do
		idx = idx + 1
		cleuBuffer[idx] = select(i, ...)
	end
	for i = idx + 1, cleuCount do cleuBuffer[i] = nil end
	cleuCount = idx
end
env.CombatLogGetCurrentEventInfo = function() return unpack(cleuBuffer, 1, cleuCount) end

-- groups
local GetNumRaidMembers, GetNumPartyMembers = realG.GetNumRaidMembers, realG.GetNumPartyMembers
env.IsInRaid = function() return GetNumRaidMembers() > 0 end
env.IsInGroup = function() return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 end
env.GetNumGroupMembers = function()
	local raid = GetNumRaidMembers()
	if raid > 0 then return raid end
	local party = GetNumPartyMembers()
	return party > 0 and party + 1 or 0
end
env.GetNumSubgroupMembers = function() return GetNumPartyMembers() end
env.UnitIsGroupLeader = function(unit) return realG.UnitIsPartyLeader(unit) and true or false end
env.UnitIsGroupAssistant = function(unit) return realG.UnitIsRaidOfficer and realG.UnitIsRaidOfficer(unit) and true or false end

local origUnitGroupRolesAssigned = realG.UnitGroupRolesAssigned
env.UnitGroupRolesAssigned = function(unit)
	if not origUnitGroupRolesAssigned then return "NONE" end
	local a, b, c = origUnitGroupRolesAssigned(unit)
	if type(a) == "string" then return a end
	if a then return "TANK" elseif b then return "HEALER" elseif c then return "DAMAGER" end
	return "NONE"
end

-- talent tree index -> role, for GetTalentGroupRole
local TREE_ROLES = {
	WARRIOR = {"DAMAGER", "DAMAGER", "TANK"}, PALADIN = {"HEALER", "TANK", "DAMAGER"}, PRIEST = {"HEALER", "HEALER", "DAMAGER"},
	SHAMAN = {"DAMAGER", "DAMAGER", "HEALER"}, DRUID = {"DAMAGER", "DAMAGER", "HEALER"}, DEATHKNIGHT = {"DAMAGER", "DAMAGER", "DAMAGER"},
}
env.GetTalentGroupRole = function(group)
	local _, class = realG.UnitClass("player")
	local roles = TREE_ROLES[class]
	if not roles then return "DAMAGER" end
	local best, bestPoints = 1, -1
	for tab = 1, (realG.GetNumTalentTabs() or 3) do
		local _, _, points = realG.GetTalentTabInfo(tab, false, false, group)
		if (points or 0) > bestPoints then best, bestPoints = tab, points or 0 end
	end
	if class == "DRUID" and best == 2 and realG.GetShapeshiftForm() == 1 then return "TANK" end
	if class == "DEATHKNIGHT" and realG.GetShapeshiftForm() == 2 then return "TANK" end
	return roles[best] or "DAMAGER"
end
env.GetSpecialization = retNil
env.GetSpecializationInfo = retNil
env.GetSpecializationInfoByID = retNil
env.GetSpecializationRole = retNil
env.GetNumSpecializations = retZero
env.GetNumSpecializationsForClassID = retZero
env.GetSpecializationInfoForClassID = retNil
env.GetArenaOpponentSpec = retNil
env.GetNumArenaOpponentSpecs = retZero
env.GetPvpTalentInfoByID = retNil

local CLASS_IDS = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID"}
local CLASS_ID_BY_FILE = {}
for id, file in ipairs(CLASS_IDS) do CLASS_ID_BY_FILE[file] = id end
env.GetNumClasses = function() return 11 end
env.GetClassInfo = function(classID)
	local file = CLASS_IDS[classID]
	if not file or file == "MONK" then return nil end
	local localized = (realG.LOCALIZED_CLASS_NAMES_MALE and realG.LOCALIZED_CLASS_NAMES_MALE[file]) or file
	return localized, file, classID
end
env.UnitClassBase = function(unit) local _, file = realG.UnitClass(unit) return file, CLASS_ID_BY_FILE[file or ""] end
-- 3.3.5 errors on unknown tokens (softinteract, softenemy, softfriend, nil) instead of returning false
local realUnitIsUnit = realG.UnitIsUnit
env.UnitIsUnit = function(a, b)
	if not a or not b then return false end
	local ok, result = pcall(realUnitIsUnit, a, b)
	return ok and result or false
end
env.UnitClass = function(unit)
	local name, file = realG.UnitClass(unit)
	return name, file, file and CLASS_ID_BY_FILE[file]
end

local RACES = {"Human", "Orc", "Dwarf", "NightElf", "Scourge", "Tauren", "Gnome", "Troll", "Goblin", "BloodElf", "Draenei"}
env.C_CreatureInfo = {
	GetClassInfo = function(classID)
		local name, file, id = env.GetClassInfo(classID)
		if name then return {className = name, classFile = file, classID = id} end
	end,
	GetRaceInfo = function(raceID)
		local file = RACES[raceID]
		if file then return {raceName = file, clientFileString = file, raceID = raceID} end
	end,
}

env.UnitIsTapDenied = function(unit)
	return realG.UnitIsTapped(unit) and not realG.UnitIsTappedByPlayer(unit) and not (realG.UnitIsTappedByAllThreatList and realG.UnitIsTappedByAllThreatList(unit))
end
env.UnitEffectiveLevel = realG.UnitLevel
env.UnitGetTotalAbsorbs = retZero
env.UnitGetTotalHealAbsorbs = retZero
if not realG.UnitGetIncomingHeals then env.UnitGetIncomingHeals = retZero end
env.UnitIsBattlePet = retFalse
env.UnitIsWildBattlePet = retFalse
env.UnitIsGameObject = retFalse
env.UnitIsQuestBoss = retFalse
env.UnitNameplateShowsWidgetsOnly = retFalse
env.UnitShouldDisplayName = retTrue
env.UnitPartialPower = retZero
env.UnitPowerDisplayMod = function() return 1 end
env.GetUnitChargedPowerPoints = retNil
env.GetUnitEmpowerHoldAtMaxTime = retZero
env.GetUnitEmpowerStageDuration = retZero
env.GetPowerRegenForPowerType = function() return realG.GetPowerRegen() end
env.UnitInPartyIsAI = retFalse

local origUnitPower, origUnitPowerMax = realG.UnitPower, realG.UnitPowerMax
env.UnitPower = function(unit, powerType, ...)
	if powerType == 4 then return realG.GetComboPoints(unit == "player" and (realG.UnitHasVehicleUI("player") and "vehicle" or "player") or unit, "target") or 0 end
	return origUnitPower(unit, powerType, ...)
end
env.UnitPowerMax = function(unit, powerType, ...)
	if powerType == 4 then return 5 end
	return origUnitPowerMax(unit, powerType, ...)
end

local origBNGetFriendInfo = realG.BNGetFriendInfo
env.BNGetFriendInfo = function(index)
	if not origBNGetFriendInfo then return nil end
	local presenceID, givenName, surname, toonName, toonID, client, isOnline, lastOnline, isAFK, isDND, broadcastText, noteText, isFriend, broadcastTime = origBNGetFriendInfo(index)
	local presenceName = givenName and ((givenName or "") .. " " .. (surname or "")) or nil
	return presenceID, presenceName, nil, false, toonName, toonID, client, isOnline, lastOnline, isAFK, isDND, broadcastText, noteText, isFriend, broadcastTime, false
end

env.Ambiguate = function(name) return name and (name:gsub("%-.*$", "")) end
env.GetCurrentRegion = function() return 1 end
env.GetCurrentRegionName = function() return "US" end
env.GetRelativeDifficultyColor = function(_, level) return realG.GetQuestDifficultyColor(level or realG.UnitLevel("player")) end

local origCooldownFrameSetTimer = realG.CooldownFrame_SetTimer
env.CooldownFrame_Set = function(cooldown, start, duration, enable)
	local enabled = enable and enable ~= 0 and 1 or 0
	if origCooldownFrameSetTimer then
		origCooldownFrameSetTimer(cooldown, start, duration, enabled)
	elseif enabled == 1 and duration and duration > 0 then
		cooldown:SetCooldown(start, duration)
		cooldown:Show()
	else
		cooldown:Hide()
	end
end
env.CooldownFrame_Clear = function(cooldown) cooldown:Hide() end

env.NamePlateTooltip = realG.GameTooltip
env.CompactUnitFrame_UnregisterEvents = noop
env.FlashClientIcon = realG.FlashWindow or noop
env.HelpPlate_Show = noop
env.HelpPlate_Hide = noop
env.HelpPlate_IsShowing = retFalse
env.MicroButtonAlert_SetText = noop
env.SetUnitCursorTexture = noop
env.IsTargetLoose = retFalse
env.InCombatLockdownRestriction = retFalse
env.RegisterAddonMessagePrefix = retTrue
env.GetFlyoutInfo = retNil
env.GetFlyoutSlotInfo = retNil
env.ViragDevTool_AddData = noop
env.dumpt = noop

local function fillMacroIcons(t)
	if type(t) ~= "table" then t = {} end
	local getInfo, num = realG.GetMacroIconInfo, realG.GetNumMacroIcons
	if getInfo and num then
		for i = 1, num() do
			local tex = getInfo(i)
			if tex then t[#t + 1] = (tex:gsub("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[Ii][Cc][Oo][Nn][Ss]\\", "")) end
		end
	end
	return t
end
env.GetMacroIcons = fillMacroIcons
env.GetMacroItemIcons = function(t) return t or {} end
env.GetLooseMacroIcons = noop
env.GetLooseMacroItemIcons = noop

env.PlaySound = function(sound, ...) if sound ~= nil then pcall(realG.PlaySound, sound, ...) end end
env.PlaySoundFile = function(sound, ...) if sound ~= nil then pcall(realG.PlaySoundFile, sound, ...) end end

local origGetCVar, origSetCVar, origGetCVarBool, origGetCVarDefault = realG.GetCVar, realG.SetCVar, realG.GetCVarBool, realG.GetCVarDefault
env.GetCVar = function(name) local ok, v = pcall(origGetCVar, name) if ok then return v end end
env.SetCVar = function(name, value, ...) local ok, r = pcall(origSetCVar, name, value, ...) if ok then return r end end
env.GetCVarBool = function(name) local ok, v = pcall(origGetCVarBool, name) if ok then return v end end
env.GetCVarDefault = function(name) if not origGetCVarDefault then return nil end local ok, v = pcall(origGetCVarDefault, name) if ok then return v end end

---------------------------------------------------------------------------------------------------
-- C_ namespaces

env.C_AddOns = {
	GetAddOnMetadata = realG.GetAddOnMetadata,
	IsAddOnLoaded = realG.IsAddOnLoaded,
	GetAddOnInfo = realG.GetAddOnInfo,
	GetNumAddOns = realG.GetNumAddOns,
	LoadAddOn = realG.LoadAddOn,
	EnableAddOn = realG.EnableAddOn,
	DisableAddOn = realG.DisableAddOn,
	IsAddOnLoadOnDemand = realG.IsAddOnLoadOnDemand,
	GetAddOnEnableState = function(_, name)
		local _, _, _, enabled = realG.GetAddOnInfo(name)
		return enabled and 2 or 0
	end,
}
env.C_ChatInfo = {
	RegisterAddonMessagePrefix = retTrue,
	IsAddonMessagePrefixRegistered = retTrue,
	SendAddonMessage = realG.SendAddonMessage,
}
env.C_CVar = {
	GetCVar = env.GetCVar,
	SetCVar = env.SetCVar,
	GetCVarBool = env.GetCVarBool,
	GetCVarDefault = env.GetCVarDefault,
	RegisterCVar = noop,
}
env.C_Container = {
	GetContainerNumSlots = realG.GetContainerNumSlots,
	GetContainerItemLink = realG.GetContainerItemLink,
	GetContainerItemID = function(bag, slot)
		local link = realG.GetContainerItemLink(bag, slot)
		return link and tonumber(link:match("item:(%d+)"))
	end,
	GetContainerItemInfo = function(bag, slot)
		local texture, count, locked, quality, readable, lootable, link = realG.GetContainerItemInfo(bag, slot)
		if not texture then return nil end
		return {iconFileID = texture, stackCount = count, isLocked = locked, quality = quality, isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = false, hasNoValue = false, itemID = link and tonumber(link:match("item:(%d+)")), isBound = false}
	end,
}
env.C_FriendList = {
	GetNumFriends = function() return (realG.GetNumFriends()) end,
	GetFriendInfoByIndex = function(i)
		local name, level, class, area, connected, status, note = realG.GetFriendInfo(i)
		if not name then return nil end
		return {name = name, level = level, className = class, area = area, connected = connected and true or false, notes = note}
	end,
	IsFriend = function(guid) return false end,
}
env.C_BattleNet = {
	GetFriendAccountInfo = function(i)
		local _, _, _, _, toonName, _, client, isOnline = env.BNGetFriendInfo(i)
		return {gameAccountInfo = {characterName = toonName, isOnline = isOnline, clientProgram = client}}
	end,
}
env.C_Map = {
	GetBestMapForUnit = function(unit)
		if unit == "player" and realG.GetCurrentMapAreaID then return realG.GetCurrentMapAreaID() end
	end,
	GetMapInfo = function(mapID) return {mapID = mapID, name = realG.GetZoneText()} end,
}
env.C_QuestLog = {}
env.C_Texture = { GetAtlasInfo = retNil }
env.C_TooltipInfo = false
env.C_Traits = false
env.C_ClassTalents = { GetActiveConfigID = retNil }
env.C_SpecializationInfo = { GetAllSelectedPvpTalentIDs = retEmptyTable, GetPvpTalentSlotInfo = retNil }
env.C_ChallengeMode = {
	IsChallengeModeActive = retFalse,
	GetActiveKeystoneInfo = function() return 0, {}, false end,
	GetAffixInfo = retNil,
	GetActiveChallengeMapID = retNil,
}
env.C_EncounterJournal = { GetSectionInfo = retNil }
env.C_PvP = { GetScoreInfo = retNil, IsPVPMap = retFalse, IsRatedMap = retFalse }
env.C_TaskQuest = { GetQuestsForPlayerByMapID = retNil, GetQuestInfoByQuestID = retNil }
env.C_AlliedRaces = { GetRaceInfoByID = retNil }
env.C_GameRules = false
env.C_GuildInfo = {}
env.C_Spell = false
env.C_Item = false

env.Settings = false
env.SettingsPanel = false
env.BackdropTemplateMixin = {}

env.TextureLoadingGroupMixin = { AddTexture = noop, RemoveTexture = noop, IsEmpty = retTrue }
env.DefaultCompactNamePlateFrameSetUpOptions = {}
env.DefaultCompactNamePlateFriendlyFrameOptions = {}
env.DefaultCompactNamePlateEnemyFrameOptions = {}
env.DefaultCompactNamePlatePlayerFrameSetUpOptions = {}
env.NamePlateDriverFrame = {
	SetupClassNameplateBars = noop,
	UpdateNamePlateOptions = noop,
	namePlateSetInsetFunctions = { friendly = noop, enemy = noop, player = noop },
}

for _, fontName in ipairs({"SystemFont_NamePlate", "SystemFont_NamePlateFixed", "SystemFont_LargeNamePlate", "SystemFont_LargeNamePlateFixed"}) do
	if not realG[fontName] then
		local font = CreateFont("Plater335_" .. fontName)
		font:SetFontObject(realG.GameFontNormalSmall)
		env[fontName] = font
	end
end

---------------------------------------------------------------------------------------------------
-- GUIDs (3.3.5 uses hex GUIDs)

function Compat.NpcIDFromGUID(guid)
	if type(guid) ~= "string" or guid == "" then return nil end
	if guid:sub(1, 2) == "0x" then
		local guidType = tonumber(guid:sub(5, 5), 16)
		if guidType == 3 or guidType == 5 then
			return tonumber(guid:sub(8, 12), 16)
		end
		return nil
	end
	return tonumber((select(6, strsplit("-", guid))))
end

---------------------------------------------------------------------------------------------------
-- widget methods that 3.3.5 lacks (added to the shared metatables only when missing)

do
	local probeFrame = origCreateFrame("Frame")
	local samples = {
		Frame = probeFrame,
		Button = origCreateFrame("Button"),
		CheckButton = origCreateFrame("CheckButton"),
		StatusBar = origCreateFrame("StatusBar"),
		Slider = origCreateFrame("Slider"),
		ScrollFrame = origCreateFrame("ScrollFrame"),
		Cooldown = origCreateFrame("Cooldown"),
		Model = origCreateFrame("Model"),
		PlayerModel = origCreateFrame("PlayerModel"),
		GameTooltip = realG.GameTooltip,
		Texture = probeFrame:CreateTexture(),
		FontString = probeFrame:CreateFontString(),
	}
	local editBox = origCreateFrame("EditBox")
	editBox:SetAutoFocus(false)
	editBox:Hide()
	samples.EditBox = editBox
	for _, obj in pairs(samples) do if obj.Hide and obj ~= realG.GameTooltip then obj:Hide() end end

	local animGroup = probeFrame:CreateAnimationGroup()
	samples.AnimationGroup = animGroup
	samples.Alpha = animGroup:CreateAnimation("Alpha")
	samples.Scale = animGroup:CreateAnimation("Scale")
	samples.Translation = animGroup:CreateAnimation("Translation")
	samples.Rotation = animGroup:CreateAnimation("Rotation")

	local function methodsOf(obj)
		local mt = getmetatable(obj)
		return mt and type(mt.__index) == "table" and mt.__index
	end
	local function add(kinds, name, func)
		for _, kind in ipairs(kinds) do
			local m = samples[kind] and methodsOf(samples[kind])
			if m and m[name] == nil then m[name] = func end
		end
	end

	local FRAMES = {"Frame", "Button", "CheckButton", "StatusBar", "Slider", "ScrollFrame", "Cooldown", "Model", "PlayerModel", "EditBox", "GameTooltip"}
	local REGIONS = {"Texture", "FontString"}
	local ALL = {"Frame", "Button", "CheckButton", "StatusBar", "Slider", "ScrollFrame", "Cooldown", "Model", "PlayerModel", "EditBox", "GameTooltip", "Texture", "FontString"}
	local ANIMS = {"Alpha", "Scale", "Translation", "Rotation"}

	add(ALL, "SetShown", function(self, shown) if shown then self:Show() else self:Hide() end end)
	add(ALL, "IsForbidden", retFalse)
	add(ALL, "GetParentKey", retNil)
	add(ALL, "SetIgnoreParentAlpha", noop)
	add(ALL, "SetIgnoreParentScale", noop)
	add(ALL, "SetSnapToPixelGrid", noop)
	add(ALL, "SetTexelSnappingBias", noop)
	add(ALL, "IsObjectLoaded", retTrue)
	add({"Button", "CheckButton"}, "SetEnabled", function(self, enabled) if enabled then self:Enable() else self:Disable() end end)
	add({"Slider", "EditBox"}, "SetEnabled", function(self, enabled) if enabled then if self.Enable then self:Enable() end else if self.Disable then self:Disable() end end end)

	add(FRAMES, "SetResizeBounds", function(self, minW, minH, maxW, maxH)
		if minW and minH then self:SetMinResize(minW, minH) end
		if maxW and maxH then self:SetMaxResize(maxW, maxH) end
	end)
	add(FRAMES, "EnableMouseMotion", noop)
	add(FRAMES, "SetMouseMotionEnabled", noop)
	add(FRAMES, "SetMouseClickEnabled", noop)
	add(FRAMES, "SetFixedFrameStrata", noop)
	add(FRAMES, "SetFixedFrameLevel", noop)
	add(FRAMES, "SetClipsChildren", noop)
	add(FRAMES, "SetFlattensRenderLayers", noop)
	add(FRAMES, "SetIsFrameBuffer", noop)
	add(FRAMES, "SetPropagateKeyboardInput", noop)
	add(FRAMES, "SetUsingParentLevel", noop)

	-- textures created in place of mask textures and lines
	local function createMaskTexture(self, name, layer)
		local tex = self:CreateTexture(name, layer or "artwork")
		tex:Hide()
		return tex
	end
	add(FRAMES, "CreateMaskTexture", createMaskTexture)
	local lineMethods = {
		SetStartPoint = function(self, ...) self.__startPoint = {...} end,
		SetEndPoint = function(self, ...) self.__endPoint = {...} end,
		SetThickness = function(self, t) self.__thickness = t end,
		GetThickness = function(self) return self.__thickness or 1 end,
		SetColorTexture = function(self, r, g, b, a) self:SetTexture(r, g, b, a) end,
	}
	add(FRAMES, "CreateLine", function(self, name, layer, template, subLevel)
		local tex = self:CreateTexture(name, layer or "artwork")
		for k, f in pairs(lineMethods) do tex[k] = f end
		tex:Hide()
		return tex
	end)

	add({"Texture"}, "SetColorTexture", function(self, r, g, b, a) self:SetTexture(r, g, b, a or 1) end)
	add({"Texture"}, "SetMask", noop)
	add({"Texture"}, "AddMaskTexture", noop)
	add({"Texture"}, "RemoveMaskTexture", noop)
	add({"Texture"}, "GetNumMaskTextures", retZero)
	add({"Texture"}, "GetMaskTexture", retNil)
	add({"Texture"}, "SetDesaturation", function(self, d) self:SetDesaturated(d and d > 0) end)
	add({"Texture"}, "GetDesaturated", function(self) return self:IsDesaturated() end)
	add({"Texture"}, "GetDesaturation", function(self) return self:IsDesaturated() and 1 or 0 end)
	add({"Texture"}, "SetAtlas", function(self) self:SetTexture(nil) end)
	add({"Texture"}, "GetAtlas", retNil)

	add({"StatusBar"}, "SetReverseFill", noop)
	add({"StatusBar"}, "GetReverseFill", retFalse)
	add({"StatusBar"}, "SetFillStyle", noop)
	add({"StatusBar"}, "SetStatusBarDesaturated", noop)

	add({"Slider"}, "SetObeyStepOnDrag", noop)
	add({"Slider"}, "SetStepsPerPage", noop)

	add({"Cooldown"}, "SetDrawSwipe", noop)
	add({"Cooldown"}, "SetDrawBling", noop)
	add({"Cooldown"}, "SetDrawEdge", noop)
	add({"Cooldown"}, "SetSwipeColor", noop)
	add({"Cooldown"}, "SetSwipeTexture", noop)
	add({"Cooldown"}, "SetEdgeTexture", noop)
	add({"Cooldown"}, "SetBlingTexture", noop)
	add({"Cooldown"}, "SetHideCountdownNumbers", noop)
	add({"Cooldown"}, "SetUseCircularEdge", noop)
	add({"Cooldown"}, "SetCountdownFont", noop)
	add({"Cooldown"}, "SetCooldownDuration", noop)
	add({"Cooldown"}, "GetCooldownDuration", retZero)
	add({"Cooldown"}, "Clear", function(self) self:Hide() end)

	add({"EditBox"}, "SetCountInvisibleLetters", noop)
	add({"FontString"}, "SetMaxLines", noop)
	-- regions have no scale on 3.3.5: emulate by resizing from the last unscaled size
	add(REGIONS, "SetScale", function(self, scale)
		scale = scale or 1
		local w, h = self:GetWidth(), self:GetHeight()
		local applied = self.__p335applied
		local baseW, baseH = w, h
		if applied and math.abs(applied[1] - w) < 0.01 and math.abs(applied[2] - h) < 0.01 then
			baseW, baseH = applied[3], applied[4]
		end
		self.__p335scale = scale
		if baseW > 0 and baseH > 0 then
			self:SetWidth(baseW * scale)
			self:SetHeight(baseH * scale)
			self.__p335applied = {baseW * scale, baseH * scale, baseW, baseH}
		end
	end)
	add(REGIONS, "GetScale", function(self) return self.__p335scale or 1 end)
	add(REGIONS, "GetEffectiveScale", function(self) return (self.__p335scale or 1) * self:GetParent():GetEffectiveScale() end)
	add({"FontString"}, "SetTextScale", noop)
	add({"FontString"}, "GetTextScale", function() return 1 end)
	add({"FontString"}, "GetMaxLines", retZero)
	add({"FontString"}, "GetLineHeight", function(self) local _, size = self:GetFont() return size or 12 end)
	add({"FontString"}, "GetUnboundedStringWidth", function(self) return self:GetStringWidth() end)
	add({"FontString"}, "IsTruncated", retFalse)
	add({"FontString"}, "SetWordWrap", noop)
	add({"FontString"}, "SetNonSpaceWrap", noop)
	add({"FontString"}, "SetFontObjectsToTry", noop)

	-- animations: emulate absolute alpha/scale ranges on top of the 3.3.5 relative animations
	local function alphaOnPlay(self)
		local region = self:GetRegionParent()
		if region then
			self.__p335orig = region:GetAlpha()
			if self.__p335from then region:SetAlpha(self.__p335from) end
		end
	end
	local function alphaOnUpdate(self)
		local region = self:GetRegionParent()
		local from, to = self.__p335from, self.__p335to
		if region and from and to then
			local progress = self.GetSmoothProgress and self:GetSmoothProgress() or self:GetProgress() or 0
			region:SetAlpha(from + (to - from) * progress)
		end
	end
	local function alphaOnFinished(self)
		local region = self:GetRegionParent()
		if not region then return end
		if self.__p335final or (self:GetParent() and self:GetParent().__p335final) then
			if self.__p335to then region:SetAlpha(self.__p335to) end
		elseif self.__p335orig then
			region:SetAlpha(self.__p335orig)
		end
	end
	local function alphaOnStop(self)
		local region = self:GetRegionParent()
		if region and self.__p335orig then region:SetAlpha(self.__p335orig) end
	end
	local function setupAlpha(self)
		if self.__p335alpha then return end
		self.__p335alpha = true
		self:SetChange(0)
		self:SetScript("OnPlay", alphaOnPlay)
		self:SetScript("OnUpdate", alphaOnUpdate)
		self:SetScript("OnFinished", alphaOnFinished)
		self:SetScript("OnStop", alphaOnStop)
	end
	add({"Alpha"}, "SetFromAlpha", function(self, a) self.__p335from = a setupAlpha(self) end)
	add({"Alpha"}, "SetToAlpha", function(self, a) self.__p335to = a setupAlpha(self) end)
	add({"Alpha"}, "GetFromAlpha", function(self) return self.__p335from or 0 end)
	add({"Alpha"}, "GetToAlpha", function(self) return self.__p335to or 0 end)

	local function applyScale(self)
		local fx, fy = self.__p335fromX or 1, self.__p335fromY or 1
		local tx, ty = self.__p335toX or 1, self.__p335toY or 1
		self:SetScale(fx ~= 0 and tx / fx or tx, fy ~= 0 and ty / fy or ty)
	end
	local setFromScale = function(self, x, y) self.__p335fromX, self.__p335fromY = x, y or x applyScale(self) end
	local setToScale = function(self, x, y) self.__p335toX, self.__p335toY = x, y or x applyScale(self) end
	add({"Scale"}, "SetFromScale", setFromScale)
	add({"Scale"}, "SetToScale", setToScale)
	add({"Scale"}, "SetScaleFrom", setFromScale)
	add({"Scale"}, "SetScaleTo", setToScale)
	add({"Scale"}, "ScaleBy", function(self, x, y) self:SetScale(x, y or x) end)

	add(ANIMS, "SetToFinalAlpha", function(self, v) self.__p335final = v end)
	add(ANIMS, "SetTarget", noop)
	add(ANIMS, "SetChildKey", noop)
	add(ANIMS, "SetTargetKey", noop)
	add(ANIMS, "SetStartColor", noop)
	add(ANIMS, "SetEndColor", noop)
	add(ANIMS, "SetFlipBookColumns", noop)
	add(ANIMS, "SetFlipBookRows", noop)
	add(ANIMS, "SetFlipBookFrames", noop)
	add(ANIMS, "SetFlipBookFrameWidth", noop)
	add(ANIMS, "SetFlipBookFrameHeight", noop)
	add({"AnimationGroup"}, "SetToFinalAlpha", function(self, v) self.__p335final = v end)
	add({"AnimationGroup"}, "SetAnimationSpeedMultiplier", noop)
	add({"AnimationGroup"}, "GetAnimationSpeedMultiplier", function() return 1 end)
	add({"AnimationGroup"}, "Restart", function(self) self:Stop() self:Play() end)

	-- unknown animation types (FlipBook, VertexColor, ...) fall back to a plain animation
	local groupMethods = methodsOf(animGroup)
	local origCreateAnimation = groupMethods.CreateAnimation
	local fallbackMethods = {
		SetFromAlpha = noop, SetToAlpha = noop, SetFromScale = noop, SetToScale = noop, SetScaleFrom = noop, SetScaleTo = noop,
		SetOffset = noop, SetDegrees = noop, SetOrigin = noop, SetStartColor = noop, SetEndColor = noop,
		SetFlipBookColumns = noop, SetFlipBookRows = noop, SetFlipBookFrames = noop, SetFlipBookFrameWidth = noop, SetFlipBookFrameHeight = noop,
		SetTarget = noop, SetChildKey = noop, SetToFinalAlpha = noop,
	}
	groupMethods.CreateAnimation = function(self, animType, ...)
		local ok, anim = pcall(origCreateAnimation, self, animType, ...)
		if ok and anim then return anim end
		anim = origCreateAnimation(self, "Animation", ...)
		for k, f in pairs(fallbackMethods) do if anim[k] == nil then anim[k] = f end end
		return anim
	end

	Compat.FrameMethods = methodsOf(probeFrame)
end

---------------------------------------------------------------------------------------------------
-- frames created by Plater: event aliases, unit filters, 3.3.5 payload conversion

local FrameMethods = Compat.FrameMethods
local origRegisterEvent = FrameMethods.RegisterEvent
local origUnregisterEvent = FrameMethods.UnregisterEvent
local origUnregisterAllEvents = FrameMethods.UnregisterAllEvents
local origSetScript = FrameMethods.SetScript
local origGetScript = FrameMethods.GetScript

local POWER_EVENTS = {UNIT_MANA = "MANA", UNIT_RAGE = "RAGE", UNIT_ENERGY = "ENERGY", UNIT_FOCUS = "FOCUS", UNIT_RUNIC_POWER = "RUNIC_POWER", UNIT_HAPPINESS = "HAPPINESS"}
local MAXPOWER_EVENTS = {UNIT_MAXMANA = "MANA", UNIT_MAXRAGE = "RAGE", UNIT_MAXENERGY = "ENERGY", UNIT_MAXFOCUS = "FOCUS", UNIT_MAXRUNIC_POWER = "RUNIC_POWER", UNIT_MAXHAPPINESS = "HAPPINESS"}
local EVENT_ALIASES = {
	GROUP_ROSTER_UPDATE = {"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"},
	UNIT_POWER_UPDATE = {"UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_RUNIC_POWER", "UNIT_HAPPINESS"},
	UNIT_POWER_FREQUENT = {"UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_RUNIC_POWER", "UNIT_HAPPINESS"},
	UNIT_MAXPOWER = {"UNIT_MAXMANA", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_MAXRUNIC_POWER", "UNIT_MAXHAPPINESS"},
	UNIT_HEALTH_FREQUENT = {},
	PLAYER_SPECIALIZATION_CHANGED = {"ACTIVE_TALENT_GROUP_CHANGED"},
}
local SPELLCAST_EVENTS = {
	UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTIBLE = true,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true, UNIT_SPELLCAST_FAILED_QUIET = true,
}

-- registry[event][frame] = true, used to deliver synthesized events for nameplate units
local registry = {}
Compat.registry = registry
local function track(frame, event, on)
	local r = registry[event]
	if on then
		if not r then r = {} registry[event] = r end
		r[frame] = true
	elseif r then
		r[frame] = nil
	end
end

local function safeRegister(frame, event)
	return pcall(origRegisterEvent, frame, event)
end

local function p_RegisterEvent(self, event)
	local aliases = EVENT_ALIASES[event]
	if aliases then
		self.__p335alias = self.__p335alias or {}
		for _, native in ipairs(aliases) do
			local set = self.__p335alias[native]
			if not set then set = {} self.__p335alias[native] = set end
			set[event] = true
			safeRegister(self, native)
			track(self, native, true)
		end
		track(self, event, true)
		return true
	end
	if self.__p335units then self.__p335units[event] = nil end
	track(self, event, true)
	return safeRegister(self, event)
end

local function p_RegisterUnitEvent(self, event, unit1, unit2)
	p_RegisterEvent(self, event)
	if unit1 or unit2 then
		self.__p335units = self.__p335units or {}
		local filter = {}
		if unit1 then filter[unit1] = true end
		if unit2 then filter[unit2] = true end
		self.__p335units[event] = filter
		local aliases = EVENT_ALIASES[event]
		if aliases then
			for _, native in ipairs(aliases) do self.__p335units[native] = filter end
		end
	end
	return true
end

local function p_UnregisterEvent(self, event)
	local aliases = EVENT_ALIASES[event]
	if aliases and self.__p335alias then
		for _, native in ipairs(aliases) do
			local set = self.__p335alias[native]
			if set then
				set[event] = nil
				if not next(set) then
					self.__p335alias[native] = nil
					pcall(origUnregisterEvent, self, native)
					track(self, native, false)
					if self.__p335units then self.__p335units[native] = nil end
				end
			end
		end
	else
		pcall(origUnregisterEvent, self, event)
	end
	if self.__p335units then self.__p335units[event] = nil end
	track(self, event, false)
end

local function p_UnregisterAllEvents(self)
	origUnregisterAllEvents(self)
	self.__p335alias = nil
	self.__p335units = nil
	for _, frames in pairs(registry) do frames[self] = nil end
end

-- called before Plater's own handlers see the event
local preHooks = {}
Compat.preHooks = preHooks

local function deliver(self, handler, event, arg1, ...)
	local filter = self.__p335units and self.__p335units[event]
	if filter and arg1 and not filter[arg1] then return end
	if SPELLCAST_EVENTS[event] then
		return handler(self, event, arg1, nil, Compat.GetCastSpellID(arg1, (...)))
	end
	return handler(self, event, arg1, ...)
end

local function wrapOnEvent(handler)
	return function(self, event, ...)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			Compat.SetCombatLogArgs(...)
			return handler(self, event)
		end
		local pre = preHooks[event]
		if pre then pre(self, handler, ...) end
		local aliasSet = self.__p335alias and self.__p335alias[event]
		if aliasSet then
			local unit = ...
			local powerToken = POWER_EVENTS[event] or MAXPOWER_EVENTS[event]
			for aliasEvent in pairs(aliasSet) do
				if powerToken then
					deliver(self, handler, aliasEvent, unit, powerToken)
				else
					deliver(self, handler, aliasEvent, ...)
				end
			end
			return
		end
		return deliver(self, handler, event, ...)
	end
end

local wrappedHandlers = setmetatable({}, {__mode = "k"})
local function p_SetScript(self, script, handler)
	if script == "OnEvent" and type(handler) == "function" then
		local wrapped = wrappedHandlers[handler]
		if not wrapped then
			wrapped = wrapOnEvent(handler)
			wrappedHandlers[handler] = wrapped
		end
		self.__p335onEvent = handler
		return origSetScript(self, script, wrapped)
	end
	if script == "OnEvent" then self.__p335onEvent = nil end
	return origSetScript(self, script, handler)
end
local function p_GetScript(self, script)
	if script == "OnEvent" and self.__p335onEvent then return self.__p335onEvent end
	return origGetScript(self, script)
end

-- retail SetAtlas returns false for unknown atlases; the client's SharedXML version errors
local function safeSetAtlas(self, ...)
	local ok, result = pcall(getmetatable(self).__index.SetAtlas, self, ...)
	if ok then return result end
	return false
end

local function p_CreateTexture(self, ...)
	local tex = getmetatable(self).__index.CreateTexture(self, ...)
	tex.SetAtlas = safeSetAtlas
	return tex
end
Compat.CreateTexture = p_CreateTexture

function Compat.PatchFrame(frame)
	if not frame or frame.__p335patched then return frame end
	frame.__p335patched = true
	frame.CreateTexture = p_CreateTexture
	frame.RegisterEvent = p_RegisterEvent
	frame.RegisterUnitEvent = p_RegisterUnitEvent
	frame.UnregisterEvent = p_UnregisterEvent
	frame.UnregisterAllEvents = p_UnregisterAllEvents
	frame.SetScript = p_SetScript
	frame.GetScript = p_GetScript
	local existing = origGetScript(frame, "OnEvent")
	if existing then p_SetScript(frame, "OnEvent", existing) end
	return frame
end

local STRIPPED_TEMPLATES = {BackdropTemplate = true}
local function cleanTemplate(template)
	if type(template) ~= "string" then return template end
	local kept
	for name in template:gmatch("[^,%s]+") do
		if not STRIPPED_TEMPLATES[name] then kept = kept and (kept .. "," .. name) or name end
	end
	return kept
end

-- 3.3.5 scroll templates only expose their parts as named globals; retail uses parentKeys
function Compat.FillScrollBar(frame)
	if frame.ScrollBar then return end
	local name = frame:GetName()
	local bar = name and realG[name .. "ScrollBar"]
	if not bar then
		for _, child in ipairs({frame:GetChildren()}) do
			if child:GetObjectType() == "Slider" then bar = child break end
		end
	end
	if not bar then return end
	frame.ScrollBar = bar
	local barName = bar:GetName()
	local up = barName and realG[barName .. "ScrollUpButton"]
	local down = barName and realG[barName .. "ScrollDownButton"]
	if not up or not down then
		local buttons = {}
		for _, child in ipairs({bar:GetChildren()}) do
			if child:GetObjectType() == "Button" then buttons[#buttons + 1] = child end
		end
		up, down = up or buttons[1], down or buttons[2]
	end
	bar.ScrollUpButton, bar.ScrollDownButton = up, down
	bar.ThumbTexture = bar.ThumbTexture or bar:GetThumbTexture()
	for _, button in ipairs({up, down}) do
		button.Normal = button.Normal or button:GetNormalTexture()
		button.Pushed = button.Pushed or button:GetPushedTexture()
		button.Disabled = button.Disabled or button:GetDisabledTexture()
		button.Highlight = button.Highlight or button:GetHighlightTexture()
	end
end

-- retail-only templates are dropped (and remembered) instead of erroring
env.CreateFrame = function(frameType, name, parent, template, id)
	local frame = Compat.CreateFrameRaw(frameType, name, parent, template, id)
	if template and type(frameType) == "string" and frameType:lower() == "scrollframe" then
		Compat.FillScrollBar(frame)
	end
	return frame
end

function Compat.CreateFrameRaw(frameType, name, parent, template, id)
	template = cleanTemplate(template)
	for _ = 1, 5 do
		local ok, frame = pcall(origCreateFrame, frameType, name, parent, template, id)
		if ok then return Compat.PatchFrame(frame) end
		local missing = type(frame) == "string" and frame:match('inherited node "([^"]+)"')
		if not missing or not template then error(frame, 2) end
		STRIPPED_TEMPLATES[missing] = true
		template = cleanTemplate(template)
	end
	return Compat.PatchFrame(origCreateFrame(frameType, name, parent, nil, id))
end

---------------------------------------------------------------------------------------------------
-- nameplates (rebuffed.dll / awesome_wotlk C_NamePlate)

local realNP = realG.C_NamePlate or {}
local npGetForUnit = realNP.GetNamePlateForUnit or retNil
local npGetPlates = realNP.GetNamePlates or retEmptyTable
local npTokenByGUID = realNP.GetNamePlateTokenByGUID or retNil

local plateCount = 0
local tokenByPlate = {}
local activeTokens = {}
Compat.activeTokens = activeTokens

function Compat.PlateName(plate)
	return plate.__p335name or plate:GetName() or "Plater335NamePlate"
end

-- the client keeps re-showing native regions (name, threat glow, target glow) in combat,
-- so while Plater owns a plate they are hidden outright and re-checked every frame
local hiddenPlates = {}
local function hideNative(native)
	for _, region in ipairs(native.regions) do
		if region:IsShown() then
			native.wasShown[region] = true
			region:Hide()
		end
		if region:GetAlpha() > 0 then region:SetAlpha(0) end
	end
	for _, bar in ipairs(native.bars) do
		if bar:GetAlpha() > 0 then bar:SetAlpha(0) end
	end
end

local function setNativeVisible(plate, visible)
	local native = plate.__p335native
	if not native then return end
	if visible then
		hiddenPlates[plate] = nil
		for _, region in ipairs(native.regions) do
			region:SetAlpha(1)
			if native.wasShown[region] then region:Show() end
		end
		wipe(native.wasShown)
		for _, bar in ipairs(native.bars) do bar:SetAlpha(1) end
	else
		hiddenPlates[plate] = native
		hideNative(native)
	end
end
Compat.HiddenPlates = hiddenPlates
Compat.HideNative = hideNative
Compat.SetNativeVisible = setNativeVisible

function Compat.PreparePlate(plate)
	if not plate or plate.__p335name then return end
	plateCount = plateCount + 1
	plate.__p335name = "Plater335NamePlate" .. plateCount
	plate.CreateTexture = p_CreateTexture

	local native = {regions = {}, bars = {}, wasShown = {}}
	for _, region in ipairs({plate:GetRegions()}) do native.regions[#native.regions + 1] = region end
	for _, child in ipairs({plate:GetChildren()}) do
		if child:GetObjectType() == "StatusBar" and not child:GetName() and #native.bars < 2 then
			native.bars[#native.bars + 1] = child
		end
	end
	plate.__p335native = native

	local proxy = origCreateFrame("Frame", nil, plate)
	local proxyShow, proxyHide = proxy.Show, proxy.Hide
	proxy.Show = function(self) setNativeVisible(plate, true) proxyShow(self) end
	proxy.Hide = function(self) setNativeVisible(plate, false) proxyHide(self) end
	proxy.CastBar = native.bars[2] or {}
	proxy.healthBar = native.bars[1]
	proxy.isProxy = true
	plate.UnitFrame = proxy
end

env.C_NamePlate = setmetatable({
	GetNamePlates = function()
		local list = {}
		for plate in pairs(tokenByPlate) do
			if plate.unitFramePlater then list[#list + 1] = plate end
		end
		return list
	end,
	GetNamePlateForUnit = function(unit)
		if not unit or unit == "player" then return nil end
		return npGetForUnit(unit)
	end,
	SetNamePlateEnemySize = noop, SetNamePlateFriendlySize = noop, SetNamePlateSelfSize = noop,
	SetNamePlateEnemyClickThrough = noop, SetNamePlateFriendlyClickThrough = noop, SetNamePlateSelfClickThrough = noop,
	SetNamePlateEnemyPreferredClickInsets = noop, SetNamePlateFriendlyPreferredClickInsets = noop, SetNamePlateSelfPreferredClickInsets = noop,
	GetNamePlateEnemySize = function() return 110, 45 end,
	GetNamePlateFriendlySize = function() return 110, 45 end,
	GetNamePlateSelfSize = function() return 110, 45 end,
	GetNamePlateEnemyClickThrough = retFalse, GetNamePlateFriendlyClickThrough = retFalse, GetNamePlateSelfClickThrough = retFalse,
	SetTargetClampingInsets = noop,
}, {__index = realNP})

local function trackUnitAdded(token)
	local plate = npGetForUnit(token)
	if not plate then return end
	Compat.PreparePlate(plate)
	local oldToken = tokenByPlate[plate]
	if oldToken and oldToken ~= token then activeTokens[oldToken] = nil end
	tokenByPlate[plate] = token
	activeTokens[token] = plate
	setNativeVisible(plate, true)
	Compat.ResetUnitState(token)
	return plate
end

local function trackUnitRemoved(token)
	local plate = activeTokens[token]
	activeTokens[token] = nil
	if plate and tokenByPlate[plate] == token then tokenByPlate[plate] = nil end
	Compat.ResetUnitState(token)
end

preHooks.NAME_PLATE_CREATED = function(self, handler, plate)
	Compat.PreparePlate(plate)
end
preHooks.NAME_PLATE_UNIT_ADDED = function(self, handler, token)
	local plate = trackUnitAdded(token)
	if plate and not plate.unitFramePlater and registry.NAME_PLATE_CREATED and registry.NAME_PLATE_CREATED[self] then
		handler(self, "NAME_PLATE_CREATED", plate)
	end
end
preHooks.NAME_PLATE_UNIT_REMOVED = function(self, handler, token)
	trackUnitRemoved(token)
end

---------------------------------------------------------------------------------------------------
-- unit events for nameplate tokens: remap from other unit ids, poll health/casts, combat log auras

local nativeTokenEvents = {}
local unitState = {}
local auraDirty = {}

function Compat.ResetUnitState(token)
	unitState[token] = nil
	auraDirty[token] = nil
end

local function dispatch(event, unit, ...)
	local frames = registry[event]
	if not frames then return end
	for frame in pairs(frames) do
		local handler = origGetScript(frame, "OnEvent")
		if handler then handler(frame, event, unit, ...) end
	end
end
Compat.Dispatch = dispatch

local REMAP_EVENTS = {"UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_TARGET", "UNIT_LEVEL", "UNIT_HEALTH", "UNIT_MAXHEALTH"}
local NATIVE_PROBE_EVENTS = {"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START"}

local lastRemap = {}
local eventFrame = origCreateFrame("Frame")
for _, e in ipairs(REMAP_EVENTS) do origRegisterEvent(eventFrame, e) end
for _, e in ipairs(NATIVE_PROBE_EVENTS) do origRegisterEvent(eventFrame, e) end
origRegisterEvent(eventFrame, "COMBAT_LOG_EVENT_UNFILTERED")
origRegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD")
pcall(origRegisterEvent, eventFrame, "NAME_PLATE_UNIT_ADDED")
pcall(origRegisterEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED")
pcall(origRegisterEvent, eventFrame, "NAME_PLATE_CREATED")

local AURA_SUBEVENTS = {
	SPELL_AURA_APPLIED = true, SPELL_AURA_REMOVED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true,
	SPELL_AURA_REMOVED_DOSE = true, SPELL_AURA_BROKEN = true, SPELL_AURA_BROKEN_SPELL = true, SPELL_DISPEL = true, SPELL_STOLEN = true,
}

local function onCombatLog(_, subEvent, srcGUID, _, _, dstGUID, _, _, spellId, spellName)
	if (subEvent == "SPELL_CAST_START" or subEvent == "SPELL_CAST_SUCCESS") and srcGUID and spellId then
		local entry = castSpellByGUID[srcGUID]
		if not entry then entry = {} castSpellByGUID[srcGUID] = entry end
		entry.id, entry.name = spellId, spellName
	elseif subEvent == "SPELL_INTERRUPT" and dstGUID then
		local token = npTokenByGUID(dstGUID)
		if token and unitState[token] then unitState[token].interrupted = true end
	elseif subEvent == "UNIT_DIED" and dstGUID then
		castSpellByGUID[dstGUID] = nil
	end
	if AURA_SUBEVENTS[subEvent] and dstGUID then
		local token = npTokenByGUID(dstGUID)
		if token and activeTokens[token] then auraDirty[token] = true end
	end
end

eventFrame:SetScript("OnEvent", function(self, event, unit, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, subEvent, third = unit, ...
		if type(third) == "boolean" then
			local _, _, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName = unit, ...
			return onCombatLog(nil, subEvent, srcGUID, nil, nil, dstGUID, nil, nil, spellId, spellName)
		end
		return onCombatLog(unit, ...)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		if not activeTokens[unit] or activeTokens[unit] ~= npGetForUnit(unit) then trackUnitAdded(unit) end
		return
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		trackUnitRemoved(unit)
		return
	elseif event == "NAME_PLATE_CREATED" then
		Compat.PreparePlate(unit)
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		Compat.ScheduleExistingPlates()
		return
	end
	if type(unit) ~= "string" then return end
	if unit:find("^nameplate%d") then
		nativeTokenEvents[event] = true
		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then nativeTokenEvents.casts = true end
		if event == "UNIT_HEALTH" then nativeTokenEvents.health = true end
		return
	end
	if nativeTokenEvents[event] or SPELLCAST_EVENTS[event] then return end
	local guid = realG.UnitGUID(unit)
	local token = guid and npTokenByGUID(guid)
	if not token or not activeTokens[token] then return end
	local key = event .. token
	local now = GetTime()
	if lastRemap[key] == now then return end
	lastRemap[key] = now
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		local st = unitState[token]
		if st then st.health, st.healthMax = realG.UnitHealth(token), realG.UnitHealthMax(token) end
	elseif event == "UNIT_AURA" then
		auraDirty[token] = nil
	end
	dispatch(event, token)
end)

local function pollToken(token)
	local st = unitState[token]
	local fresh = not st
	if fresh then st = {} unitState[token] = st end

	if not nativeTokenEvents.health then
		local health, healthMax = realG.UnitHealth(token), realG.UnitHealthMax(token)
		if not fresh then
			if healthMax ~= st.healthMax then dispatch("UNIT_MAXHEALTH", token) end
			if health ~= st.health then dispatch("UNIT_HEALTH", token) end
		end
		st.health, st.healthMax = health, healthMax
	end

	if not nativeTokenEvents.casts then
		local name, rank, _, _, startTime, endTime, _, castID, notInterruptible = origUnitCastingInfo(token)
		if name then
			if not fresh then
				if not st.casting or st.castStart ~= startTime or st.castName ~= name then
					st.interrupted = nil
					dispatch("UNIT_SPELLCAST_START", token, name, rank, castID)
				elseif st.castEnd ~= endTime then
					dispatch("UNIT_SPELLCAST_DELAYED", token, name, rank, castID)
				elseif st.notInterruptible ~= notInterruptible then
					dispatch(notInterruptible and "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" or "UNIT_SPELLCAST_INTERRUPTIBLE", token)
				end
			end
			st.casting, st.castName, st.castStart, st.castEnd, st.notInterruptible = true, name, startTime, endTime, notInterruptible
		elseif st.casting then
			st.casting = nil
			if st.interrupted then dispatch("UNIT_SPELLCAST_INTERRUPTED", token, st.castName) end
			dispatch("UNIT_SPELLCAST_STOP", token, st.castName)
			st.interrupted = nil
		end

		local cname, crank, _, _, cstart, cend, _, cNotInterruptible = origUnitChannelInfo(token)
		if cname then
			if not fresh then
				if not st.channeling or st.chanStart ~= cstart or st.chanName ~= cname then
					st.interrupted = nil
					dispatch("UNIT_SPELLCAST_CHANNEL_START", token, cname, crank)
				elseif st.chanEnd ~= cend then
					dispatch("UNIT_SPELLCAST_CHANNEL_UPDATE", token, cname, crank)
				end
			end
			st.channeling, st.chanName, st.chanStart, st.chanEnd = true, cname, cstart, cend
			st.notInterruptible = cNotInterruptible
		elseif st.channeling then
			st.channeling = nil
			if st.interrupted then dispatch("UNIT_SPELLCAST_INTERRUPTED", token, st.chanName) end
			dispatch("UNIT_SPELLCAST_CHANNEL_STOP", token, st.chanName)
			st.interrupted = nil
		end
	end

	if auraDirty[token] then
		auraDirty[token] = nil
		dispatch("UNIT_AURA", token)
	end
end

local POLL_INTERVAL = 0.1
local pollElapsed = 0
local pollFrame = origCreateFrame("Frame")
pollFrame:SetScript("OnUpdate", function(_, elapsed)
	for plate, native in pairs(hiddenPlates) do
		if plate:IsShown() then hideNative(native) end
	end
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < POLL_INTERVAL then return end
	pollElapsed = 0
	for token in pairs(activeTokens) do pollToken(token) end
end)

-- plates that existed before Plater registered its events (e.g. after /reload)
function Compat.ScheduleExistingPlates()
	env.C_Timer.After(0.5, function()
		for i = 1, 40 do
			local token = "nameplate" .. i
			local plate = realG.UnitExists(token) and npGetForUnit(token)
			if plate and plate:IsShown() and not activeTokens[token] then
				trackUnitAdded(token)
				dispatch("NAME_PLATE_UNIT_ADDED", token)
			elseif plate and plate:IsShown() and plate.unitFramePlater and not plate.unitFramePlater.PlaterOnScreen then
				dispatch("NAME_PLATE_UNIT_ADDED", token)
			end
		end
	end)
end

-- retail Unit* APIs return nil for a nil unit; 3.3.5 throws "Usage:" errors
do
	local TWO_UNIT = {UnitReaction = true, UnitCanAttack = true, UnitCanAssist = true, UnitIsFriend = true, UnitIsEnemy = true, UnitCanCooperate = true}
	local names = {}
	for name, f in pairs(realG) do
		if type(name) == "string" and type(f) == "function" and name:match("^Unit%u%a*$") then names[#names + 1] = name end
	end
	for name in pairs(env) do
		if type(name) == "string" and type(rawget(env, name)) == "function" and name:match("^Unit%u%a*$") and realG[name] == nil then names[#names + 1] = name end
	end
	for _, name in ipairs(names) do
		local f = rawget(env, name) or realG[name]
		if name ~= "UnitIsUnit" then
			if TWO_UNIT[name] then
				env[name] = function(a, b, ...) if a == nil or b == nil then return nil end return f(a, b, ...) end
			else
				env[name] = function(unit, ...) if unit == nil then return nil end return f(unit, ...) end
			end
		end
	end
end

envMeta.__newindex = function(_, k, v) realG[k] = v end
