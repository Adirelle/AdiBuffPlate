--[[
AdiBuffPlate -- Display Damage over Time debuffs
Copyright 2010 Adirelle
All rights reserved.
--]]

--<GLOBALS
local _G = _G
local band = _G.bit.band
local ceil = _G.ceil
local COMBATLOG_OBJECT_AFFILIATION_MINE = _G.COMBATLOG_OBJECT_AFFILIATION_MINE
local COMBATLOG_OBJECT_REACTION_FRIENDLY = _G.COMBATLOG_OBJECT_REACTION_FRIENDLY
local COMBATLOG_OBJECT_REACTION_MASK = _G.COMBATLOG_OBJECT_REACTION_MASK
local CreateFrame = _G.CreateFrame
local floor = _G.floor
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local huge = _G.math.huge
local ipairs = _G.ipairs
local max = _G.max
local min = _G.min
local next = _G.next
local pairs = _G.pairs
local setmetatable = _G.setmetatable
local tinsert = _G.tinsert
local tonumber = _G.tonumber
local tostring = _G.tostring
local tsort = _G.table.sort
local UnitBuff = _G.UnitBuff
local UnitCanAttack = _G.UnitCanAttack
local UnitDebuff = _G.UnitDebuff
local UnitGUID = _G.UnitGUID
local UnitInParty = _G.UnitInParty
local UnitInRaid = _G.UnitInRaid
local UnitIsCorpse = _G.UnitIsCorpse
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsUnit = _G.UnitIsUnit
local wipe = _G.wipe
--GLOBALS>

local addonName, ns = ...
local ICON_SIZE = 16

local DEFAULT_CONFIG = {
	anchor = {}
}

local LibDispellable = LibStub('LibDispellable-1.0')

local SPELLS = {}
for id, cat in pairs(LibStub('DRData-1.0'):GetSpells()) do
	SPELLS[id] = cat
end

local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0', 'LibNameplateRegistry-1.0')

local baseFrame = CreateFrame("Frame")
local function NewFrameHeap(namePrefix)
	local proto = setmetatable({}, {__index = baseFrame})
	local meta = {__index = proto}
	local heap = {}
	local counter = 1
	function proto:Acquire(...)
		local self = next(heap)
		if not self then
			self = setmetatable(CreateFrame("Frame", namePrefix..counter), meta)
			counter = counter + 1
			if self.OnInitialize then
				self:OnInitialize()
			end
		else
			heap[self] = nil
		end
		if self.OnAcquire then
			self:OnAcquire(...)
		end
		return self
	end
	function proto:Release()
		if heap[self] then return end
		heap[self] = true
		self:Hide()
		self:SetParent(nil)
		self:ClearAllPoints()
		if self.OnRelease then
			self:OnRelease()
		end
	end
	return proto
end

-- Debug output
--@debug@
if AdiDebug then
	AdiDebug:Embed(addon, addonName)
else
	function addon.Debug() end
end
--@end-debug@

local auraProto = NewFrameHeap(addonName.."_Aura")
local unitProto = NewFrameHeap(addonName.."_Unit")
local unitFrames = {}

auraProto.Debug = addon.Debug
unitProto.Debug = addon.Debug

function addon:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New('AdiBuffPlateDB', {profile=DEFAULT_CONFIG})
end

function addon:OnEnable()
	self:Debug('Enabled')
	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('UNIT_TARGET')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	self:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	self:RegisterEvent('PLAYER_DEAD')
	self:LNR_RegisterCallback('LNR_ON_NEW_PLATE', 'NewPlate')
	self:LNR_RegisterCallback('LNR_ON_GUID_FOUND', 'PlateGUIDFound')
	self:LNR_RegisterCallback('LNR_ON_RECYCLE_PLATE', 'RecyclePlate')
end

function addon:OnDisable()
	self:LNR_UnregisterAllCallbacks()
	for guid, unitFrame in pairs(unitFrames) do
		unitFrame:Release()
	end
end

function addon:GetUnitFrameForGUID(guid, noSpawn)
	return guid and (unitFrames[guid] or (not noSpawn and unitProto:Acquire(guid)))
end

function addon:NewPlate(event, nameplate, data)
	if data.GUID then
		return self:PlateGUIDFound(event, nameplate, data.GUID)
	end
end

function addon:PlateGUIDFound(event, nameplate, guid)
	if unitFrames[guid] then
		unitFrames[guid]:SetNameplate(nameplate)
	end
