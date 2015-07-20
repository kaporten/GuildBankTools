
local GuildBankTools = Apollo.GetAddon("GuildBankTools")


	--[[ (local) Sorting functions --]]
	
local function SlotSortOrderComparator(tSlotA, tSlotB)
	-- If either (or both) input slots are nil, non-nil slot "wins" - tSlotA wins if both are nil
	if tSlotA == nil or tSlotB == nil then
		return tSlotA ~= nil or tSlotB == nil
	end

	-- Extract items from slots
	local itemA = tSlotA.itemInSlot
	local itemB = tSlotB.itemInSlot

	-- Same nil check on contained items as for slots
	if itemA == nil or itemB == nil then
		return itemA ~= nil or itemB == nil
	end
	
	-- Family (Crafting, Schematic etc)
	if itemA:GetItemFamily() ~= itemB:GetItemFamily() then
		return itemA:GetItemFamily() < itemB:GetItemFamily()
	end
	
	-- Category (Family sub-category. For crafting it can be Mining, Technologist etc)
	if itemA:GetItemCategory() ~= itemB:GetItemCategory() then
		return itemA:GetItemCategory() < itemB:GetItemCategory()
	end

	-- Same family and category of item. Apply category-specific rules
	-- TODO: pseudo code below
	--if itemA:GetItemCategory == "amp" then
		-- amp sort by class
	--end
	
	-- TODO: Add category-id --> function map
	
	-- Default match (if no other rules apply) is to sort by current index
	return tSlotA.nIndex < tSlotB.nIndex
end

local function SlotSortOrderComparator_Category_AMPs(tSlotA, tSlotB)
end

function GuildBankTools:CalculateSortedList(guildOwner, nTab)
	local tTabContent = guildOwner:GetBankTab(nTab)
	table.sort(tTabContent, SlotSortOrderComparator)
	
--	for idx,tSlot in ipairs(tTabContent) do
--		Print(idx .. ": " .. tSlot.itemInSlot:GetName())
--	end

	return tTabContent
end


function GuildBankTools:Sort()
	-- Set flag for retriggering another sort after this one	
	self.bIsSorting = true
	
	local tCurrentSlots = self.guildOwner:GetBankTab(self.nCurrentTab)
	
	-- Loop through bank-slots, stop at first slot with incorrect inventoryItemId
	for idx,tSortedSlot in ipairs(self.tSortedSlots) do
		if tSortedSlot.itemInSlot:GetInventoryId() ~= tCurrentSlots[idx].itemInSlot:GetInventoryId() then
			Print("Mismatch at idx " .. idx .. ", should be " .. tSortedSlot.itemInSlot:GetName())
			return
		end
	end
--[[
	
	local GB = Apollo.GetAddon("GuildBank")
	for i,wndSlot in ipairs(GB.tWndRefs.tBankItemSlots) do
		if 
	end
	for idx,tSlot in ipairs(guildOwner:GetBankTab(nTab)) do
		Print(idx .. ": " .. tSlot.itemInSlot:GetName())
	end
	--]]
end


	--[[ Button events --]]

function GuildBankTools:OnSortButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	Print("OnSortButton_ButtonSignal")
	self:Sort()
end

function GuildBankTools:OnSortButton_MouseEnter(wndHandler, wndControl, x, y)
	
	Print("OnSortButton_MouseEnter")
end

function GuildBankTools:OnSortButton_MouseExit(wndHandler, wndControl, x, y)
	Print("OnSortButton_MouseExit")	
end
