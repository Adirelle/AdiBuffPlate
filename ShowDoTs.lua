--[[
ShowDoTs -- Display Damage over Time debuffs
Copyright 2010 Adirelle
All rights reserved.
--]]

local addonName, ns = ...

local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0')

local function NewFrameHeap(namePrefix, frameType, parent, template)
	local baseFrame = CreateFrame(frameType, nil, parent, template)
	local proto = setmetatable({}, {__index = getmetatable(baseFrame).__index})
	local meta = {__index = proto}
	local heap = {}
	local counter = 1
	function proto:Acquire(...)
		local self = next(heap)
		if not self then
			self = setmetatable(CreateFrame(frameType, namePrefix..counter, parent, template), meta)
			counter = counter + 1
		else
			heap[self] = nil
		end
		self:Initialize(...)
		return self
	end
	function proto:Release()
		self:Hide()
		self:UnregisterAllEvents()
		heap[self] = true
	end
	return proto
end

local auraProto = newFrameHeap(addonName.."_Aura", "Frame", UIParent)
local unitProto = newFrameHeap(addonName.."_Unit","Frame", UIParent)
local units = {}

function addon:OnEnable()
	self:RegisterEvent('UNIT_AURA')
	self:RegisterEvent('PLAYER_TARGET_CHANGED')
	self:RegisterEvent('PLAYER_FOCUS_CHANGED')
elf:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
end

function addon:OnDisable()
end

function addon:ScanUnit(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	local uf = units[guid]
	if UnitIsCorpse(unit) or UnitIsDeadOrGhost(unit) or not UnitCanAttack("player", unit) then
		if uf then
			uf:Release()
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

