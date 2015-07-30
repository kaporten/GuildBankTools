--[[
	Arrange:Sort module.
--]]

local Sort = {}
local GBT = Apollo.GetAddon("GuildBankTools")

function Sort:Initialize()
	self.Controller = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
end

function Sort.Comparator_Family(tSlotA, tSlotB)
	-- Family (Crafting, Schematic etc)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetItemFamily(), 
		tSlotB.itemInSlot:GetItemFamily())
end

function Sort.Comparator_Category(tSlotA, tSlotB)	
	-- Category (Family sub-category. For crafting it can be Mining, Technologist etc)
	local result = Sort:CompareValues(
		tSlotA.itemInSlot:GetItemCategory(), 
		tSlotB.itemInSlot:GetItemCategory())
	
	if result ~= nil then
		return result
	else
		-- Same category? Check category-specific comparators
		if result == nil then
			local cat = tSlotA.itemInSlot:GetItemCategory()
			if Sort.tComparators_Category[cat] ~= nil then 		
				local fComparator = Sort.tComparators_Category[cat]
				return fComparator(tSlotA, tSlotB)			
			end		
		end
	end
end

function Sort.Comparator_RequiredLevel(tSlotA, tSlotB)
	local primaryA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary
	local primaryB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary
	
	-- Level requirements
	if primaryA.tLevelRequirement ~= nil or primaryB.tLevelRequirement ~= nil then
		-- ItemA has no level requirements (but B does), so sort A before B
		if primaryA.tLevelRequirement == nil then return true end
		
		-- ItemB has no level requirements (but A does), so sort B before A
		if primaryB.tLevelRequirement == nil then return false end
		
		-- Both have level requirements
		return Sort:CompareValues(primaryA.tLevelRequirement.nLevelRequired, primaryB.tLevelRequirement.nLevelRequired)		
	end
end

function Sort.Comparator_Name(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetName(), 
		tSlotB.itemInSlot:GetName())
end

function Sort.Comparator_ItemId(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetItemId(), 
		tSlotB.itemInSlot:GetItemId())
end

function Sort.Comparator_CurrentIndex(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.nIndex, 
		tSlotB.nIndex)
end

function Sort.Comparator_Category_Decor(tSlotA, tSlotB)
	-- First sort FABKits by name, then the rest by name
	local nameA = tSlotA.itemInSlot:GetName()
	local nameB = tSlotB.itemInSlot:GetName()
	
	local bIsFABKitA = string.find(nameA, "FABKit") ~= nil or string.find(nameA, "KITFab") ~= nil or  string.find(nameA, "BAUSatz") 
	local bIsFABKitB = string.find(nameB, "FABKit") ~= nil or string.find(nameB, "KITFab") ~= nil or  string.find(nameB, "BAUSatz") 
	
	if bIsFABKitA or bIsFABKitB then
		if bIsFABKitA and not bIsFABKitB then
			return true
		elseif not bIsFABKitA and bIsFABKitB then
			return false
		else
			return Sort:CompareValues(nameA, nameB)
		end
	end
end

function Sort.Comparator_Category_SkillAMPs(tSlotA, tSlotB)		
	local classA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]
	local classB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]	
	
	return Sort:CompareValues(
		classA, 
		classB)
end

function Sort.Comparator_Category_Runes(tSlotA, tSlotB)
	local runeSortOrderA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary.tRuneInfo.nSortOrder
	local runeSortOrderB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary.tRuneInfo.nSortOrder
	
	return Sort:CompareValues(
		runeSortOrderA, 
		runeSortOrderB)
end

-- Comparators, in order-of-execution. First comparator to identify a difference between A and B breaks the loop.
Sort.tComparators = {
	-- Overall "blank space seperated" family+category
	Sort.Comparator_Family,
	Sort.Comparator_Category, -- May call additional tComparators_Category
	
	Sort.Comparator_RequiredLevel,
	
	-- General fallback sorting
--	Sort.Comparator_Name, -- I don't really like sorting by name, since that makes the sort client-language dependent
						  -- TODO: NOT using _Name makes same-items swap back and forth. Find out why.
	
	
	
	-- TODO: Quality
	-- TODO: Item Level	
	Sort.Comparator_ItemId,
	
	Sort.Comparator_CurrentIndex,
}

-- Index is category type
Sort.tComparators_Category = {
	-- [67] = Sort.Comparator_Category_Decor,
	[130] = Sort.Comparator_Category_SkillAMPs,
	[135] = Sort.Comparator_Category_Runes,
}
	
