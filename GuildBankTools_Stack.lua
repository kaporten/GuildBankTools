
local GuildBankTools = Apollo.GetAddon("GuildBankTools")
local GB = Apollo.GetAddon("GuildBank")

local Stack = {}

-- Scans current guild bank tab, returns list containing list of stackable slots
function Stack:IdentifyStackableItems()
	-- Identify all stackable slots in the current tab, and add to tStackableItems
	-- This includes stackables with just 1 stack (ie. nothing to stack with)
	-- tStackableItems is a table with key=itemId, value=list of slots containing this itemId
	local tStackableItems = {}
	for _,tSlot in ipairs(GuildBankTools:GetCurrentTabSlots()) do
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

	-- Store in addon scope
	self.tStackable = tStackable
end

-- An item is considered stackable if it has a current stacksize < max stacksize.
function Stack:IsItemStackable(tItem)	
	return tItem:GetMaxStackCount() > 1 and tItem:GetStackCount() < tItem:GetMaxStackCount()
end


-- Performs one single stacking operation.
-- Sets a flag indicating if further stacking is possible, but takes no further action 
-- (awaits Event indicating this stacking-operation has fully completed)
function Stack:Execute()
	
	-- Safeguard, but should only happen if someone calls :Execute() before opening the guild bank
	if self.tStackable == nil then
		GuildBankTools:StopModule(GuildBankTools.enumModules.Stack)		
		return
	end
	
	-- Grab last element from the tStackable list of item-types
	local tSlots = table.remove(self.tStackable)
	
	-- Nothing in self.tStackable? Just do nothing then.
	if tSlots == nil then
		GuildBankTools:StopModule(GuildBankTools.enumModules.Stack)
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
		GuildBankTools:SetPendingEvents(GuildBankTools.enumModules.Stack, {
			[tTargetSlot.nIndex] = {false}, 
			[tSourceSlot.nIndex] = {false}
		})
	else
		-- Full move (entire source stack is moved into target) updates target and removes source
		GuildBankTools:SetPendingEvents(GuildBankTools.enumModules.Stack, {
			[tTargetSlot.nIndex] = {false}, 
			[tSourceSlot.nIndex] = {true}
		})
	end
	
	-- Fire off the update by beginning and ending the bank transfer from source to target.
	GuildBankTools.guildOwner:BeginBankItemTransfer(tSourceSlot.itemInSlot, nItemsToMove)
	
	-- Will trigger OnGuildBankItem x2, one for target (items picked up), one for target (items deposited)
	GuildBankTools.guildOwner:EndBankItemTransfer(GuildBankTools.nCurrentTab, tTargetSlot.nIndex) 
end

-- Highlight all items-to-stack on the current tab
function Stack:HighlightStackables()
	-- Build lookuptable of all stackable indices. Key=bank slot index, Value=true (value not used).
	local tStackableSlotIdx = {}
	for _,tStackableItem in ipairs(self.tStackable) do
		for _,tSlot in ipairs(tStackableItem) do
			tStackableSlotIdx[tSlot.nIndex] = true
		end		
	end
		
	-- Go through all bank wnd-slots, and set visibility according to tStackableSlotIdx list
	if GB ~= nil then
		for i,wndSlot in ipairs(GB.tWndRefs.tBankItemSlots) do
			if tStackableSlotIdx[i] ~= nil then
				wndSlot:FindChild("BankItemIcon"):SetOpacity(GuildBankTools.enumOpacity.Visible)
			else
				wndSlot:FindChild("BankItemIcon"):SetOpacity(GuildBankTools.enumOpacity.Hidden)
			end			
		end
	end	
end

-- When the stack-button is clicked, just execute the stack operation
function GuildBankTools:OnStackButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	if GuildBankTools:IsInProgress(GuildBankTools.enumModules.Stack) then
		GuildBankTools:StopModule(GuildBankTools.enumModules.Stack)
	else
		GuildBankTools:StartModule(GuildBankTools.enumModules.Stack)
	end	
end

-- When mousing over the button, change bank-slot opacity to identify stackables
function GuildBankTools:OnStackButton_MouseEnter(wndHandler, wndControl, x, y)
	if wndControl:IsEnabled() then
		Stack:HighlightStackables()
	end
end

-- When no longer hovering over the button, reset opacity for stackables to whatever matches search criteria
function GuildBankTools:OnStackButton_MouseExit(wndHandler, wndControl, x, y)
	GuildBankTools:HighlightSearchMatches()
end

function Stack:Enable(bInProgress)
	Print("Enable: Stack (in progress: " .. tostring(bInProgress))
	
	-- Text on button depends on in-progress or not
	local text = bInProgress and "..." or "Stack"

	-- Enable button depends on stackable items or not, and also if other modules are in progress
	local bEnable = bInProgress or (self.tStackable ~= nil and #self.tStackable > 0)
	
	-- Update button
	local wndButton = GuildBankTools.wndOverlayForm:FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:Enable(bEnable)
		wndButton:SetText(text)
	end	
end

function Stack:Disable()
	Print("Disable: Stack")
	local wndButton = GuildBankTools.wndOverlayForm:FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:Enable(false)
		wndButton:SetText("Stack")
	end	
end



Apollo.RegisterPackage(Stack, "GuildBankTools:Stack", 1, {}) 