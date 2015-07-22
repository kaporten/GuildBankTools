
local GuildBankTools = Apollo.GetAddon("GuildBankTools")
local GB = Apollo.GetAddon("GuildBank")


	--[[ (local) Sorting functions --]]


local Sort = {}
GuildBankTools.GBT_Sort = Sort
	
function Sort.SlotSortOrderComparator_Category_SkillAMPs(tSlotA, tSlotB)	
	local classA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]
	local classB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]	
	if classA ~= classB then
		return classA < classB
	end
	
	-- Inconclusive, carry on with general last-ditch sorting
	return nil
end

Sort.tCategoryComparators = {
	[130] = Sort.SlotSortOrderComparator_Category_SkillAMPs
}
	
function Sort.SlotSortOrderComparator(tSlotA, tSlotB)
	-- If either (or both) input slots are nil, non-nil slot "wins" - tSlotA wins if both are nil
	if tSlotA == nil or tSlotB == nil then return Sort:CompareNils(tSlotA, tSlotB) end

	-- Shorthand variables to items in slots
	local itemA, itemB = tSlotA.itemInSlot, tSlotB.itemInSlot

	-- Same nil check on items as for slots
	if itemA == nil or itemB == nil then return Sort:CompareNils(itemA, itemB) end
	
	
	-- Family (Crafting, Schematic etc)
	if itemA:GetItemFamily() ~= itemB:GetItemFamily() then
		return itemA:GetItemFamily() < itemB:GetItemFamily()
	end
	
	-- Category (Family sub-category. For crafting it can be Mining, Technologist etc)
	if itemA:GetItemCategory() ~= itemB:GetItemCategory() then
		return itemA:GetItemCategory() < itemB:GetItemCategory()
	end
	
	-- Category specific sorters
	if Sort.tCategoryComparators[itemA:GetItemCategory()] ~= nil then 		
		local fComparator = Sort.tCategoryComparators[itemA:GetItemCategory()]
		local result = fComparator(tSlotA, tSlotB)
		if result ~= nil then 
			return result 
		end
		
	end

	-- Level requirements
	if itemA:GetDetailedInfo().tPrimary.tLevelRequirement ~= nil or itemB:GetDetailedInfo().tPrimary.tLevelRequirement ~= nil then
		if itemA:GetDetailedInfo().tPrimary.tLevelRequirement == nil then
			-- ItemA has no level requirements (but B does), so sort A before B
			return true
		end
		
		if itemB:GetDetailedInfo().tPrimary.tLevelRequirement == nil then
			-- ItemB has no level requirements (but A does), so sort B before A
			return false			
		end
		
		-- Both have level requirements. Only sort by this if they're different.
		if itemA:GetDetailedInfo().tPrimary.tLevelRequirement.nLevelRequired ~= itemB:GetDetailedInfo().tPrimary.tLevelRequirement.nLevelRequired then
			return itemA:GetDetailedInfo().tPrimary.tLevelRequirement.nLevelRequired < itemB:GetDetailedInfo().tPrimary.tLevelRequirement.nLevelRequired
		end
	end
	
	--TODO: item level

	-- Item name
	--[[
	if Sort.bReverse then
		if itemA:GetName() > itemB:GetName() then
			return itemA:GetName() < itemB:GetName()
		end
	else
		if itemA:GetName() ~= itemB:GetName() then
			return itemA:GetName() < itemB:GetName()
		end
	end
	--]]
	if itemA:GetName() ~= itemB:GetName() then
		return itemA:GetName() < itemB:GetName()
	end
	
	-- Same family and category of item. Apply category-specific rules
	-- TODO: pseudo code below
	--if itemA:GetItemCategory == "amp" then
		-- amp sort by class
	--end
	
	-- TODO: Add category-id --> function map
	
	-- Default match (if no other rules apply) is to sort by current index
	local result = tSlotA.nIndex < tSlotB.nIndex
	--local result = itemA:GetInventoryId() < itemB:GetInventoryId()
	--local result = itemA:GetItemId() < itemB:GetItemId()
	
	return result
end

function Sort:CompareNils(a, b)
	Print("Comparing nils")
	if a == nil and b == nil then
		return false
	end
	if a == nil then
		return false
	end
	if b == nil then
		return true
	end
end

