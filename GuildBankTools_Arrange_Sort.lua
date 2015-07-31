--[[
	Arrange:Sort module.
--]]

local Sort = {}
local GBT = Apollo.GetAddon("GuildBankTools")

function Sort:Initialize()
	self.Controller = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage

	-- Sort Comparators, in order-of-execution. 
	-- Comparators will be executed from top to bottom until a comparator 
	-- returns true or false (nil means items are considered identical by comparator).
	self.tComparators = {
		-- Item family (Crafting, Schematic etc - these are seperated by space)		
		self.Comparator_Family,
		
		-- May call additional function, if the two items category is found in tComparators_Category
		self.Comparator_Category, 
		
		self.Comparator_RequiredLevel,
		self.Comparator_ItemId,		
		self.Comparator_CurrentIndex,
	}

	-- Comparators for individual Categories
	-- Index is category type
	self.tComparators_Category = {
		-- [67] = self.Comparator_Category_Decor,
		[130] = self.Comparator_Category_SkillAMPs,
		[135] = self.Comparator_Category_Runes,
	}	
end


	--[[ Controller "pending operations" interface --]]

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
	--Print("Sort:DeterminePendingOperations")
	local tTabContent = GBT:GetBankTab()
	table.sort(tTabContent, Sort.TableSortComparator)
	
	Sort:DistributeBlanksSingle(tTabContent, GBT:GetBankTabSlots())

	-- After distributing spaces, realign indices on all contained slots' .nIndex with new sorted-index
	for newIndex,entry in ipairs(tTabContent) do
		entry.nIndex = newIndex
	end
	
	-- Store result in self-variable
	self.tSortedSlots = tTabContent
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


	--[[ Utility lookup functions --]]

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


	--[[ Module control --]]

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

function Sort:UpdateProgress()
	local wndButton = Apollo.GetAddon("GuildBankTools"):GetToolbarForm():FindChild("SortButton")
	if wndButton ~= nil then
		wndButton:SetText(self:GetPendingOperationCount())
	end	
end


	--[[ Item comparison functions --]]
	
-- Main entry point for sorting, used by table.sort (so has to be . not : ... no self)
function Sort.TableSortComparator(tSlotA, tSlotB)
	-- If either (or both) input slots are nil, non-nil slot "wins" - tSlotA wins if both are nil
	if tSlotA == nil or tSlotB == nil then return Sort:CompareNils(tSlotA, tSlotB) end

	-- Shorthand variables to items in slots
	local itemA, itemB = tSlotA.itemInSlot, tSlotB.itemInSlot
	if itemA == nil or itemB == nil then return Sort:CompareNils(itemA, itemB) end
	
	-- All items are expected to have item details as well
	local detailsA, detailsB = itemA:GetDetailedInfo(), itemB:GetDetailedInfo()
	if detailsA == nil or detailsB == nil then return Sort:CompareNils(detailsA, detailsB) end
	
	-- Run all comparators in order
	for idx,fComparator in ipairs(Sort.tComparators) do
		--Print("Comparator " .. idx)
		local result = fComparator(Sort, tSlotA, tSlotB)
		if result ~= nil then
			return result
		end
	end
	
	--Print("WARNING: All comparators failed to sort slots " .. tSlotA.nIndex .. ":" .. tSlotA.itemInSlot:GetName() .. " vs " .. tSlotB.nIndex .. ":" .. tSlotB.itemInSlot:GetName())
	--return true
end

-- General nil check	
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

-- General value comparision
function Sort:CompareValues(a, b)
	if a ~= b then
		return a < b
	end
	
	-- Inconclusive, return nil (indicates further sorting)
	return nil
end

function Sort:Comparator_Family(tSlotA, tSlotB)
	-- Family (Crafting, Schematic etc)
	return self:CompareValues(
		tSlotA.itemInSlot:GetItemFamily(), 
		tSlotB.itemInSlot:GetItemFamily())
end