end

function addon:RecyclePlate(event, nameplate, data)
	local unitFrame = data.GUID and unitFrames[data.GUID]
	if unitFrame and unitFrame.nameplate == nameplate then
		self:Debug('RecyclePlate', event, 'nameplate=', nameplate, 'GUID=', data.GUID, 'unitFrame=', unitFrame)
		unitFrame:SetNameplate(nil)
	end
end

function addon:AcceptAura(auraType, spellId, isMine, duration)
	if SPELLS[spellId] then
		return true, 2.5
	elseif auraType == 'BUFF' and LibDispellable:IsEnrageEffect(spellId) then
		return true, 2.5
	elseif isMine and duration > 5 and duration <= 300 then
		return true, 1
	else
		return false
	end
end

local function iterateAuras(unit, index)
	local name, rank, icon, count, dispelType, duration, expires, caster, isStealable, shouldConsolidate, spellID
	if index >= 0 then
		index = index + 1
		name, rank, icon, count, dispelType, duration, expires, caster, isStealable, shouldConsolidate, spellID = UnitDebuff(unit, index)
		if name then
			return index, "DEBUFF", name, rank, icon, count, dispelType, duration, expires, caster, isStealable, shouldConsolidate, spellID
		else
			index = 0
		end
	end
	index = index - 1
	name, rank, icon, count, dispelType, duration, expires, caster, isStealable, shouldConsolidate, spellID = UnitBuff(unit, -index)
	if name then
		return index, "BUFF", name, rank, icon, count, dispelType, duration, expires, caster, isStealable, shouldConsolidate, spellID
	end
end

local gen = 0
function addon:ScanUnit(event, unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	if UnitIsCorpse(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAttack("player", unit) then
		if unitFrames[guid] then
			unitFrames[guid]:Release()
		end
		return
	end
	self:Debug('Scanning', unit, 'on', event)
	local unitFrame
	gen = (gen + 1) % 10000
	for index, auraType, name, _, icon, count, _, duration, expireTime, caster, _, _, spellId in iterateAuras, unit, 0 do
		if not duration or duration == 0 then
			duration, expireTime = huge, huge
		end
		local isMine = (caster == "player" or caster == "pet" or caster == "vehicle")
		local accepted, scale = self:AcceptAura(auraType, spellId, isMine, duration)
		if accepted then
			unitFrame = unitFrame or addon:GetUnitFrameForGUID(guid)
			local aura = unitFrame:GetAura(spellId, auraType, icon)
			aura:SetDuration(expireTime-duration, duration)
			aura:SetCount(count)
			aura:SetScale(scale)
			aura.gen = gen
		end
	end
	if unitFrame then
		for spellId, aura in pairs(unitFrame.auras) do
			if aura.gen ~= gen then
				unitFrame:RemoveAura(spellId)
			end
		end
	elseif unitFrames[guid] then
		unitFrames[guid]:Release()
	end
end

function addon:UNIT_TARGET(event, unit)
	if unit ~= 'player' then
		return self:ScanUnit(event, (unit.."target"):gsub("(%d+)(target)$", "%2%1"))
	end
end

function addon:UNIT_AURA(event, unit)
	return self:ScanUnit(event, unit)
end

function addon:PLAYER_TARGET_CHANGED(event)
	return self:ScanUnit(event, "target")
end

function addon:PLAYER_FOCUS_CHANGED(event)
	return self:ScanUnit(event, "focus")
end

function addon:PLAYER_DEAD()
	for guid, unitFrame in pairs(unitFrames) do
		unitFrame:Release()
	end
end

local lastMouseoverScan = setmetatable({}, {__mode = 'kv'})
function addon:UPDATE_MOUSEOVER_UNIT(event)
	if UnitIsUnit('mouseover', 'target') or UnitIsUnit('mouseover', 'focus') or UnitInParty('mouseover') or UnitInRaid('mouseover') then
		return
	end
	local guid = UnitGUID('mouseover')
	if guid and GetTime() - (lastMouseoverScan[guid] or 0) > 0.5 then
		lastMouseoverScan[guid] = GetTime()
		return self:ScanUnit(event, "mouseover")
	end
end

local eventFilter = {
	UNIT_DIED = true,
	SPELL_AURA_APPLIED = true,
	SPELL_AURA_REMOVED = true,
	SPELL_AURA_APPLIED_DOSE = true,
	SPELL_AURA_REMOVED_DOSE = true,
	SPELL_AURA_REFRESH = true,
}
function addon:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellId, spellName, spellSchool, auraType, auraAmount)

	if not band(destFlags, COMBATLOG_OBJECT_REACTION_MASK) == COMBATLOG_OBJECT_REACTION_FRIENDLY or not eventFilter[event] then
		return
	end

	if event == 'SPELL_AURA_APPLIED' then
		local isMine = band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
		local accepted, scale = self:AcceptAura(auraType, spellId, isMine, huge)
		if accepted then
			local unitFrame = addon:GetUnitFrameForGUID(destGUID)
			local aura = unitFrame:GetAura(spellId, auraType)
			aura:SetCount(auraAmount)
			aura:SetScale(scale)
		end
		return
	end

	local unitFrame = addon:GetUnitFrameForGUID(destGUID, true)
	if not unitFrame then return end

	if event == 'UNIT_DIED' then
		lastMouseoverScan[destGUID] = nil
		self:Debug(destName, 'died according to combat log')
		unitFrame:Release()
		return
	end

	if not unitFrame:HasAura(spellId) then return end

	if event == 'SPELL_AURA_REMOVED' then
		unitFrame:RemoveAura(spellId)
	end

	local aura = unitFrame:GetAura(spellId, auraType)
	if event == 'SPELL_AURA_APPLIED_DOSE' or event == 'SPELL_AURA_REFRESH' then
		aura:SetDuration(GetTime(), aura.duration)
	end
	if event == 'SPELL_AURA_APPLIED_DOSE' or event == 'SPELL_AURA_REMOVED_DOSE' then
		aura:SetCount(auraAmount)
	end
end

-- Unit frame methods

function unitProto:OnInitialize()
	self.auras = {}
	self:SetSize(ICON_SIZE, ICON_SIZE)
	self:Hide()
	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)
