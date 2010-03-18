--[[
ShowDoTs -- Display Damage over Time debuffs
Copyright 2010 Adirelle
All rights reserved.
--]]

local addonName, ns = ...
local ICON_SIZE = 16

local AURAS = {
	WARLOCK = {
		(GetSpellInfo(172)), -- Corruption
		(GetSpellInfo(48181)), -- Haunt
		(GetSpellInfo(30108)), -- Unstable Afflication
		(GetSpellInfo(980)), -- Curse of Agony
		(GetSpellInfo(27243)), -- Seed of Corruption
		(GetSpellInfo(348)), -- Immolate
		(GetSpellInfo(5782)), -- Fear
		(GetSpellInfo(49892)), -- Death Coil
		(GetSpellInfo(5484)), -- Howl of Terror
	},
	DRUID = {
		(GetSpellInfo(8921)), -- Moonfire
		(GetSpellInfo(24974)), -- Insect Swarm
		(GetSpellInfo(33745)), -- Lacerate
	},
}

local DEFAULT_CONFIG = {
	anchor = {}
}

local LibNameplate = LibStub('LibNameplate-1.0')

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
if tekDebug then
	local debugFrame = tekDebug:GetFrame(addonName)
	function addon:Debug(...)
		debugFrame:AddMessage('|cffff8800['..tostring(self)..']|r '..strjoin(" ", tostringall(...)):gsub("= ", "="))
	end
else
	function addon.Debug() end
end

local auraProto = NewFrameHeap(addonName.."_Aura", "Frame")
local unitProto = NewFrameHeap(addonName.."_Unit","Frame")
local unitFrames = {}

auraProto.Debug = addon.Debug
unitProto.Debug = addon.Debug

function addon:OnInitialize()
	local _, class = UnitClass('player')
	AURAS = AURAS[class]
	if not AURAS then
		self:Debug('Not aura to watch, disabling')
		return self:Disable()
	end
	self:Debug('Watched auras:', unpack(AURAS))
	
	self.db = LibStub('AceDB-3.0'):New('ShowDoTsDB', {profile=DEFAULT_CONFIG})
end

function addon:OnEnable()
	self:Debug('Enabled')
	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('UNIT_TARGET')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
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
	local unitFrame = unitFrames[guid or ""]
	if unitFrame then
		unitFrame:AttachToNameplate(nameplate)
	end
end

function addon:LibNameplate_RecycleNameplate(event, nameplate)
	local unitFrame = unitFrames[LibNameplate:GetGUID(nameplate) or ""]
	if unitFrame then
		unitFrame:DetachFromNameplate(nameplate)
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
	for i, name in ipairs(AURAS) do
		local found, _, icon, count, _, duration, expireTime, caster = UnitDebuff(unit, name)
		if found and caster == "player" and (tonumber(duration) or 0) > 0 then
			auraCount = auraCount + 1
			toDelete[name] = nil
			if not unitFrame then
				self:Debug('Acquiring unit frame for', guid, 'unit=', unit)
				unitFrame = unitProto:Acquire(guid, unit)
				updated = true
			end
			local auraFrame = unitFrame.auras[name]
			if not auraFrame then
				self:Debug('Acquiring aura frame for', name, 'icon=', icon)
				auraFrame = auraProto:Acquire(unitFrame, name, icon)
			end
			self:Debug(unit, name, duration, expireTime, count)
			updated = auraFrame:Update(expireTime-duration, duration, count) or updated
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

local strmatch, band = string.match, bit.band
function addon:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType, auraAmount)
	local unitFrame = destGUID and unitFrames[destGUID]
	if not unitFrame then return end
	if event == 'UNIT_DIED' then
		self:Debug(destName, 'died according to combat log')
		unitFrame:Release()
		return
	end
	local aura = spellName and unitFrame.auras[spellName]
	if not aura then return end
	self:Debug(event, 'source=', sourceName, 'target=', destName, 'spell=', spellName)
	local updated
	if event == 'SPELL_AURA_REMOVED' then
		aura:Release()
		updated = true
	elseif event == 'SPELL_AURA_APPLIED_DOSE' then
		updated = aura:Update(GetTime(), aura.duration, auraAmount)
	elseif event == 'SPELL_AURA_REMOVED_DOSE' then
		updated = aura:Update(aura.start, aura.duration, auraAmount)
	elseif event == 'SPELL_AURA_REFRESH' then
		updated = aura:Update(GetTime(), aura.duration, aura.count)
	else
		return
	end
	if updated then
		unitFrame:Layout()
	end
