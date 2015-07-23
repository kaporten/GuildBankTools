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

-- Enum of modules to load. Each module is expected to conform to the same interface (Enable, Disable, Execute
GuildBankTools.enumModules = {
	Stack = "Stack",
	Sort = "Sort",
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
	
	Apollo.RegisterAddon(self, false, "GuildBankTools", {"GuildBank", "GuildAlerts"})	
end

function GuildBankTools:OnLoad()
	-- Load sub-modules
	self.tModules = {}
	for m,_ in pairs(GuildBankTools.enumModules) do
		self.tModules[m] = Apollo.GetPackage("GuildBankTools:" .. m).tPackage
	end
	
	-- Ensure tSettings table always exist, even if there are no saved settings
	self.tSettings = self.tSettings or {}
	
	-- Default value for throttle, used when async event-operations such as stack/sort needs to be taken down a notch in speed (due to busy bank)
	self.nThrottleTimer = 2
	
	-- Initially, no operations are in progress. Explicitly register "false" for all.
	self.tInProgress = {}
	for e,_ in pairs(GuildBankTools.enumModules) do
		self.tInProgress[e] = false
	end

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
		local eModuleInProgress = GBT:GetInProgressModule()
	
		if eModuleInProgress ~= nil then
			-- Yep, GuildBankTools is spamming
			-- "Eat" the busy signal event, engage throttle, and continue the operation
			GBT.nThrottleTimer = 1
			GBT:ExecuteThrottledOperation(eModuleInProgress)		
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
	
	-- Changed tab, interrupt any in-progress operations
	local eInProgress = self:GetInProgressModule()
	if eInProgress ~= nil then 
		self:StopModule(eInProgress)
	end
	
	-- Initially disable all modules after tab-change (dead buttons)
	for eModule,module in pairs(self.tModules) do
		module:Disable()
	end

	-- Calculate list of stackable & sortable items
	self.tModules.Stack:IdentifyStackableItems()
	self.tModules.Sort:CalculateSortedList()
	
	-- Re-enable modules (enable buttons)
	for eModule,module in pairs(self.tModules) do
		Print("tab-change-enabling" .. eModule)
		module:Enable(false) -- None are in progress
	end	
	
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
	
	-- Is any module in progress?
	local eModuleInProgress = self:GetInProgressModule()
	
	if eModuleInProgress == nil then
		-- User, or some other guildie modified guild bank (since I'm not doing anything... intentionally at least)
		-- So just recalculate state, modules will be enabled (button updated) after this if/else block
		self.tModules.Stack:IdentifyStackableItems()
		self.tModules.Sort:CalculateSortedList()
		
		for eModule,module in pairs(self.tModules) do
			Print("unexpected event-enabling")
			module:Enable(false) 
		end				
	else
		-- Remove pending event from list of expected events for in-progress operation
		local bMatched = self:RemovePendingGuildBankEvent(eModuleInProgress, nInventorySlot, bRemoved)
		
		if not bMatched then
			-- Uh-oh... this event was not meant for me. Stop in-progress module then.
			self:StopModule(eModuleInProgress)
	
			-- Re-calculate stack/sort lists
			self.tModules.Stack:IdentifyStackableItems()
			self.tModules.Sort:CalculateSortedList()		
		else
			-- Event was expected. Are we waiting for more events?
			if self:HasPendingGuildBankEvents(eModuleInProgress) == false then
				-- All partial events received, recalculate
				self.tModules.Stack:IdentifyStackableItems()
				self.tModules.Sort:CalculateSortedList()		

				self:ExecuteThrottledOperation(eModuleInProgress)
			end
		end
		
		-- Re-enable in-progress module (update button)
		for eModule,module in pairs(self.tModules) do
			if eModule == eModuleInProgress then
				Print("event re-enabling" .. eModule)
				module:Enable(true) 
			end
		end			
	end
	
	-- Once all real processing is done, update the filtering if needed
	self:HighlightSearchMatches()	
end


--[[ Control of in-progress operations --]]


function GuildBankTools:StopModule(eModule)
	self.tInProgress[eModule] = false
	
	-- When stopping a module, all modules can be enabled again
	for e,module in pairs(self.tModules) do	
		module:Enable(false)
	end	
end


function GuildBankTools:StartModule(eModule)
	
	-- When starting a module, all other modules must be stoppend and disabled
	for e,module in pairs(self.tModules) do	
		if eModule ~= e then	
			self:StopModule(e)
			module:Disable()
		end
	end

	self.tInProgress[eModule] = true
	
	-- After stopping/disabling everything (else), enable the one which was just started
	for e,module in pairs(self.tModules) do	
		if eModule == e then
			Print("Start-enabling " .. eModule)
			module:Enable(true)
		end
	end
	
	-- Call the async :Execute() operation for this module
	self:ExecuteThrottledOperation(eModule)
end

function GuildBankTools:GetInProgressModule()
	for eModule,bInProgress in pairs(self.tInProgress) do
		if bInProgress then
			return eModule
		end
	end
end

function GuildBankTools:IsInProgress(eModule)
	return self:GetInProgressModule() == eModule	
end


function GuildBankTools:ExecuteThrottledOperation(eModule)
	-- Start timer
	self.timerOperation = ApolloTimer.Create(self.nThrottleTimer + 0.0, false, "Execute", self.tModules[eModule])
	
	-- Decrease throttled delay by 0.25 sec for next pass
	self.nThrottleTimer = self.nThrottleTimer > 0 and self.nThrottleTimer-0.25 or 0
end




--[[ Control of pending events for asynchronous operation --]]

function GuildBankTools:SetPendingEvents(eModule, tPendingEvents)	
	self.tPendingEvents = self.tPendingEvents or {}
	self.tPendingEvents[eModule] = tPendingEvents
end

function GuildBankTools:RemovePendingGuildBankEvent(eModule, nUpdatedInventorySlot, bRemoved)
	self.tPendingEvents = self.tPendingEvents or {}
	self.tPendingEvents[eModule] = self.tPendingEvents[eModule] or {}
	
	local tPendingForModule = self.tPendingEvents[eModule]
	local bMatch = false
	
	if tPendingForModule ~= nil and type(tPendingForModule[nUpdatedInventorySlot]) == "table" then
		local tPending = tPendingForModule[nUpdatedInventorySlot]
		for i,b in ipairs(tPending) do
			if b == bRemoved then				
				table.remove(tPending, i)
				bMatch = true
			end
			
			if #tPending == 0 then
				tPendingForModule[nUpdatedInventorySlot] = nil
			end
		end
	end
	
	return bMatch
end

function GuildBankTools:HasPendingGuildBankEvents(eModule)
	if self.tPendingEvents == nil or self.tPendingEvents[eModule] == nil then return
		false
	end
	
	for k,v in pairs(self.tPendingEvents[eModule]) do
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