function Sort.SlotSortOrderComparator(tSlotA, tSlotB)
	-- If either (or both) input slots are nil, non-nil slot "wins" - tSlotA wins if both are nil
	if tSlotA == nil or tSlotB == nil then return Sort:CompareNils(tSlotA, tSlotB) end

	-- Shorthand variables to items in slots
	local itemA, itemB = tSlotA.itemInSlot, tSlotB.itemInSlot
	if itemA == nil or itemB == nil then return Sort:CompareNils(itemA, itemB) end
	
	-- All items are expected to have item details as well
	local detailsA, detailsB = itemA:GetDetailedInfo(), itemB:GetDetailedInfo()
	if detailsA == nil or detailsB == nil then return Sort:CompareNils(detailsA, detailsB) end
	
	for idx,fComparator in ipairs(Sort.tComparators) do
		--Print("Comparator " .. idx)
		local result = fComparator(tSlotA, tSlotB)
		if result ~= nil then
			return result
		end
	end
	
	--Print("WARNING: All comparators failed to sort slots " .. tSlotA.nIndex .. ":" .. tSlotA.itemInSlot:GetName() .. " vs " .. tSlotB.nIndex .. ":" .. tSlotB.itemInSlot:GetName())
	--return true
end

function Sort:CompareNils(a, b)
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

function Sort:CompareValues(a, b)
	if a ~= b then
		return a < b
	end
	
	-- Inconclusive, return nil (indicates further sorting)
	return nil
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

function Sort:HasPendingOperations()
	return self:GetPendingOperationCount() > 0
end

function Sort:GetPendingOperationCount()
	local tCurrentSlots = GBT:GetBankTab()
	
	-- Run through list of sorted items, compare sorted with current ItemId for each slot	
	-- For speed, first build map of current slot idx -> itemId
	local tCurrentItemIds = {}
	for _,tSlot in ipairs(tCurrentSlots) do
		tCurrentItemIds[tSlot.nIndex] = tSlot.itemInSlot:GetItemId()
	end
	
	local nPending = 0
	
	-- Check if all slots match
	for _,tSortedSlot in ipairs(self.tSortedSlots) do
		if tSortedSlot.bIsBlank then
			-- Blank sorted slot should not match any current slot
			if tCurrentItemIds[tSortedSlot.nIndex] ~= nil then
				nPending = nPending + 1
			end
		else
			-- Non-blank sorted slot should have identical itemId in current slot
			local itemId = tSortedSlot.itemInSlot:GetItemId()
			if tCurrentItemIds[tSortedSlot.nIndex] ~= itemId then
				nPending = nPending + 1
			end
		end
	end
		
	return nPending
end

function Sort:DeterminePendingOperations()
	Print("Sort:DeterminePendingOperations")
	local tTabContent = GBT:GetBankTab()
	table.sort(tTabContent, Sort.SlotSortOrderComparator)
	
	Sort:DistributeBlanksSingle(tTabContent, GBT:GetBankTabSlots())

	-- After distributing spaces, realign indices on all contained slots' .nIndex with new sorted-index
	for newIndex,entry in ipairs(tTabContent) do
		entry.nIndex = newIndex
	end
	
	-- Store result in self-variable
	self.tSortedSlots = tTabContent
end

function Sort:GetSlotByIndex(tSlots, nIndex)
	for idx,tSlot in ipairs(tSlots) do
		if tSlot.nIndex == nIndex then
			return tSlot
		end
	end
end

function Sort:GetSlotByItemId(tSlots, nItemId, tIgnoreSlots)
	tIgnoreSlots = tIgnoreSlots or {}
	
	for i=#tSlots,1,-1 do 
		local tSlot = tSlots[i]
		if tSlot.bIsBlank ~= true and tIgnoreSlots[tSlot.nIndex] == nil and tSlot.itemInSlot:GetItemId() == nItemId then
			return tSlot
		end
	end
end

-- Get filtred table [idx->tSlot] of slots with only the specified itemId
function Sort:GetSlotsWithItemId(tSlots, nItemId)
	local result = {}
	for _,tSlot in pairs(tSlots) do		
		if tSlot.bIsBlank ~= true and tSlot.itemInSlot:GetItemId() == nItemId then
			result[tSlot.nIndex] = tSlot			
		end
	end
	return result
end


