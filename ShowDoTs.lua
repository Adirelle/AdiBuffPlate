--[[
ShowDoTs -- Display Damage over Time debuffs
Copyright 2010 Adirelle
All rights reserved.
--]]

local addonName, ns = ...

local ICON_SIZE = 24

local AURAS = {
	WARLOCK = {
		(GetSpellInfo(172)), -- Corruption
		(GetSpellInfo(980)), -- Curse of Agony
		(GetSpellInfo(348)), -- Immolate
		(GetSpellInfo(27243)), -- Seed of Corruption
		(GetSpellInfo(30108)), -- Unstable Afflication
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
local NUM_SLOTS = 5
local unitSlots = {}
local anchor

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
	
	self.db = LibStub('AceDB-3.0'):NewDatabase('ShowDoTsDB', {profile=DEFAULT_CONFIG})

	anchor = CreateFrame("Frame", addonName..'Anchor', UIParent)
	anchor:SetWidth((1+#AURAS)*ICON_SIZE)
	anchor:SetHeight(NUM_SLOTS*ICON_SIZE)
	anchor:SetPoint("BOTTOMLEFT", 100, 500)
	anchor:Hide()	

	local libmovable = LibStub('LibMovable-1.0', true)
	if libmovable then
		libmovable.RegisterMovable(self, anchor, self.db.profile.anchor)
	end
end

function addon:OnEnable()
	self:Debug('Enabled')
	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('UNIT_TARGET')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
end

function addon:OnDisable()
	for guid, unitFrame in pairs(unitFrames) do
		unitFrame:Release()
	end
end

local function GetFreeSlot()
	for slot = 1, NUM_SLOTS do
		if not unitSlots[slot] then
			return slot
		end
	end
end

local currentTargetGUID
local toDelete = {}
function addon:ScanUnit(event, unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	if unit == 'target' and guid ~= currentTargetGUID then
		currentTargetGUID = guid
		for guid, unitFrame in pairs(unitFrames) do
			unitFrame:UpdateBorder()
		end
	end
	if UnitIsCorpse(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAttack("player", unit) then
		if unitFrames[guid] then
			unitFrames[guid]:Release()
			self:Layout()
		end
		return
	end
	self:Debug('Scanning', unit, 'on', event)
	local unitFrame = unitFrames[guid]
	local freeSlot
	if unitFrame then
		for spell, aura in pairs(unitFrame.auras) do
			toDelete[spell] = aura
		end
	else
		freeSlot = GetFreeSlot()
		if not freeSlot then
			return self:Debug('No free slot')
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
				self:Debug('Acquiring unit frame for', guid, 'unit=', unit, 'slot=', freeSlot)
				unitFrame = unitProto:Acquire(guid, unit, freeSlot)
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
			self:Layout()
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
			unitFrame:Show()
			self:Layout()
		end
	end
end

function addon:Layout()
	for slot, unitFrame in ipairs(unitSlots) do
		unitFrame:SetPoint("BOTTOMLEFT", anchor, 0, slot * ICON_SIZE)
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
		self:Layout()
		return
	elseif not strmatch(event, '_AURA_') or band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) == 0 then
		return self:Debug('Ignoring', event, sourceName)
	end
	local aura = spellName and unitFrame.auras[spellName]
	if not aura then return end
	self:Debug(event, 'source=', sourceName, 'target=', destName, 'spell=', spellName)
	if event == 'SPELL_AURA_REMOVED' then
		aura:Release()
		unitFrame:Layout()
	elseif event == 'SPELL_AURA_APPLIED_DOSE' then
		aura:Update(GetTime(), aura.duration, auraAmount)
	elseif event == 'SPELL_AURA_REMOVED_DOSE' then
		aura:Update(aura.start, aura.duration, auraAmount)
	elseif event == 'SPELL_AURA_REFRESH' then
		aura:Update(GetTime(), aura.duration, aura.count)
	end
end

-- Unit frame methods

local unitBackdrop = {
	bgFile = [[Interface\Addons\WTFIH\white16x16]],	tile = true, tileSize = 16,
	edgeFile = [[Interface\Addons\WTFIH\white16x16]], edgeSize = 1,
	insets = {left = 0, right = 0, top = 0, bottom = 0},
}

function unitProto:OnInitialize()
	self.auras = {}
	
	self:SetWidth(ICON_SIZE)
	self:SetHeight(ICON_SIZE)
	
	self:SetBackdrop(unitBackdrop)
	self:SetBackdropColor(0, 0, 0, 1)
	self:SetBackdropBorderColor(0, 0, 0, 0)
	
	local portrait = self:CreateTexture(nil, "OVERLAY")	
	portrait:SetPoint('TOPLEFT', 1, -1)
	portrait:SetPoint('BOTTOMRIGHT', -1, 1)
	self.Portrait = portrait
end

function unitProto:OnAcquire(guid, unit, slot)
	SetPortraitTexture(self.Portrait, unit)
	self.guid = guid
	self.slot = slot
	unitFrames[guid] = self
	unitSlots[slot] = self
	self:UpdateBorder()
	self:Show()
end

function unitProto:OnRelease()
	unitSlots[self.slot] = nil
	unitFrames[self.guid] = nil
	for spell, aura in pairs(self.auras) do
		aura:Release()
	end
end

function unitProto:UpdateBorder()
	if self.guid == UnitGUID('target') then
		self:SetBackdropBorderColor(1, 1, 1, 1)
	else
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end
end

function unitProto:Layout()
	for i, name in ipairs(AURAS) do
		local aura = self.auras[name]
		if aura then
			aura:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", ICON_SIZE * (i-1), 0)
		end
	end
end

-- Aura frame methods

--local borderBackdrop = {
--	edgeFile = [[Interface\Addons\WTFIH\white16x16]], edgeSize = 1,
--	insets = {left = 0, right = 0, top = 0, bottom = 0},
--}

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

	local cooldown = CreateFrame("Cooldown", nil, self, "CooldownFrameTemplate")
	cooldown:SetAllPoints(texture)
	cooldown:SetDrawEdge(true)
	cooldown:SetReverse(true)
	self.Cooldown = cooldown

	local count = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	count:SetAllPoints(texture)
	count:SetJustifyH("RIGHT")
	count:SetJustifyV("BOTTOM")
	count:SetFont(GameFontNormal:GetFont(), 13, "OUTLINE")
	count:SetShadowColor(0, 0, 0, 0)
	count:SetTextColor(1, 1, 1, 1)
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

function auraProto:OnUpdate(elapsed)
	local now = GetTime()
	local timeLeft = self.expireTime - now
	if timeLeft <=0 then
		self:Release()
	elseif timeLeft < self.flashTime then
		local alpha = now % 1
		if alpha < 0.5 then
			alpha = alpha * 2
		else
			alpha = (1 - alpha) * 2
		end
		self:SetAlpha(self.alpha * alpha)
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
		self.flashTime = math.min(duration / 3, 3)
		self:SetScript('OnUpdate', self.OnUpdate)
		self.Cooldown:SetCooldown(start, duration)
		self.Cooldown:Show()
	else
		self:SetScript('OnUpdate', nil)
		self.Cooldown:Hide()
	end
end
