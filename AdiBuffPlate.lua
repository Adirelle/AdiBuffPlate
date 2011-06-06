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

local LibNameplate = LibStub('LibNameplate-1.0')

local SPELLS = {}
for id, cat in pairs(LibStub('DRData-1.0'):GetSpells()) do
	SPELLS[id] = cat
end

local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0')

local function NewFrameHeap(namePrefix, frameType, parent, template)
	--local baseFrame = CreateFrame(frameType, nil, parent, template)
	--local proto = setmetatable({}, {__index = getmetatable(baseFrame).__index})
	--local meta = {__index = proto}
	local proto = {}
	local heap = {}
	local counter = 1
	function proto:Acquire(...)
		local self = next(heap)
		if not self then
			--self = setmetatable(CreateFrame(frameType, namePrefix..counter, parent, template), meta)
			self = CreateFrame(frameType, namePrefix..counter, parent, template)
			for k,v in pairs(proto) do
				self[k] = v
			end
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
		if self.OnRelease then
			self:OnRelease()
		end
		self:Hide()
		self:SetParent(nil)
		heap[self] = true
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

local auraProto = NewFrameHeap(addonName.."_Aura", "Frame")
local unitProto = NewFrameHeap(addonName.."_Unit","Frame")
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
	LibNameplate.RegisterCallback(self, 'LibNameplate_FoundGUID')
	LibNameplate.RegisterCallback(self, 'LibNameplate_RecycleNameplate')
end

function addon:OnDisable()
	LibNameplate.UnregisterAllcallbacks(self)
	for guid, unitFrame in pairs(unitFrames) do
		unitFrame:Release()
	end
end

function addon:LibNameplate_FoundGUID(event, nameplate, guid)
	local unitFrame = guid and unitFrames[guid]
	if unitFrame then
		unitFrame:AttachToNameplate(nameplate)
	end
end

function addon:LibNameplate_RecycleNameplate(event, nameplate)
	local guid = LibNameplate:GetGUID(nameplate)
	local unitFrame = guid and unitFrames[guid]
	if unitFrame then
		unitFrame:DetachFromNameplate(nameplate)
	end
end

function addon:AcceptAura(auraType, spellId, isMine, duration)
	if SPELLS[spellId] then
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

local toDelete = {}
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
	local unitFrame = unitFrames[guid]
	if unitFrame then
		for spell, aura in pairs(unitFrame.auras) do
			toDelete[spell] = aura
		end
	end
	local auraCount = 0
	local updated = false
	for index, auraType, name, _, icon, count, _, duration, expireTime, caster, _, _, spellId in iterateAuras, unit, 0 do
		if not duration or duration == 0 then
			duration, expireTime = huge, huge
		end
		local isMine = (caster == "player" or caster == "pet" or caster == "vehicle")
		local accepted, scale = self:AcceptAura(auraType, spellId, isMine, duration)
		if accepted then
			auraCount = auraCount + 1
			toDelete[name] = nil
			if not unitFrame then
				self:Debug('Acquiring unit frame for', guid, 'unit=', unit)
				unitFrame = unitProto:Acquire(guid)
				updated = true
			end
			local auraFrame = unitFrame.auras[name]
			if not auraFrame then
				self:Debug('Acquiring aura frame for', name, 'icon=', icon, 'type=', auraType)
				auraFrame = auraProto:Acquire(unitFrame, name, icon, auraType)
			end
			self:Debug(unit, name, duration, expireTime, count)
			if auraFrame:Update(expireTime-duration, duration, count, scale) then
				updated = true
			end
			auraFrame:Show()
		end
	end
	self:Debug('Scanned unit', unit, 'guid=', guid, 'auraCount=', auraCount)
	if auraCount == 0 then
		if unitFrame then
			wipe(toDelete)
			unitFrame:Release()
		end
	elseif unitFrame then
		if next(toDelete) then
			for spell, aura in pairs(toDelete) do
				aura:Release()
				updated = true
			end
			wipe(toDelete)
		end
		if updated then
			unitFrame:Layout()
		end
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

function addon:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, _, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType, auraAmount)

	local unitFrame = destGUID and unitFrames[destGUID]

	if event == 'SPELL_AURA_APPLIED' then
		local isMine = band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
		local accepted, scale = self:AcceptAura(auraType, spellId, isMine, huge)
		if accepted then
			if not unitFrame then
				unitFrame = unitProto:Acquire(destGUID)
			end
			local aura = unitFrame.auras[spellName]
			if not aura then
				local _, _, icon = GetSpellInfo(spellId)
				aura = auraProto:Acquire(unitFrame, spellName, icon, auraType)
				aura:Show()
			end
			if aura:Update(GetTime(), nil, auraAmount, scale) then
				unitFrame:Layout()
			end
		end
		return
	end

	if not unitFrame then return end

	if event == 'UNIT_DIED' then
		lastMouseoverScan[destGUID] = nil
		self:Debug(destName, 'died according to combat log')
		unitFrame:Release()
		return
	end

	local aura = spellName and unitFrame.auras[spellName]
	if not aura then return end
	self:Debug(event, 'source=', sourceName, 'target=', destName, 'spell=', spellName)
	if event == 'SPELL_AURA_REMOVED' then
		aura:Release()
		unitFrame:Layout()
	elseif event == 'SPELL_AURA_APPLIED_DOSE' then
		if aura:Update(GetTime(), aura.duration, auraAmount) then
			unitFrame:Layout()
		end
	elseif event == 'SPELL_AURA_REMOVED_DOSE' then
		if aura:Update(aura.start, aura.duration, auraAmount) then
			unitFrame:Layout()
		end
	elseif event == 'SPELL_AURA_REFRESH' then
		if aura:Update(GetTime(), aura.duration, aura.count) then
			unitFrame:Layout()
		end
	end