function Sort:DistributeBlanksSingle(tEntries, nBankSlots)
	-- How many blank slots are there?
	local nBlanks = nBankSlots-#tEntries

	-- No blank spaces to distribute? Then do nothing
	if nBlanks <= 0 then
		return 
	end
	
	while nBlanks > 0 do
		local nInsertIndex = 1
		
		-- Scan for first appropriate spot to insert
		for idx=nInsertIndex, #tEntries do
			local cur = tEntries[idx]
			local nxt = tEntries[idx+1]

			if	nxt ~= nil 								
				and cur.bIsBlank ~= true -- Never adjacent to existing blanks
				and nxt.bIsBlank ~= true -- Never adjacent to existing blanks
				and (cur.itemInSlot:GetItemFamily() ~= nxt.itemInSlot:GetItemFamily() -- When family changes
				     or cur.itemInSlot:GetItemCategory() ~= nxt.itemInSlot:GetItemCategory()) -- Or when category changes
			then				
				nInsertIndex = idx+1
				break
			end
		end
		
		-- Was any insertion point found?
		if nInsertIndex > 1 then
			-- Appropriate insertion point found, insert blank and decrement blanks left			
			table.insert(tEntries, nInsertIndex, {
				nIndex = "new",
				bIsBlank = true
			})			
			nBlanks = nBlanks - 1
		else
			-- No appropriate insertion point found, break outer loop by setting blanks left to 0
			nBlanks = 0
		end
	end
	
	-- Realign indices on all slots with new actual index
	for newIndex,entry in ipairs(tEntries) do
		entry.nIndex = newIndex
	end
end

-- After sorting, some slots may already contain an item of desired type 
-- Avoid switching multiple identical items back and forth by adjusting the 
-- sorted list with as-is tab content
function Sort:AlignWithCurrentSlots(tSortedSlots, tCurrentSlots)
	for _,tCurrentSlot in ipairs(tCurrentSlots) do
		local strCurrentName = tCurrentSlot.itemInSlot:GetName()
		local nCurrentInventoryId = tCurrentSlot.itemInSlot:GetInventoryId()
		
		if tSortedSlots[tCurrentSlot.nIndex] ~= nil and tSortedSlots[tCurrentSlot.nIndex].bIsBlank ~= true then
			local strSortedName = tSortedSlots[tCurrentSlot.nIndex].itemInSlot:GetName()
			local nSortedInventoryId = tSortedSlots[tCurrentSlot.nIndex].itemInSlot:GetInventoryId()
			
			if strCurrentName == strSortedName and nCurrentInventoryId ~= nSortedInventoryId then
				-- Ok, so item with same name, but different inventoryId found. 
				-- Adjust sorted-list so the item with this particular inventoryId is "sorted to" to tCurrentSlot.nIndex instead
				local tSlotToSwap1 = tSortedSlots[tCurrentSlot.nIndex]
				local tSlotToSwap2 = self:GetSlotByInventoryId(tSortedSlots, nSortedInventoryId)
				
				--[[
				Print(string.format("Swapping: Item1=[index: %d, itemId: %d, inventoryId: %d, name: %s] <--> Item1=[index: %d, itemId: %d, inventoryId: %d, name: %s]",
					tSlotToSwap1.nIndex, tSlotToSwap1.itemInSlot:GetItemId(), tSlotToSwap1.itemInSlot:GetInventoryId(), tSlotToSwap1.itemInSlot:GetName(),
					tSlotToSwap2.nIndex, tSlotToSwap2.itemInSlot:GetItemId(), tSlotToSwap2.itemInSlot:GetInventoryId(), tSlotToSwap2.itemInSlot:GetName()))
				--]]

				tSortedSlots[tCurrentSlot.nIndex] = tSlotToSwap2
				tSortedSlots[tSlotToSwap2.nIndex] = tSlotToSwap1				
			end
		end	
	end
end

function Sort:CalculateSortedList(guildOwner, nTab)
	local tTabContent = GuildBankTools:GetCurrentTabSlots()
	table.sort(tTabContent, Sort.SlotSortOrderComparator)
	
	Sort:DistributeBlanksSingle(tTabContent, GuildBankTools:GetCurrentTabSize())

	-- After distributing spaces, realign indices on all contained slots' .nIndex with new actual index
	for newIndex,entry in ipairs(tTabContent) do
		entry.nIndex = newIndex
	end

	Sort:AlignWithCurrentSlots(tTabContent, GuildBankTools:GetCurrentTabSlots())
	
	-- And re-align .nIndex again after "soft-swapping" identical sorted slots
	for newIndex,entry in ipairs(tTabContent) do
		entry.nIndex = newIndex
	end

	-- Store result in self-variable
	self.tSortedSlots = tTabContent
end


-- TODO: Move to general

function Sort:GetSlotByInventoryId(tSlots, nInventoryId)
	for idx, tSlot in ipairs(tSlots) do
		if tSlot.bIsBlank ~= true and tSlot.itemInSlot:GetInventoryId() == nInventoryId then
			return tSlot
		end
	end
end

function Sort:GetSlotByIndex(tCurrentSlots, nIndex)
	for idx, tSlot in ipairs(tCurrentSlots) do
		if tSlot.nIndex == nIndex then
			return tSlot
		end
	end