end

function unitProto:OnAcquire(guid)
	unitFrames[guid] = self
	self.guid = guid
	self:SetNameplate(addon:GetPlateByGUID(guid))
end

function unitProto:OnRelease()
	self:SetNameplate(nil)
	unitFrames[self.guid] = nil
	for spell, aura in pairs(self.auras) do
		aura:Release()
	end
	wipe(self.auras)
end

function unitProto:OnShow()
	self:Debug('OnShow')
	self:Layout()
end

function unitProto:OnHide()
	self:Debug('OnHide')
	self:SetNameplate(nil)
end

function unitProto:HasAura(spellId)
	return self.auras[spellId] ~= nil
end

function unitProto:GetAura(spellId, auraType, icon)
	local aura = self.auras[spellId]
	if not aura then
		if not icon then
			icon = select(3, GetSpellInfo(spellId))
		end
		aura = auraProto:Acquire(self, spellId, icon, auraType)
		self.auras[spellId] = aura
		self:Layout()
	end
	return aura
end

function unitProto:RemoveAura(spellId)
	local aura = self.auras[spellId]
	if not aura then return end
	self.auras[spellId] = nil
	aura:Release()
	if next(self.auras) then
		self:Layout()
	else
		self:Release()
	end
end

function unitProto:SetNameplate(nameplate)
	if nameplate == self.nameplate then return end
	self:Debug('SetNameplate', nameplate)
	self.nameplate = nameplate
	self:SetParent(nameplate)
	if nameplate then
		self:SetPoint('TOPLEFT', nameplate, 'BOTTOMLEFT', 0, 0)
		self:SetPoint('TOPRIGHT', nameplate, 'BOTTOMRIGHT', 0, 0)
		self:Show()
	else
		self:ClearAllPoints()
		self:Hide()
	end
end

local function SortAuras(a, b)
	if a.scale == b.scale then
		if a.expireTime and b.expireTime then
			return a.expireTime < b.expireTime
		else
			return a.spell < b.spell
		end
	else
		return a.scale > b.scale
	end
end

function unitProto:Layout()
	self:SetScript('OnUpdate', self.DoLayout)
end