function Sort:Comparator_Category(tSlotA, tSlotB)	
	-- Category (Family sub-category. For crafting it can be Mining, Technologist etc)
	local result = self:CompareValues(
		tSlotA.itemInSlot:GetItemCategory(), 
		tSlotB.itemInSlot:GetItemCategory())
	
	if result ~= nil then
		-- Different categories
		return result
	else
		-- Same category? Check category-specific comparators
		if result == nil then
			local cat = tSlotA.itemInSlot:GetItemCategory()
			if self.tComparators_Category[cat] ~= nil then 		
				local fComparator = self.tComparators_Category[cat]
				return fComparator(self, tSlotA, tSlotB)			
			end		
		end
	end
end

function Sort:Comparator_RequiredLevel(tSlotA, tSlotB)
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

function Sort:Comparator_Name(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetName(), 
		tSlotB.itemInSlot:GetName())
end

function Sort:Comparator_ItemId(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetItemId(), 
		tSlotB.itemInSlot:GetItemId())
end

function Sort:Comparator_CurrentIndex(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.nIndex, 
		tSlotB.nIndex)
end

function Sort:Comparator_Category_SkillAMPs(tSlotA, tSlotB)		
	local classA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]
	local classB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary.arClassRequirement.arClasses[1]	
	
	return Sort:CompareValues(
		classA, 
		classB)
end

function Sort:Comparator_Category_Runes(tSlotA, tSlotB)
	local runeSortOrderA = tSlotA.itemInSlot:GetDetailedInfo().tPrimary.tRuneInfo.nSortOrder
	local runeSortOrderB = tSlotB.itemInSlot:GetDetailedInfo().tPrimary.tRuneInfo.nSortOrder
	
	return Sort:CompareValues(
		runeSortOrderA, 
		runeSortOrderB)
end


	--[[ Button events --]]

function GBT:OnSortButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	local controllerArrange = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
	if controllerArrange:GetInProgressModule() ~= nil then
		controllerArrange:StopModule(controllerArrange.enumModules.Sort)
	else
		controllerArrange:StartModule(controllerArrange.enumModules.Sort)
	end	
end

-- When mousing over the button, change bank-slot opacity to identify stackables
function GBT:OnSortButton_MouseEnter(wndHandler, wndControl, x, y)
	local controllerArrange = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage
	if controllerArrange:GetInProgressModule() == nil and wndControl:IsEnabled() then	
		local controllerFilter = Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage
						
		-- Get current bank slot contents
		local tCurrentSlots = GBT:GetBankTab()
		
		-- Run through list of sorted items, compare sorted with current ItemId for each slot	
		-- For speed, first build map of current slot idx -> itemId
		local tCurrentItemIds = {}
		for _,tSlot in ipairs(tCurrentSlots) do
			tCurrentItemIds[tSlot.nIndex] = tSlot.itemInSlot:GetItemId()
		end
		
		-- For all 128 possible slots
		local tByIdx = {}
		for i=1, GBT:GetBankTabSlots() do 
			-- Assume every slot is correctly sorted, 
			-- and thus DOES NOT match the "highlight sortable" filter we're building
			tByIdx[i] = false
			
			local tSortedSlot = Sort.tSortedSlots[i]
			if tSortedSlot == nil or tSortedSlot.bIsBlank then
				-- Blank sorted slot should not match any current slot
				if tCurrentItemIds[i] ~= nil then
					tByIdx[i] = true				
				end
			else
				-- Non-blank sorted slot should have identical itemId in current slot
				local itemId = tSortedSlot.itemInSlot:GetItemId()
				if tCurrentItemIds[i] ~= itemId then
					tByIdx[i] = true
				end
			end
		end
		
		controllerFilter:ApplyFilter(tByIdx)
	end
end

-- When no longer hovering over the button, reset opacity for stackables to whatever matches search criteria
function GBT:OnSortButton_MouseExit(wndHandler, wndControl, x, y)
	local controllerFilter = Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage
	controllerFilter:ApplyFilter()
end


Apollo.RegisterPackage(Sort, "GuildBankTools:Module:Arrange:Sort", 1, {}) 