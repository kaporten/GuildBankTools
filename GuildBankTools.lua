--[[
	GuildBankTools by porten. 
	Comments/suggestions/questions? Find me on Curse or porten@gmail.com.
--]]

require "Apollo"
require "Window"

-- Addon class itself
local Major, Minor, Patch = 3, 0, 0
local GuildBankTools = {}

-- Ref to the GuildBank addon
local GB

-- Opacity levels to use when highlighting items
GuildBankTools.enumOpacity = {
	Hidden = 0.2,
	Visible = 1
}

-- Asynchronous event-driven operation types
-- Key = Operation name
GuildBankTools.enumOperations = {
	Stack = "Stack",
	Sort = "Sort"
}	

function GuildBankTools:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

function GuildBankTools:Init()
	-- Only actually load GuildBankTools if it is not already loaded
	-- This is to prevent double-loads caused by "guildbanktools" vs "GuildBankTools" dir renames
	if Apollo.GetAddon("GuildBankTools") ~= nil then
		return
	end

	-- Ensure tSettings table always exist, even if there are no saved settings
	self.tSettings = self.tSettings or {}
	
	-- Default value for throttle, used when async event-operations such as stack/sort needs to be taken down a notch in speed (due to busy bank)
	self.nThrottleTimer = 0
	
	-- Initially, no operations are in progress. Explicitly register "false" for all.
	self.tInProgress = {}
	for e,_ in pairs(GuildBankTools.enumOperations) do
		self.tInProgress[e] = false
	end
	
	Apollo.RegisterAddon(self, false, "GuildBankTools", {"GuildBank", "GuildAlerts"})	
end

function GuildBankTools:OnLoad()	
	-- Store ref for Guild Bank
	GB = Apollo.GetAddon("GuildBank")	
	if GB == nil then
		Print("GuildBankTools startup aborted: required addon 'GuildBank' not found!")
		return
	end

	-- Register for bank-tab updated events
	Apollo.RegisterEventHandler("GuildBankTab", "OnGuildBankTab", self) -- Guild bank tab opened/changed.
	Apollo.RegisterEventHandler("GuildBankItem", "OnGuildBankItem", self) -- Guild bank tab contents changed.

	-- Load form for later use
	self.xmlDoc = XmlDoc.CreateFromFile("GuildBankTools.xml")
	
	-- Hook into GuildBank to react to main-tab changes (not bank-vault tab changes, but f.ex. changing to the Money or Log tab)
	self.Orig_GB_OnBankTabUncheck = GB.OnBankTabUncheck
	GB.OnBankTabUncheck = self.Hook_GB_OnBankTabUncheck	
	
	-- Hook into GuildAlerts to suppress the "guild bank busy" log message / throttle speed when it occurs
	local GA = Apollo.GetAddon("GuildAlerts")
	self.Orig_GA_OnGuildResult = GA.OnGuildResult
	GA.OnGuildResult = self.Hook_GA_OnGuildResult	
	
	-- Register with addon "OneVersion"
	Event_FireGenericEvent("OneVersion_ReportAddonInfo", "GuildBankTools", Major, Minor, Patch)
end

function GuildBankTools:Hook_GB_OnBankTabUncheck(wndHandler, wndControl)	
	-- NB: In this hooked context "self" is GuildBank, not GuildBankTools, so grab a ref to GuildBankTools
	local GBT = Apollo.GetAddon("GuildBankTools")
	
	-- First, let GuildBank handle the call fully
	GBT.Orig_GB_OnBankTabUncheck(GB, wndHandler, wndControl)
	
	-- Then, determine if the toolbar should be shown or hidden
	if GBT.wndOverlayForm ~= nil then
		-- If UN-checked tab is the bank vault tab, hide the toolbar
		if wndControl:GetName() == "BankTabBtnVault" then
			GBT.wndOverlayForm:Show(false)
		else
			GBT.wndOverlayForm:Show(true)
		end
	end
end