end

-- Unit frame methods

function unitProto:OnInitialize()
	self.auras = {}
	self:SetWidth(ICON_SIZE)
	self:SetHeight(ICON_SIZE)
end

function unitProto:OnAcquire(guid)
	unitFrames[guid] = self
	self.guid = guid
	self.nameplate = nil
	self:AttachToNameplate(LibNameplate:GetNameplateByGUID(guid))
end

function unitProto:OnRelease()
	self:DetachFromNameplate(self.nameplate)
	unitFrames[self.guid] = nil
	for spell, aura in pairs(self.auras) do
		aura:Release()
	end
end

function unitProto:AttachToNameplate(nameplate)
	if nameplate and nameplate ~= self.nameplate then
		self.nameplate = nameplate
		self:SetParent(nameplate)
		self:SetPoint('TOPLEFT', nameplate, 'BOTTOMLEFT', 0, 0)
		self:SetPoint('TOPRIGHT', nameplate, 'BOTTOMRIGHT', 0, 0)
		self:Show()
		self:Layout()
	end
end

function unitProto:DetachFromNameplate(nameplate)
	if self.nameplate and nameplate == self.nameplate then
		self.nameplate = nil
		self:SetParent(nil)
		self:ClearAllPoints()
		self:Hide()
	end
end

local function SortAuras(a, b)
	if a.scale == b.scale then
		return a:GetTimeLeft() > b:GetTimeLeft()
	else
		return b.scale > a.scale
	end
end

local tmp = {}
function unitProto:Layout()
	if self:IsShown() then
		for _, aura in pairs(self.auras) do
			tinsert(tmp, aura)
		end
		local left, right, height = 0, 0, 0
		tsort(tmp, SortAuras)
		for i, aura in ipairs(tmp) do
			local w, h = aura:GetSize()
			if aura.type == "DEBUFF" then
				aura:SetPoint("TOPLEFT", left, 0)
				left = left + w
			else
				aura:SetPoint("TOPRIGHT", -right, 0)
				right = right + w
			end
			if h > height then
				height = h
			end
		end
		self:SetHeight(height)
		wipe(tmp)
	end
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
	unitFrame.auras[spell] = self
	self:Show()
end

function auraProto:OnRelease()
	self:Hide()
	self:ClearAllPoints()
	self.unitFrame.auras[self.spell] = nil
	self.unitFrame = nil
end

function auraProto:Update(start, duration, count, scale)
	if self.start ~= start or self.duration ~= duration or self.count ~= count or self.scale ~= scale then
		self.start, self.duration, self.count = start, duration, count
		self:SetDuration(start, duration)
		self:SetCount(count)
		self:SetScale(scale)
		return true
	end
end

function auraProto:GetTimeLeft()
	return self.expireTime and (self.expireTime - GetTime()) or huge
end

function auraProto:OnUpdate(elapsed)
	local now = GetTime()
	local timeLeft = self.expireTime - now
	if timeLeft <=0 then
		return self:Release()
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
	if count > 1 then
		self.Count:SetText(count)
		self.Count:Show()
	else
		self.Count:Hide()
	end
end

function auraProto:SetScale(scale)
	scale = tonumber(scale) or 1
	if scale ~= self.scale then
		self.scale = scale
		self:SetSize(ICON_SIZE * scale, ICON_SIZE * scale)
	end
end

function auraProto:SetDuration(start, duration)
	self:SetAlpha(self.alpha)
	start, duration = tonumber(start), tonumber(duration)
	if start and duration then
		self.expireTime = start + duration
		self.flashTime = max(min(duration / 3, 6), 3)
		self.Countdown:Show()
		self:SetScript('OnUpdate', self.OnUpdate)
	else
		self.expireTime, self.flashTime = nil, nil
		self:SetScript('OnUpdate', nil)
		self.Countdown:Hide()
	end
end

--------------------------------------------------------------------------------
-- DRData does not know about snares, but we want them
--------------------------------------------------------------------------------

for i, id in pairs{
	 1604, -- Dazed
	45524, -- Chains of Ice
	50434, -- Chilblains
	58617, -- Glyph of Heart Strike
	68766, -- Desecration
	50259, -- Dazed (feral charge effect)
	58180, -- Infected Wounds
	61391, -- Typhoon
	31589, -- Slow
	44614, -- Frostfire Bolt
	 2974, -- Wing Clip
	 5116, -- Concussive Shot
	13810, -- Ice Trap
	35101, -- Concussive Barrage
	35346, -- Time Warp (Warp Stalker)
	50433, -- Ankle Crack (Crocolisk)
	54644, -- Frost Breath (Chimaera)
	61394, -- Frozen Wake (glyph)
	  116, -- Frostbolt
	  120, -- Cone of Cold
	 6136, -- Chilled
	 7321, -- Chilled (bis)
	11113, -- Blast Wave
	 3409, -- Crippling Poison
	26679, -- Deadly Throw
	31126, -- Blade Twisting
	51693, -- Waylay
	51585, -- Blade Twisting
	 3600, -- Earthbind
	 8034, -- Frostbrand Attack
	 8056, -- Frost Shock
	 8178, -- Grounding Totem Effect
	18118, -- Aftermath
	18223, -- Curse of Exhaustion
	 1715, -- Piercing Howl
	12323  -- Hamstring
} do
	SPELLS[id] = "snare"
end

