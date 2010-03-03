--[[
ShowDoTs -- Display Damage over Time debuffs
Copyright 2010 Adirelle
All rights reserved.
--]]

local addonName, ns = ...

local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0')

local function NewFrameHeap(namePrefix, frameType, parent, template)
	--local baseFrame = CreateFrame(frameType, nil, parent, template)
	--local proto = setmetatable({}, {__index = getmetatable(baseFrame).__index})
	local proto = {}
	local heap = {}
	local counter = 1
	function proto:Acquire(...)
		local self = next(heap)
		if not self then
			self = CreateFrame(frameType, namePrefix..counter, parent, template)
			for k,v in pairs(proto) do
				self[k] = v
			end
			--self = setmetatable(CreateFrame(frameType, namePrefix..counter, parent, template), meta)
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
		self:UnregisterAllEvents()
		self:SetParent(nil)
		heap[self] = true
	end
	return proto
end

local auraProto = NewFrameHeap(addonName.."_Aura", "Frame")
local unitProto = NewFrameHeap(addonName.."_Unit","Frame")
local unitFrames = {}

function addon:OnEnable()
	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
end

function addon:OnDisable()
	for guid, uf in pairs(unitFrames) do
		uf:Release()
	end
end

function addon:ScanUnit(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	local unitFrame = unitFrames[guid]
	if UnitIsCorpse(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAttack("player", unit) then
		if unitFrame then
			unitFrame:Release()
		end
		return
	end
end

function addon:UNIT_AURA(event, unit)
	return self:ScanUnit(unit)
end

function addon:PLAYER_TARGET_CHANGED(event)
	return self:ScanUnit("target")
end

function addon:PLAYER_FOCUS_CHANGED(event)
	return self:ScanUnit("focus")
end

function addon:COMBAT_LOG_EVENT_UNFILTERED(event)
end

-- Unit frame methods

function unitProto:OnInitialize()
	self.auras = {}
end

function unitProto:OnAcquire(guid, unit)
	self.guid = guid
	units[guid] = self
	self:Show()
end

function unitProto:OnRelease()
	units[self.guid] = nil
	for spell, aura in pairs(self.auras) do
		aura:Release()
	end
end

-- Aura frame methods

local borderBackdrop = {
	edgeFile = [[Interface\Addons\WTFIH\white16x16]], edgeSize = 1,
	insets = {left = 0, right = 0, top = 0, bottom = 0},
}

function auraProto:OnInitialize()
	self:SetWidth(32)
	self:SetHeight(32)
	self:SetBackdrop(borderBackdrop)
	self:SetBackdropColor(0, 0, 0, 0)
	self:SetBackdropBorderColor(1, 1, 1, 1)

	local texture = self:CreateTexture(nil, "OVERLAY")
	texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
	texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
	texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	texture:SetTexture(1,1,1,0)
	self.Texture = texture

	local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
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

function auraProto:OnAcquire(unitFrame, spell, texture, start, duration, count)
	self.spell = spell
	self:SetTexture(texture)
	self:SetParent(unitFrame)
	self.unitFrame = unitFrame
	self:Update(start, duration, count)
	self:Show()
end

function auraProto:OnRelease()
	self.unitFrame.auras[self.spell] = nil
	self.unitFrame = nil
end

function auraProto:Update(start, duration, count)
	self.start, self.duration, self.count = start, duration, count
	self:SetDuration(start, duration)
	self:SetCount(count)
end

function auraProto:OnUpdate(elapsed)
	local now = GetTime()
	local timeLeft = self.expireTime - now
	if timeLeft <=0 then
		self:Hide()
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

function auraProto:SetBorderColor(r, g, b)
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if r and g and b then
		self:SetBackdropBorderColor(r, g, b, 1)
	else
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end
end