function GuildBankTools:Hook_GA_OnGuildResult(guildSender, strName, nRank, eResult)	
	-- NB: In this hooked context "self" is GuildAlerts, not GuildBankTools, so grab a ref to GuildBankTools
	local GBT = Apollo.GetAddon("GuildBankTools")	
	
	if eResult ~= GuildLib.GuildResult_Busy then
		-- Not the busy-signal, just let GuildAlerts handle whatever it is as usual
		GBT.Orig_GA_OnGuildResult(self, guildSender, strName, nRank, eResult)
	else
		-- Bank complains that it's busy (due to sort/stack spam)
		-- Is it me spamming? (is there an in-progress operation?)
		local eOperationInProgress = GBT:GetInProgressOperation()
	
		if eOperationInProgress ~= nil then
			-- Yep, GuildBankTools is spamming
			-- "Eat" the busy signal event, engage throttle, and continue the operation
			GBT.nThrottleTimer = 1
			GBT:ExecuteThrottledOperation(eOperationInProgress)		
		else
			-- Something else did this, pass the signal on to GuildAlerts
			GBT.Orig_GA_OnGuildResult(self, guildSender, strName, nRank, eResult)
		end
	end
end


-- Whenever bank tab is changed, interrupt stacking (if it is in progress) and calc stackability
function GuildBankTools:OnGuildBankTab(guildOwner, nTab)	
	-- First-hit form loading when the items (vault) tab is shown	
	if GB ~= nil and self.xmlDoc ~= nil and (self.wndOverlayForm == nil or GB.tWndRefs.wndMain:FindChild("GuildBankToolsForm") == nil) then
		self.wndOverlayForm = Apollo.LoadForm(self.xmlDoc, "GuildBankToolsForm", GB.tWndRefs.wndMain, self)					
		
		-- Restore usable-items-only checkbox to previously saved state from tSettings
		if self.tSettings.bUsableOnly ~= nil then			
			self.wndOverlayForm:FindChild("UsableButton"):SetCheck(self.tSettings.bUsableOnly)
		end
		
		-- Load bank-tab highlight forms
		self.tTabHighlights = {}
		for n = 1,5 do
			local wndBankTab = GB.tWndRefs.wndMain:FindChild("BankTabBtn" .. n)
			self.tTabHighlights[n] = Apollo.LoadForm(self.xmlDoc, "TabHighlightForm", wndBankTab, self)								
		end
		
		-- Localization hack - german/french texts for "Usable items only" are considerbly longer than english ones, so reduce font-size for non-EN
		if Apollo.GetString(1) ~= "Cancel" then
			self.wndOverlayForm:FindChild("UsableButtonLabel"):SetFont("CRB_InterfaceTiny_BB")
		end
	end

	-- Store refs to current visible tab and guild
	self.nCurrentTab = nTab
	self.guildOwner = guildOwner
	
	-- Changed tab, interrupt any in-progress stacking
	self:StopAllOperations()
	
	
	-- Calculate list of stackable items
	self:IdentifyStackableItems()
		
	-- Calculate sorted list of items
	self.GBT_Sort:CalculateSortedList(guildOwner, nTab)
	self.GBT_Sort:UpdateSortButton()
	
	-- Then highlight any search criteria matches
	self:HighlightSearchMatches()
end


-- React to bank changes by re-calculating stackability
-- If stacking is in progress, mark progress on the current stacking (pendingStackEvents)
-- Each stacked item will produce 2 GuildBankItem events, and stacking of next item cannot
-- proceed until both events are received.
function GuildBankTools:OnGuildBankItem(guildOwner, nTab, nInventorySlot, itemUpdated, bRemoved)
	-- Ignore events if toolbar is not visible 
	-- (don't bother updating if people change stuff while you're not at the bank)
	if self.wndOverlayForm == nil or self.wndOverlayForm:FindChild("ContentArea") == nil or (not self.wndOverlayForm:FindChild("ContentArea"):IsShown()) then
		return
	end
		
	-- Re-calculate stackable items list
	self:IdentifyStackableItems()
	
	-- Re-calculate sorted list of items
	self.GBT_Sort:CalculateSortedList(guildOwner, nTab)	
	self.GBT_Sort:UpdateSortButton()
	
	-- Is any operation in progress?
	local eOperationInProgress = self:GetInProgressOperation()
	
	if eOperationInProgress ~= nil then
		-- Remove pending event from list of expected events for in-progress operation
		self:RemovePendingGuildBankEvent(eOperationInProgress, nInventorySlot, bRemoved)
		
		-- All events handled? If so, fire off next pass of sort/stack
		if self:HasPendingGuildBankEvents(eOperationInProgress) == false then
			self:ExecuteThrottledOperation(eOperationInProgress)
		end
	end
	
	-- Once all real processing is done, update the filtering if needed
	self:HighlightSearchMatches()	
