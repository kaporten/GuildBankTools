--[[
	Arrange:Sort module.
--]]

local Sort = {}
local GBT = Apollo.GetAddon("GuildBankTools")

Sort.enumDirection = {
	Horzontal = "Horizontal",
	Vertical = "Vertical",
}

function Sort:Initialize()
	-- Settings... no way to modify them yet, just use a default sort-direction=Horizontal
	self.tSettings = self.tSettings or {}
	self.tSettings.eDirection = self.tSettings.eDirection or self.enumDirection.Horizontal

	self.Controller = Apollo.GetPackage("GuildBankTools:Controller:Arrange").tPackage

	-- Sort Comparators, in order-of-execution. 
	-- Comparators will be executed from top to bottom until a comparator 
	-- returns true or false (nil means items are considered identical by comparator).
	self.tComparators = {
		-- Item family (Crafting, Schematic etc - these are seperated by space)		
		self.Comparator_Family,
		
		-- May call additional function, if the two items category is found in tComparators_Category
		self.Comparator_Category,
		self.Comparator_Type,
		
		self.Comparator_RequiredLevel,
		self.Comparator_Quality,
		self.Comparator_Name,
		
		-- Fallbacks to ensure unique sorting options
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
	
	-- Horizontal-to-vertical index translation
	self.tHorizontalToVertical = {
		1,  9, 17, 25, 33, 41, 49, 57, 65, 73, 80, 87,  94, 101, 108, 115, 122,
		2, 10, 18, 26, 34, 42, 50, 58, 66, 74, 81, 88,  95, 102, 109, 116, 123,
		3, 11, 19, 27, 35, 43, 51, 59, 67, 75, 82, 89,  96, 103, 110, 117, 124,
		4, 12, 20, 28, 36, 44, 52, 60, 68, 76, 83, 90,  97, 104, 111, 118, 125,
		5, 13, 21, 29, 37, 45, 53, 61, 69, 77, 84, 91,  98, 105, 112, 119, 126,
		6, 14, 22, 30, 38, 46, 54, 62, 70, 78, 85, 92,  99, 106, 113, 120, 127,
		7, 15, 23, 31, 39, 47, 55, 63, 71, 79, 86, 93, 100, 107, 114, 121, 128,
		8, 16, 24, 32, 40, 48, 56, 64, 72
	}
	
	-- ... and the other way around
	self.tVerticalToHorizontal = {}
	for hor,vert in ipairs(self.tHorizontalToVertical) do
		self.tVerticalToHorizontal[vert] = hor
	end	
end


	--[[ Controller "pending operations" interface --]]

function Sort:HasPendingOperations()
	return self:GetPendingOperationCount() > 0
end

function Sort:GetPendingOperationCount()
	local tCurrentSlots = self:GetBankTabVirtual()
	
	-- Run through list of sorted items, compare sorted with current ItemId for each slot	
	-- For speed, first build map of current slot idx -> itemId
	local tCurrentItemIds = {}
	for _,tSlot in pairs(tCurrentSlots) do
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
	local tCurrent = self:GetBankTabVirtual()
	table.sort(tCurrent, Sort.TableSortComparator)

	-- Insert first between Family, then Category, then Type until we run out of blanks
	fInsertionComparators = {Sort.Comparator_Family, Sort.Comparator_Category, Sort.Comparator_Type}
	for i,f in ipairs(fInsertionComparators) do
		local blanks = nil
		blanks = Sort:DistributeBlanksSingle(tCurrent, GBT:GetBankTabSlots(), f, blanks) 
	end	

	-- After distributing spaces, realign indices on all contained slots' .nIndex with new sorted-index
	for newIndex,entry in pairs(tCurrent) do		
		entry.nIndex = newIndex
	end
	
	-- Store result in self-variable
	self.tSortedSlots = tCurrent
end

function Sort:DistributeBlanksSingle(tEntries, nBankSlots, fComparator, nBlanks)
	-- How many blank slots are there?
	nBlanks = nBlanks or nBankSlots-#tEntries	
	
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
				and fComparator(Sort, cur, nxt) ~= nil -- Comparator think's the items are different
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
end

-- Main module operation
function Sort:Execute()	
	
	-- All current bank slots, prior to sort operation
	local tCurrentSlots = self:GetBankTabVirtual()
	
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
						[self:GetRealIndex(tSortedTargetSlot.nIndex)] = {true, false}, 
						[self:GetRealIndex(tSourceSlot.nIndex)] = {true, false}
					})
				else				
					-- Move fires bRemoved=true for source, bRemoved=false for target
					self.Controller:SetPendingEvents(self.Controller.enumModules.Sort, {
						[self:GetRealIndex(tSortedTargetSlot.nIndex)] = {false}, 
						[self:GetRealIndex(tSourceSlot.nIndex)] = {true}
					})
				end
				
				--Print(string.format("Moving '%s' from index [%d] to [%d]",  tSourceSlot.itemInSlot:GetName(), self:GetRealIndex(tSourceSlot.nIndex), self:GetRealIndex(tSortedTargetSlot.nIndex)))

				-- Pulse both source and target
				local GB = Apollo.GetAddon("GuildBank")
				if GB ~= nil then
					local bankwnds = GB.tWndRefs.tBankItemSlots
					bankwnds[self:GetRealIndex(tSourceSlot.nIndex)]:TransitionPulse()
					bankwnds[self:GetRealIndex(tSortedTargetSlot.nIndex)]:TransitionPulse()
				end	
				
				-- Fire off the update by beginning and ending the bank transfer from source to target.
				tSourceSlot.nIndex = self:GetRealIndex(tSourceSlot.nIndex)
				GBT.guildOwner:BeginBankItemTransfer(tSourceSlot.itemInSlot, tSourceSlot.itemInSlot:GetStackCount())
				
				-- Will trigger OnGuildBankItem x2, one for target (items picked up), one for target (items deposited)
				GBT.guildOwner:EndBankItemTransfer(GBT.nCurrentTab, self:GetRealIndex(tSortedTargetSlot.nIndex))
				
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

function Sort:Comparator_Type(tSlotA, tSlotB)
	-- Family (Crafting, Schematic etc)
	return self:CompareValues(
		tSlotA.itemInSlot:GetItemType(), 
		tSlotB.itemInSlot:GetItemType())
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

function Sort:Comparator_Quality(tSlotA, tSlotB)
	return Sort:CompareValues(
		tSlotA.itemInSlot:GetItemQuality(), 
		tSlotB.itemInSlot:GetItemQuality())
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


	--[[ Vertical / horizontal index translation --]]
	
function Sort:GetVirtualIndex(nRealIndex)
	if self.tSettings.eDirection == self.enumDirection.Vertical then
		return self.tHorizontalToVertical[nRealIndex]
	else
		return nRealIndex
	end
end

function Sort:GetRealIndex(nVirtualIndex)
	if self.tSettings.eDirection == self.enumDirection.Vertical then
		return self.tVerticalToHorizontal[nVirtualIndex]
	else
		return nVirtualIndex
	end	
end

function Sort:GetBankTabVirtual()	
	local tCurrent = GBT:GetBankTab()
	
	if self.tSettings.eDirection == self.enumDirection.Vertical then
		local tRemapped = {}
		for idx,tSlot in pairs(tCurrent) do
			tSlot.nIndex = self:GetVirtualIndex(tSlot.nIndex)
			tRemapped[#tRemapped+1] = tSlot

		end
		return tRemapped
	else
		-- Horizontal (default layout)
		return tCurrent
	end
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
			
			local tSortedSlot = Sort.tSortedSlots[Sort:GetVirtualIndex(i)]
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