end

function Sort:Sort()	
	-- Start async event-driven process.
	GuildBankTools:StartOperation(GuildBankTools.enumOperations.Sort, self, "Sort")
	
	-- All current bank slots, prior to sort operation
	local tCurrentSlots = GuildBankTools.guildOwner:GetBankTab(GuildBankTools.nCurrentTab)
	
	-- Loop through sorted list of bank-slots, process first slot with incorrect InventoryId (first slot to move stuff into)
	for _,tSortedTargetSlot in ipairs(self.tSortedSlots) do

		if tSortedTargetSlot.bIsBlank == true then
			-- Do nothing, just skip this blank slot
		else
			-- Find current source slot by scanning for slot which contains the desired inventory id
			local tSourceSlot = Sort:GetSlotByInventoryId(tCurrentSlots, tSortedTargetSlot.itemInSlot:GetInventoryId())

			-- Is the current placement of this inventory id at the correct index?
			if tSortedTargetSlot.nIndex ~= tSourceSlot.nIndex then
					
				-- About to sort a slot. Determine if it is a move (to empty target), or swap (to already occupied target).			
				local bIsSwap = Sort:GetSlotByIndex(tCurrentSlots, tSortedTargetSlot.nIndex) ~= nil

				-- Expected events to process before triggering next move depends on swap or move.
				if bIsSwap == true then
					-- Swap fires bRemoved=true|false events for both slots
					GuildBankTools:SetPendingEvents(GuildBankTools.enumOperations.Sort, {
						[tSortedTargetSlot.nIndex] = {true, false}, 
						[tSourceSlot.nIndex] = {true, false}
					})
				else				
					-- Move fires bRemoved=true for source, bRemoved=false for target
					GuildBankTools:SetPendingEvents(GuildBankTools.enumOperations.Sort, {
						[tSortedTargetSlot.nIndex] = {false}, 
						[tSourceSlot.nIndex] = {true}
					})
				end
				
				--Print(string.format("Moving [nTargetIdx=%d]:(ItemId=%d, name='%s') to index [%d]", tSourceSlot.nIndex, tSourceSlot.itemInSlot:GetItemId(), tSourceSlot.itemInSlot:GetName(), tSortedTargetSlot.nIndex))
				
				-- Fire off the update by beginning and ending the bank transfer from source to target.
				GuildBankTools.guildOwner:BeginBankItemTransfer(tSourceSlot.itemInSlot, tSourceSlot.itemInSlot:GetStackCount())
				
				-- Will trigger OnGuildBankItem x2, one for target (items picked up), one for target (items deposited)
				GuildBankTools.guildOwner:EndBankItemTransfer(GuildBankTools.nCurrentTab, tSortedTargetSlot.nIndex) 

				return
			end
		end
	end
	
	-- Nothing moved in for-loop, guess we're all done sorting	
	GuildBankTools:StopOperation(GuildBankTools.enumOperations.Sort)
end

function Sort:UpdateSortButton()
	-- Do nothing if overlay form is not loaded
	if GuildBankTools.wndOverlayForm == nil then
		return
	end
		
	local bEnable = not self:IsEverythingSorted()
	local wndButton = GuildBankTools.wndOverlayForm:FindChild("SortButton")
	if wndButton ~= nil then
		wndButton:Enable(bEnable)	
	end
end

function Sort:IsEverythingSorted()
	local tCurrentSlots = GuildBankTools:GetCurrentTabSlots()
	
	-- Build map of current slot idx -> inventoryId
	local tCurrentInventoryIds = {}
	for _,tSlot in ipairs(tCurrentSlots) do
		tCurrentInventoryIds[tSlot.nIndex] = tSlot.itemInSlot:GetInventoryId()
	end
	
	-- Check if all slots match
	for _,tSortedSlot in ipairs(self.tSortedSlots) do
		if tSortedSlot.bIsBlank then
			-- Blank sorted slot should not match any current slot
			if tCurrentInventoryIds[tSortedSlot.nIndex] ~= nil then
				return false
			end
		else
			local invId = tSortedSlot.itemInSlot:GetInventoryId()
			if tCurrentInventoryIds[tSortedSlot.nIndex] ~= invId then
				return false
			end
		end
	end
	return true
end


	--[[ Button events --]]

	-- TODO: Load/handle compartmentalized sort-form from this file
function GuildBankTools:OnSortButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	Sort:Sort()
end

function GuildBankTools:OnSortButton_MouseEnter(wndHandler, wndControl, x, y)
	
--	Print("OnSortButton_MouseEnter")
end

function GuildBankTools:OnSortButton_MouseExit(wndHandler, wndControl, x, y)
--	Print("OnSortButton_MouseExit")	
end
