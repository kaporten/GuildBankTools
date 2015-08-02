--[[
	GuildBankTools by porten. 
	Comments/suggestions/questions? Find me on Curse or porten@gmail.com.
--]]

require "Apollo"
require "Window"


	--[[ Globals and enums --]]

-- Addon class itself
local Major, Minor, Patch = 4, 0, 0
local GuildBankTools = {}

-- Ref to the GuildBank addon
local GB

-- Opacity levels to use when highlighting items
GuildBankTools.enumOpacity = {
	Hidden = 0.2,
	Visible = 1
}

GuildBankTools.enumModuleTypes = {
	Arrange = "Arrange",
	Filter = "Filter",
}


	--[[ Addon initialization --]]

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
	
	Apollo.RegisterAddon(self, true, "GuildBankTools", {"GuildBank", "GuildAlerts"})	
end

function GuildBankTools:OnDependencyError(strDep, strErr)
	-- GuildAlerts is optional (optionally used by Arrange-modules)
	if strDep == "GuildAlerts" then
		return true
	end	
	
	-- All other missing dependencies (ie., just "GuildBank") should cause the addon to fail loading
	return false
end

-- Addon being loaded
function GuildBankTools:OnLoad()
	
	-- Ensure tSettings table always exist, even if there are no saved settings
	self.tSettings = self.tSettings or {}
	for e,_ in pairs(self.enumModuleTypes) do
		self.tSettings[e] = self.tSettings[e] or {}
	end

	self.tModuleControllers = {}
	for e,_ in pairs(self.enumModuleTypes) do
		self.tModuleControllers[e] = Apollo.GetPackage("GuildBankTools:Controller:" .. e).tPackage
		self.tModuleControllers[e]:Initialize()				
		self.tModuleControllers[e]:SetSettings(self.tSettings[e])		
	end
	

	-- Store ref for Guild Bank
	GB = Apollo.GetAddon("GuildBank")	
	if GB == nil then
		-- GuildBank missing should've triggered a dependency error, but it doesn't hurt to check again
		Print("GuildBankTools startup aborted: required addon 'GuildBank' not found!")
		return
	end

	-- Register for bank-tab updated events
	Apollo.RegisterEventHandler("GuildBankTab", "OnGuildBankTab", self) -- Guild bank tab opened/changed.
	Apollo.RegisterEventHandler("GuildBankItem", "OnGuildBankItem", self) -- Guild bank tab contents changed.

	-- Load form file. Toolbar is created from loaded file when GB hooked functions are called.
	self.xmlDoc = XmlDoc.CreateFromFile("GuildBankTools.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	-- Hook into GuildBank to react to main-tab changes (not bank-vault tab changes, but f.ex. changing to the Money or Log tab)
	self.Orig_GB_OnBankTabUncheck = GB.OnBankTabUncheck
	GB.OnBankTabUncheck = self.Hook_GB_OnBankTabUncheck	

	-- Hook into GuildBank to react to bank-tab changes
	self.Orig_GB_OnGuildBankTab = GB.OnGuildBankTab
	GB.OnGuildBankTab = self.Hook_GB_OnGuildBankTab
	
	-- Register with addon "OneVersion"
	Event_FireGenericEvent("OneVersion_ReportAddonInfo", "GuildBankTools", Major, Minor, Patch)
end

function GuildBankTools:OnDocLoaded()
	-- Load settings form
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
		self.wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
		if self.wndSettings == nil then			
			Apollo.AddAddonErrorText(self, "Could not load the Settings form.")
			return
		end		
		self.wndSettings:Show(false, true)
		
		-- Restore settings		
		if self.tSettings.Arrange.Sort.eDirection == "Vertical" then
			self.wndSettings:FindChild("DirectionVertical"):SetCheck(true)
		else
			self.wndSettings:FindChild("DirectionHorizontal"):SetCheck(true)
		end
	end
end


	--[[ Guild bank tab change hooks --]]

-- Individual Bank tab selected
function GuildBankTools:Hook_GB_OnGuildBankTab(guildOwner, nTab)
	--Print("OnGuildBankTab:" .. nTab)
	-- NB: In this hooked context "self" is GuildBank, not GuildBankTools, so grab a ref to GuildBankTools
	local GBT = Apollo.GetAddon("GuildBankTools")

	-- First, let GuildBank handle the call fully
	GBT.Orig_GB_OnGuildBankTab(GB, guildOwner, nTab)
	
	-- Store refs to currently selected guild and tab
	GBT.guildOwner = guildOwner
	GBT.nCurrentTab = nTab

	-- First-hit form loading when the Bank tab is shown
	local bIsFormLoaded = GBT.wndOverlayForm ~= nil and GB.tWndRefs.wndMain:FindChild("GuildBankToolsForm") ~= nil
	if not bIsFormLoaded and GBT.xmlDoc ~= nil then	
		-- Load overlayform with GuildBank's "wndMain" as parent window, and self as owner (event recipient)
		GBT.wndOverlayForm = Apollo.LoadForm(GBT.xmlDoc, "GuildBankToolsForm", GB.tWndRefs.wndMain, GBT)					
		
		-- (re-)load all module-forms and trigger settings update
		if GBT.tModuleControllers ~= nil then
			for e,c in pairs(GBT.tModuleControllers) do
				c:LoadForms()
				c:SetSettings(GBT.tSettings[e])	
			end
		end
	end
		
	-- Stop any in-progress modules, and update their status
	for eModuleType, controller in pairs(GBT.tModuleControllers) do
		controller:StopModules()
		controller:UpdateModules()
	end	
end

-- Top Guild tab changes, eg. Money/Bank/Bank Permissions/Bank Management/Log.
-- Hooked so that toolbar can be hidden when moving away from the Bank tab
function GuildBankTools:Hook_GB_OnBankTabUncheck(wndHandler, wndControl)
	--Print("Hook_GB_OnBankTabUncheck")
	-- NB: In this hooked context "self" is GuildBank, not GuildBankTools, so grab a ref to GuildBankTools
	local GBT = Apollo.GetAddon("GuildBankTools")

	-- First, let GuildBank handle the call fully
	GBT.Orig_GB_OnBankTabUncheck(GB, wndHandler, wndControl)
	
	-- Stop any running modules
	if GBT.tModuleControllers ~= nil then
		for eModuleType, controller in pairs(GBT.tModuleControllers) do
			controller:StopModules()
		end
	end
		
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


	--[[ Item changed in guildbank --]]
	
function GuildBankTools:OnGuildBankItem(guildOwner, nTab, nInventorySlot, itemUpdated, bRemoved)
	-- Ignore events if toolbar is not visible 
	-- (don't bother updating if people change stuff while you're not at the bank)
	if self.wndOverlayForm == nil or self.wndOverlayForm:FindChild("ContentArea") == nil or (not self.wndOverlayForm:FindChild("ContentArea"):IsShown()) then
		return
	end
	
	-- Shorthands to Arrange/Filter controllers
	
	-- Check if any Arrange module is in progress
	local Arrange = self.tModuleControllers[self.enumModuleTypes.Arrange]
	local Filter = self.tModuleControllers[self.enumModuleTypes.Filter]
	
	local eModuleInProgress = Arrange:GetInProgressModule()
	
	if eModuleInProgress == nil then
		-- User, or some other guildie modified guild bank (since I'm not doing anything... intentionally at least)
		-- Stop any in-progress activities, and update all modules
		for _,controller in pairs(self.tModuleControllers) do
			controller:StopModules()
			controller:UpdateModules()
		end
	else
		-- Some Arrange-operation is in progress...
		-- Remove pending event from list of expected events for in-progress operation
		local bMatched = Arrange:RemovePendingEvent(eModuleInProgress, nInventorySlot, bRemoved)
		
		if not bMatched then
			-- Uh-oh... this event was not meant for me. Stop, drop and roll.
			for _,controller in pairs(self.tModuleControllers) do
				controller:StopModules()
				controller:UpdateModules()
			end
		else
			-- Event was expected. Are we waiting for more events?
			if Arrange:HasPendingEvents(eModuleInProgress) == false then
				-- Nope, last event for this operation just received
				
				-- Update all modules (recalculate stackables/sortables/apply filters etc)
				for _,controller in pairs(self.tModuleControllers) do
					controller:UpdateModules()
				end			
				
				-- Schedule next execution
				Arrange:ScheduleExecution(eModuleInProgress)					
			end
		end
	end
end
	

	--[[ Utility functions --]]

function GuildBankTools:GetToolbarForm()
	return self.wndOverlayForm
end

-- Gets tab content for specified tab (default to current tab)
function GuildBankTools:GetBankTab(nTab)
	return self.guildOwner:GetBankTab(nTab and nTab or self.nCurrentTab)
end

-- Get number of slots available on each tank tab
function GuildBankTools:GetBankTabSlots()
	return self.guildOwner:GetBankTabSlots()
end

-- Get number of available bank tabs
function GuildBankTools:GetBankTabCount()
	return self.guildOwner:GetBankTabCount()
end

function GuildBankTools:GetCurrentTab()
	return self.nCurrentTab
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
	
	-- Read settings for each controller
	local tSettings = {}
	for e,_ in pairs(self.enumModuleTypes) do
		tSettings[e] = tSavedData[e] or {}		
	end
		
	self.tSettings = tSettings
end


	--[[ UI events --]]
	
function GuildBankTools:OnSettingsButton(wndHandler, wndControl, eMouseButton)
	-- Toggle settings visibility
	if self.wndSettings:IsShown() then
		self:OnCloseSettingsButton()
	else
		self:OnConfigure()
	end
end

function GuildBankTools:OnConfigure()
	self.wndSettings:Show(true, true)
	self.wndSettings:ToFront()
end

function GuildBankTools:OnCloseSettingsButton()
	self.wndSettings:Show(false, true)
end



-- Standard addon initialization
GuildBankTools:Init()