end

-- Unit frame methods

function unitProto:OnInitialize()
	self.auras = {}
	self:SetWidth(ICON_SIZE)
	self:SetHeight(ICON_SIZE)
end

function unitProto:OnAcquire(guid, unit)
	unitFrames[guid] = self
	self.guid = guid
	self.nameplate = nil
	local nameplate = LibNameplate:GetNameplateByGUID(guid)
	if nameplate then
		self:AttachToNameplate(nameplate)
	end
end

function unitProto:AttachToNameplate(nameplate)
	if nameplate ~= self.nameplate then
		self.nameplate = nameplate
		self:SetParent(nameplate)
		self:SetPoint('LEFT', nameplate, 'RIGHT', 0, -8)
		self:Show()
		self:Layout()
	end
end

function unitProto:DetachFromNameplate(nameplate)
	if nameplate == self.nameplate then
		self.nameplate = nil
		self:SetParent(nil)
		self:Hide()
	end
end

function unitProto:OnRelease()
	self.nameplate = nil
	unitFrames[self.guid] = nil
	for spell, aura in pairs(self.auras) do
		aura:Release()
	end
end

local function SortAuras(a, b)
	return a:GetTimeLeft() > b:GetTimeLeft()
end

local tmp = {}
function unitProto:Layout()
	if self:IsShown() then
		for _, aura in pairs(self.auras) do
			tinsert(tmp, aura)
		end
		self:SetWidth(ICON_SIZE * #tmp)
		self:SetHeight(ICON_SIZE)
		table.sort(tmp, SortAuras)
		for i, aura in ipairs(tmp) do
			aura:SetPoint("BOTTOMLEFT", ICON_SIZE * (i-1), 0)
		end
		wipe(tmp)
	end
end

-- Aura frame methods

local countdownFont, countdownSize = GameFontNormal:GetFont(), math.ceil(ICON_SIZE * 13 / 16)

function auraProto:OnInitialize()
	self.alpha = 1.0
	
	self:SetWidth(ICON_SIZE)
	self:SetHeight(ICON_SIZE)

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
	count:SetFont(GameFontNormal:GetFont(), math.ceil(ICON_SIZE * 10 / 16), "OUTLINE")
	count:SetShadowColor(0, 0, 0, 0.66)
	count:SetTextColor(1, 1, 1, 1)
	count:SetAlpha(1)
	self.Count = count
end

function auraProto:OnAcquire(unitFrame, spell, texture)
	self.spell = spell
	self.unitFrame = unitFrame
	self:SetTexture(texture)
	self:SetParent(unitFrame)
	unitFrame.auras[spell] = self
	self:Show()
end

function auraProto:OnRelease()
	self.unitFrame.auras[self.spell] = nil
	self.unitFrame = nil
end

function auraProto:Update(start, duration, count)
	if self.start ~= start or self.duration ~= duration or self.count ~= count then
		self.start, self.duration, self.count = start, duration, count
		self:SetDuration(start, duration)
		self:SetCount(count)
		return true
	end
end

function auraProto:GetTimeLeft()
	return self.expireTime and (self.expireTime - GetTime()) or 0
end

local ceil, max, floor = math.ceil, math.max, math.floor
function auraProto:OnUpdate(elapsed)
	local now = GetTime()
	local timeLeft = self.expireTime - now
	if timeLeft <=0 then
		return self:Release()
	end
	local countdown = self.Countdown
	if timeLeft < self.flashTime then
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
		local alpha = timeLeft % 1
		if alpha < 0.5 then
			alpha = 1 - alpha * 2
		else
			alpha = alpha * 2 - 1
		end
		self:SetAlpha(self.alpha * (0.2 + 0.8 * alpha))
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

function auraProto:SetDuration(start, duration)
	self:SetAlpha(self.alpha)
	start, duration = tonumber(start), tonumber(duration)
	if start and duration then
		self.expireTime = start + duration
		self.flashTime = math.max(math.min(duration / 3, 6), 3)
		self.Countdown:Show()
		self:SetScript('OnUpdate', self.OnUpdate)
	else
		self.expireTime, self.flashTime = nil, nil
		self:SetScript('OnUpdate', nil)
		self.Countdown:Hide()
	end
end
