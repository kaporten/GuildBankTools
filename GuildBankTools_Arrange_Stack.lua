--[[
	Arrange:Stack module.
--]]

local Stack = {}
local GBT = Apollo.GetAddon("GuildBankTools")

function Stack:Initialize()
	GB = Apollo.GetAddon("GuildBank")
	self.Controller = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
end

function Stack:SetSettings(tSettings)
	-- Not used
	self.tSettings = tSettings
end

function Stack:HasPendingOperations()	
	return self:GetPendingOperationCount() > 0
end

function Stack:GetPendingOperationCount()
	if self.tStackable == nil then
		return 0
	end
	
	return #self.tStackable
end

-- Scans current guild bank tab, returns list containing list of stackable slots
function Stack:DeterminePendingOperations()
	--Print("Stack:DeterminePendingOperations")
	-- Identify all stackable slots in the current tab, and add to tStackableItems
	-- This includes stackables with just 1 stack (ie. nothing to stack with)
	-- tStackableItems is a table with key=itemId, value=list of slots containing this itemId
	local tStackableItems = {}
	for _,tSlot in ipairs(GBT:GetBankTab()) do
		if tSlot ~= nil and self:IsItemStackable(tSlot.itemInSlot) then
			local nItemId = tSlot.itemInSlot:GetItemId()
			
			-- Add current tSlot to tSlots-list containing all slots for this itemId
			local tSlots = tStackableItems[nItemId] or {}
			tSlots[#tSlots+1] = tSlot
			
			-- Add slot details to list of stackable items
			tStackableItems[nItemId] = tSlots
		end
	end
	
	-- Go through tStackableItems and build new list containing only itemIds with >1 stackable slots.
	local tStackable = {}	
	for itemId,tSlots in pairs(tStackableItems) do
		-- More than one stackable stack of this stackable item? If so, add to tStackable. Stack!
		if #tSlots > 1 then 		
			tStackable[#tStackable+1] = tSlots
		end
	end

	-- Store in module scope
	self.tStackable = tStackable
end

function Stack:RedeterminePendingInProgress()
	self:DeterminePendingOperations()
end

-- An item is considered stackable if it has a current stacksize < max stacksize.
function Stack:IsItemStackable(tItem)	
	return tItem:GetMaxStackCount() > 1 and tItem:GetStackCount() < tItem:GetMaxStackCount()
end


-- Performs one single stacking operation.
-- Sets a flag indicating if further stacking is possible, but takes no further action 
-- (awaits Event indicating this stacking-operation has fully completed)
function Stack:Execute()
	--Print("Stack:Execute")
	-- Safeguard, but should only happen if someone calls :Execute() before opening the guild bank
	if self.tStackable == nil then
		self.Controller:StopModule(self.Controller.enumModules.Stack)		
		return
	end
	
	-- Grab last element from the tStackable list of item-types
	local tSlots = table.remove(self.tStackable)
	
	-- Nothing in self.tStackable? Just do nothing then.
	if tSlots == nil then
		self.Controller:StopModule(self.Controller.enumModules.Stack)
		return
	end
	
	-- Identify source (smallest) and target (largest) stacks
	local tSourceSlot, tTargetSlot
	for _, tSlot in pairs(tSlots) do		
		if (tSourceSlot == nil) or -- Accept first hit as source
			(tSlot.itemInSlot:GetStackCount() < tSourceSlot.itemInSlot:GetStackCount() or -- Current slot has fewer items
			(tSlot.itemInSlot:GetStackCount() == tSourceSlot.itemInSlot:GetStackCount()) and tSlot.nIndex > tSourceSlot.nIndex) then -- Current slot has same number of items, but is at a higher index			
			tSourceSlot = tSlot
		end

		if (tTargetSlot == nil) or -- Accept first hit as target
			(tSlot.itemInSlot:GetStackCount() > tTargetSlot.itemInSlot:GetStackCount() or -- Current slot has more items
			(tSlot.itemInSlot:GetStackCount() == tTargetSlot.itemInSlot:GetStackCount()) and tSlot.nIndex < tTargetSlot.nIndex) then -- Current slot has same number of items, but is at a lower index
			tTargetSlot = tSlot
		end		
	end

	-- Determine current stack move size
	local nRoomInTargetSlot = tSourceSlot.itemInSlot:GetMaxStackCount() - tTargetSlot.itemInSlot:GetStackCount()
	local nItemsToMove = math.min(nRoomInTargetSlot, tSourceSlot.itemInSlot.GetStackCount())			
	
	-- Make a note of slot-indices that are being updated. We need to await events for both slots before triggering next stack pass.	
	local bPartialMove = nItemsToMove < tSourceSlot.itemInSlot.GetStackCount()
	if bPartialMove then
		-- Partial move (only part of source stack is moved into target) updates target and updates source
		self.Controller:SetPendingEvents(self.Controller.enumModules.Stack, {
			[tTargetSlot.nIndex] = {false}, 
			[tSourceSlot.nIndex] = {false}
		})
	else
		-- Full move (entire source stack is moved into target) updates target and removes source
		self.Controller:SetPendingEvents(self.Controller.enumModules.Stack, {
			[tTargetSlot.nIndex] = {false}, 
			[tSourceSlot.nIndex] = {true}
		})
	end

	-- Fire off the update by beginning and ending the bank transfer from source to target.
	GBT.guildOwner:BeginBankItemTransfer(tSourceSlot.itemInSlot, nItemsToMove)
	
	-- Will trigger OnGuildBankItem x2, one for target (items picked up), one for target (items deposited)
	GBT.guildOwner:EndBankItemTransfer(GBT.nCurrentTab, tTargetSlot.nIndex) 
end


-- When the stack-button is clicked, just execute the stack operation
function GBT:OnStackButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	local controller = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
	if controller:GetInProgressModule() ~= nil then
		controller:StopModule(controller.enumModules.Stack)
	else
		controller:StartModule(controller.enumModules.Stack)
	end	
end

-- When mousing over the button, change bank-slot opacity to identify stackables
function GBT:OnStackButton_MouseEnter(wndHandler, wndControl, x, y)
	local controllerArrange = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
	if controllerArrange:GetInProgressModule() == nil and wndControl:IsEnabled() then	
		local controllerFilter = Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage
		
		-- Build [idx]->true table for ApplyFilter
		local tById = {}
		for _,tSlots in ipairs(Stack.tStackable) do
			for _,tSlot in pairs(tSlots) do
				tById[tSlot.nIndex] = true
			end			
		end
		
		controllerFilter:ApplyFilter(tById)
	end
end

-- When no longer hovering over the button, reset opacity for stackables to whatever matches search criteria
function GBT:OnStackButton_MouseExit(wndHandler, wndControl, x, y)
	local controllerFilter = Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage
	controllerFilter:ApplyFilter()
end

function Stack:Enable()
	local wndButton = GBT:GetToolbarForm():FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:SetText("Stack")
		wndButton:Enable(true)
	end	
end

function Stack:Disable()
	local wndButton = GBT:GetToolbarForm():FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:SetText("Stack")
		wndButton:Enable(false)
	end	
end

function Stack:UpdateProgress()
	-- Update button
	local wndButton = GBT:GetToolbarForm():FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:SetText(self:GetPendingOperationCount())
	end	
end


Apollo.RegisterPackage(Stack, "GuildBankTools:Module:Arrange:Stack", 1, {}) 