end


--[[ Control of in-progress operations --]]

function GuildBankTools:StopOperation(eOperation)
	self.tInProgress[eOperation] = nil
end

-- Doesn't actually start anything, but registers something as started.
-- 2nd and 3rd parameters are object.function for repeated calls once all "must wait for" events have been received
function GuildBankTools:StartOperation(eOperation, tObject, strOperation)
	self.tInProgress[eOperation] = {tObject = tObject, strOperation = strOperation}
end

function GuildBankTools:ExecuteThrottledOperation(eOperation)
	-- Start timer
	self.timerOperation = ApolloTimer.Create(self.nThrottleTimer + 0.0, false, self.tInProgress[eOperation].strOperation, self.tInProgress[eOperation].tObject)
	
	-- Decrease throttled delay by 0.25 sec for next pass
	self.nThrottleTimer = self.nThrottleTimer > 0 and self.nThrottleTimer-0.25 or 0
end


--[[ Delegate methods for async operations --]]

function GuildBankTools:Sort()
	self.GBT_Sort:Sort()
end



function GuildBankTools:StopAllOperations()
	-- Set kill-flag for all operations
	for eOperation, bInProgress in pairs(self.tInProgress) do
		self:StopOperation(eOperation)
	end
end

function GuildBankTools:IsOperationInProgress(eOperation)
	return self.tInProgress[eOperation]
end

function GuildBankTools:GetInProgressOperation()
	-- Just return first-hit operation, stopping an operation removes it from the list,
	-- so the assumption is that self.tInProgress is {} or has exactly 1 k/v pair.
	for eOperation, fOperation in pairs(self.tInProgress) do
		return eOperation
	end
end


--[[ Control of pending events for asynchronous operation --]]

function GuildBankTools:SetPendingEvents(eOperation, tPendingEvents)	
	self.tPendingEvents = self.tPendingEvents or {}
	self.tPendingEvents[eOperation] = tPendingEvents
end

function GuildBankTools:RemovePendingGuildBankEvent(eOperation, nUpdatedInventorySlot, bRemoved)
	self.tPendingEvents = self.tPendingEvents or {}
	self.tPendingEvents[eOperation] = self.tPendingEvents[eOperation] or {}
	
	local tPendingForOperation = self.tPendingEvents[eOperation]
	
	if tPendingForOperation ~= nil and type(tPendingForOperation[nUpdatedInventorySlot]) == "table" then
		local tPending = tPendingForOperation[nUpdatedInventorySlot]
		for i,b in ipairs(tPending) do
			if b == bRemoved then				
				table.remove(tPending, i)
			end
			
			if #tPending == 0 then
				tPendingForOperation[nUpdatedInventorySlot] = nil
			end
		end
	end
end

function GuildBankTools:HasPendingGuildBankEvents(eOperation)
	if self.tPendingEvents == nil or self.tPendingEvents[eOperation] == nil then return
		false
	end
	
	for k,v in pairs(self.tPendingEvents[eOperation]) do
		return true
	end
	
	return false
end


function GuildBankTools:GetCurrentTabSlots()
	return self.guildOwner:GetBankTab(self.nCurrentTab)
end

function GuildBankTools:GetCurrentTabSize()
	return self.guildOwner:GetBankTabSlots()
end


--[[ Settings save/restore --]]
-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function GuildBankTools:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Simply save the entire tSettings structure
	return self.tSettings
end

-- Restore addon config per character. Called by engine when loading UI.
function GuildBankTools:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Restored savedata are just stored directly as tSettings
	self.tSettings = tSavedData
end


-- Standard addon initialization
GuildBankToolsInst = GuildBankTools:new()
GuildBankToolsInst:Init()