local tmp = {}
function unitProto:DoLayout()
	self:SetScript('OnUpdate', nil)
	if not self.nameplate then
		self:Debug('No attached to a nameplate, hiding')
		return self:Hide()
	elseif addon:GetPlateGUID(self.nameplate) ~= self.guid then
		self:Debug('GUID mismatch, hiding')
		return self:Hide()
	end
	self:Debug('Layout')

	wipe(tmp)
	for name, aura in pairs(self.auras) do
		tinsert(tmp, aura)
	end
	local height = 0
	tsort(tmp, SortAuras)
	local prevBuff, prevDebuff
	for i, aura in ipairs(tmp) do
		aura:ClearAllPoints()
		if aura.type == "DEBUFF" then
			if prevDebuff then
				aura:SetPoint("TOPLEFT", prevDebuff, "TOPRIGHT")
			else
				aura:SetPoint("TOPLEFT", self)
			end
			prevDebuff = aura
		else
			if prevBuff then
				aura:SetPoint("TOPRIGHT", prevBuff, "TOPLEFT")
			else
				aura:SetPoint("TOPRIGHT", self)
			end
			prevBuff = aura
		end
		height = max(height, aura:GetHeight())
	end
	self:SetHeight(height)
end

-- Aura frame methods

-- GLOBALS: GameFontNormal
local countdownFont, countdownSize = GameFontNormal:GetFont(), ceil(ICON_SIZE * 13 / 16)

function auraProto:OnInitialize()
	self.alpha = 1.0
	self.scale = 1.0

	self:SetSize(ICON_SIZE, ICON_SIZE)

	local texture = self:CreateTexture(nil, "OVERLAY")
	texture:SetPoint("TOPLEFT", self, "TOPLEFT")
	texture:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
	texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	texture:SetTexture(1,1,1,0)
	self.Texture = texture

	local countdown = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	countdown:SetPoint("CENTER")
	countdown:SetJustifyH("CENTER")
	countdown:SetJustifyV("MIDDLE")
	countdown:SetFont(countdownFont, countdownSize, "OUTLINE")
	countdown:SetShadowColor(0, 0, 0, 0.66)
	countdown:SetTextColor(1, 1, 0, 1)
	countdown:SetAlpha(1)
	self.Countdown = countdown

	local count = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	count:SetAllPoints(texture)
	count:SetJustifyH("RIGHT")
	count:SetJustifyV("BOTTOM")
	count:SetFont(GameFontNormal:GetFont(), ceil(ICON_SIZE * 10 / 16), "OUTLINE")
	count:SetShadowColor(0, 0, 0, 0.66)
	count:SetTextColor(1, 1, 1, 1)
	count:SetAlpha(1)
	self.Count = count
end

function auraProto:OnAcquire(unitFrame, spell, texture, type)
	self.spell = spell
	self.type = type
	self.unitFrame = unitFrame
	self:SetTexture(texture)
	self:SetParent(unitFrame)
	self:Show()
end

function auraProto:OnRelease()
	self:Hide()
	self:SetParent(nil)
	self:ClearAllPoints()
	self:SetParent(nil)
	self.unitFrame = nil
end

function auraProto:OnUpdate(elapsed)
	local now = GetTime()
	local timeLeft = self.expireTime - now
	if timeLeft <=0 then
		return self.unitFrame:RemoveAura(self)
	end
	local countdown = self.Countdown
	if timeLeft < self.flashTime or self.scale > 1.0 then
		local txt = tostring(ceil(timeLeft))
		if txt ~= countdown:GetText() then
			countdown:SetText(txt)
			countdown:SetFont(countdownFont, countdownSize, "OUTLINE")
			countdown:SetTextColor(1, timeLeft / self.flashTime, 0)
			countdown:Show()
			local scale = ICON_SIZE / max(countdown:GetStringWidth(), countdown:GetStringHeight())
			if scale < 1.0 then
				countdown:SetFont(countdownFont, floor(countdownSize * scale), "OUTLINE")
			end
		end
		if timeLeft < self.flashTime then
			local alpha = timeLeft % 1
			if alpha < 0.5 then
				alpha = 1 - alpha * 2
			else
				alpha = alpha * 2 - 1
			end
			self:SetAlpha(self.alpha * (0.2 + 0.8 * alpha))
		end
	elseif countdown:IsShown() then
		countdown:SetText("")
		countdown:Hide()
	end
end

function auraProto:SetTexture(path, ...)
	if path then
		self.Texture:SetTexture(path, ...)
		self.Texture:Show()
	else
		self.Texture:Hide()
	end
end