-- Main module operation
function Sort:Execute()	
	
	-- All current bank slots, prior to sort operation
	local tCurrentSlots = GBT:GetBankTab()
	
	-- Loop through sorted list of bank-slots, process first slot with incorrect item (by id) in it
	for idx,tSortedTargetSlot in ipairs(self.tSortedSlots) do

		if tSortedTargetSlot.bIsBlank == true then
			-- Do nothing, just skip this blank slot
		else
			-- Find current item occupying this index
			local tCurrentSlot = Sort:GetSlotByIndex(tCurrentSlots, idx)
						
			-- Nothing in current slot, or current slot has different item
			if tCurrentSlot == nil or tCurrentSlot.itemInSlot:GetItemId() ~= tSortedTargetSlot.itemInSlot:GetItemId() then
				
				-- List of correctly-sorted slots already containing this itemId. These should be ignored when looking for source mover-slot (irrellevant move).
				local tIgnoreSlots = Sort:GetSlotsWithItemId(self.tSortedSlots, tSortedTargetSlot.itemInSlot:GetItemId())
				
				-- Locate source slot with this kind of itemId
				local tSourceSlot = Sort:GetSlotByItemId(tCurrentSlots, tSortedTargetSlot.itemInSlot:GetItemId(), tIgnoreSlots)
			
				-- About to sort a slot. Determine if it is a move (to empty target), or swap (to already occupied target).			
				local bIsSwap = Sort:GetSlotByIndex(tCurrentSlots, tSortedTargetSlot.nIndex) ~= nil

				-- Expected events to process before triggering next move depends on swap or move.
				if bIsSwap == true then
					-- Swap fires bRemoved=true|false events for both slots
					self.Controller:SetPendingEvents(self.Controller.enumModules.Sort, {
						[tSortedTargetSlot.nIndex] = {true, false}, 
						[tSourceSlot.nIndex] = {true, false}
					})
				else				
					-- Move fires bRemoved=true for source, bRemoved=false for target
					self.Controller:SetPendingEvents(self.Controller.enumModules.Sort, {
						[tSortedTargetSlot.nIndex] = {false}, 
						[tSourceSlot.nIndex] = {true}
					})
				end
				
				--Print(string.format("Moving [nTargetIdx=%d]:(InventoryId=%d, name='%s') to index [%d]", tSourceSlot.nIndex, tSourceSlot.itemInSlot:GetInventoryId(), tSourceSlot.itemInSlot:GetName(), tSortedTargetSlot.nIndex))

				-- Pulse both source and target
				local GB = Apollo.GetAddon("GuildBank")
				if GB ~= nil then
					local bankwnds = GB.tWndRefs.tBankItemSlots
					bankwnds[tSourceSlot.nIndex]:TransitionPulse()
					bankwnds[tSortedTargetSlot.nIndex]:TransitionPulse()
				end	
				
				-- Fire off the update by beginning and ending the bank transfer from source to target.
				GBT.guildOwner:BeginBankItemTransfer(tSourceSlot.itemInSlot, tSourceSlot.itemInSlot:GetStackCount())
				
				-- Will trigger OnGuildBankItem x2, one for target (items picked up), one for target (items deposited)
				GBT.guildOwner:EndBankItemTransfer(GBT.nCurrentTab, tSortedTargetSlot.nIndex) 
				
				return
			end
		end
	end
	
	-- Nothing moved in for-loop, guess we're all done sorting	
	self.Controller:StopModule(self.Controller.enumModules.Sort)
end

function Sort:IsEverythingSorted()
	local tCurrentSlots = GBT:GetBankTab()
	
	-- Run through list of sorted items, compare sorted with current ItemId for each slot	
	-- For speed, first build map of current slot idx -> itemId
	local tCurrentItemIds = {}
	for _,tSlot in ipairs(tCurrentSlots) do
		tCurrentItemIds[tSlot.nIndex] = tSlot.itemInSlot:GetItemId()
	end
	
	-- Check if all slots match
	for _,tSortedSlot in ipairs(self.tSortedSlots) do
		if tSortedSlot.bIsBlank then
			-- Blank sorted slot should not match any current slot
			if tCurrentItemIds[tSortedSlot.nIndex] ~= nil then
				return false
			end
		else
			-- Non-blank sorted slot should have identical itemId in current slot
			local itemId = tSortedSlot.itemInSlot:GetItemId()
			if tCurrentItemIds[tSortedSlot.nIndex] ~= itemId then
				return false
			end
		end
	end
		
	return true
end


function Sort:Enable()
	local wndButton = Apollo.GetAddon("GuildBankTools"):GetToolbarForm():FindChild("SortButton")
	if wndButton ~= nil then
		wndButton:SetText("Sort")
		wndButton:Enable(true)
	end	
end

function Sort:Disable()
	local wndButton = Apollo.GetAddon("GuildBankTools"):GetToolbarForm():FindChild("SortButton")
	if wndButton ~= nil then
		wndButton:SetText("Sort")
		wndButton:Enable(false)
	end	
end

function Sort:SetProgress(nRemaining, nTotal)
	local wndButton = Apollo.GetAddon("GuildBankTools"):GetToolbarForm():FindChild("SortButton")
	if wndButton ~= nil then
		wndButton:SetText(self:GetPendingOperationCount())
	end	
end


	--[[ Button events --]]

	-- TODO: Load/handle compartmentalized sort-form from this file
function GBT:OnSortButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	local controllerArrange = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
	if controllerArrange:GetInProgressModule() ~= nil then
		controllerArrange:StopModule(controllerArrange.enumModules.Sort)
	else
		controllerArrange:StartModule(controllerArrange.enumModules.Sort)
	end	
end


Apollo.RegisterPackage(Sort, "GuildBankTools:Module:Arrange:Sort", 1, {}) 