function auraProto:SetCount(count)
	count = tonumber(count) or 0
	if self.count ~= count then
		self.count = count
		if (count or 0) > 1 then
			self.Count:SetText(count)
			self.Count:Show()
		else
			self.Count:Hide()
		end
	end
end

function auraProto:SetScale(scale)
	scale = tonumber(scale) or 1
	if scale ~= self.scale then
		self.scale = scale
		self:SetSize(ICON_SIZE * scale, ICON_SIZE * scale)
		if self.unitFrame then
			self.unitFrame:Layout()
		end
	end
end

function auraProto:SetDuration(start, duration)
	start, duration = tonumber(start) or 0, tonumber(duration) or 0
	if self.start == start and self.duration == duration then return end
	self:SetAlpha(self.alpha)
	if start > 0 and duration > 0 and duration < huge then
		self.expireTime = start + duration
		self.flashTime = max(min(duration / 3, 6), 3)
		self.Countdown:Show()
		self:SetScript('OnUpdate', self.OnUpdate)
	else
		self.expireTime, self.flashTime = huge, huge
		self:SetScript('OnUpdate', nil)
		self.Countdown:Hide()
	end
	if self.unitFrame then
		self.unitFrame:Layout()
	end
end

--------------------------------------------------------------------------------
-- DRData does not know about snares, but we want them
--------------------------------------------------------------------------------

for i, id in pairs{
	  1604, -- Dazed (common),
	 45524, -- Chains of Ice (death knight)
	 50259, -- Dazed (feral charge effect)
	 58180, -- Infected Wounds (druid)
	 61391, -- Typhoon (druid)
	  5116, -- Concussive Shot (hunter)
	 13810, -- Ice Trap (hunter)
	 35101, -- Concussive Barrage (hunter, passive)
	 35346, -- Time Warp (hunter, warp Stalker)
	 50433, -- Ankle Crack (hunter, crocolisk)
	 54644, -- Frost Breath (hunter, chimaera)
	 61394, -- Frozen Wake (hunter, glyph)
	 31589, -- Slow (mage)
	 44614, -- Frostfire Bolt (mage)
	   116, -- Frostbolt (mage)
	   120, -- Cone of Cold (mage)
	  6136, -- Chilled (mage)
	  7321, -- Chilled (mage, bis)
	 11113, -- Blast Wave (mage)
	116095, -- Disable (monk, 1 stack)
	  1044, -- Hand of Freedom (paladin)
	  3409, -- Crippling Poison (rogue)
	 26679, -- Deadly Throw (rogue)
	  3600, -- Earthbind (shaman)
	  8034, -- Frostbrand Attack (shaman)
	  8056, -- Frost Shock (shaman)
	  8178, -- Grounding Totem Effect (shaman)
	 18223, -- Curse of Exhaustion (warlock)
	 17962, -- Conflagrate (warlock)
	  1715, -- Piercing Howl (warrior)
	 12323  -- Hamstring (warrior)
} do
	SPELLS[id] = "snare"
end

--------------------------------------------------------------------------------
-- Interesting player buffs
--------------------------------------------------------------------------------

for i, id in pairs{
	-- DEATHKNIGHT:
	49222, -- Bone Shield
	55233, -- Vampiric Blood
	48707, -- Anti-Magic Shell
	49028, -- Dancing Rune Weapon
	48792, -- Icebound Fortitude
	-- DRUID:
	29166, -- Innervate
	22842, -- Frenzied Regeneration
	22812, -- Barkskin
	61336, -- Survival Instincts
	-- HUNTER:
	 5384, -- Feign Death
	19263, -- Deterrence
	-- MAGE:
	45438, -- Ice Block
	-- PALADIN:
	54428, -- Divine Plea
	  498, -- Divine Protection
	 6940, -- Hand of Sacrifice
	31850, -- Ardent Defender
	86657, -- Ancient Guardian (prot)
	 1022, -- Hand of Protection
	  642, -- Divine Shield
	-- PRIEST:
	64901, -- Hymn of Hope
	33206, -- Pain Suppression
	47788, -- Guardian Spirit
	-- ROGUE:
	 5277, -- Evasion
	31224, -- Cloak of Shadows
	-- WARLOCK:
	 7812, -- Sacrifice
	-- WARRIOR:
	 2565, -- Shield Block
	55694, -- Enraged Regeneration
	  871, -- Shield Wall
	12975, -- Last Stand
} do
	SPELLS[id] = "buff"
end

