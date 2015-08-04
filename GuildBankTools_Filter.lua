--[[
	Filter controller controller.
--]]

local Filter = {}
local GBT = Apollo.GetAddon("GuildBankTools")

Filter.enumModules = {
	Search = "Search",
	Usable = "Usable",
}

function Filter:Initialize()
	-- Load and intialize modules
	self.tModules = {}
	for eModule,_ in pairs(self.enumModules) do
		self.tModules[eModule] = Apollo.GetPackage("GuildBankTools:Module:Filter:" .. eModule).tPackage
		self.tModules[eModule]:Initialize()
	end
end

function Filter:LoadForms()
	-- Load bank-tab highlight forms
	local GB = Apollo.GetAddon("GuildBank")
	self.tTabHighlights = {}
	for n = 1,5 do
		local wndBankTab = GB.tWndRefs.wndMain:FindChild("BankTabBtn" .. n)
		self.tTabHighlights[n] = Apollo.LoadForm(GBT.xmlDoc, "TabHighlightForm", wndBankTab, self)								
	end
	
	-- Localization hack - german/french texts for "Usable items only" are considerbly longer than english ones, so reduce font-size for non-EN
	if Apollo.GetString(1) ~= "Cancel" then
		GBT:GetToolbarForm():FindChild("UsableButtonLabel"):SetFont("CRB_InterfaceTiny_BB")
	end			
end

function Filter:GetSettings()
	if self.tSettings == nil then
		self.tSettings = self:GetDefaultSettings()
	end
	return self.tSettings
end

function Filter:GetDefaultSettings()
	--Print("Filter:GetDefaultSettings")
	-- Get default settings for each module
	local tDefaultSettings = {}
	for e,m in pairs(self.tModules) do
		tDefaultSettings[e] = m:GetSettings()
	end
	
	return tDefaultSettings
end


function Filter:RestoreSettings(tSavedSettings)
	--Print("Filter:RestoreSettings")
	if tSavedSettings == nil then
		return
	end
		
	-- Pass on module-specific settings. No settings for Filter yet.
	if self.tModules ~= nil then
		for e,m in pairs(self.tModules) do
			m:RestoreSettings(tSavedSettings[e])
		end
	end
end

-- StopModueles does nothing, filter-modules are not event/progress driven but instantly applied after updating.
function Filter:StopModules() end

-- Called when changes happen from top (GBT changed tabs) or bottom (module changed settings)
function Filter:UpdateModules()

	-- Get matches for every tab
	local tMatchesOnTabs = {}
	local bAnyActiveFilters = false
	
	for nTab=1,GBT:GetBankTabCount() do		
		local tTab = {}
		tMatchesOnTabs[nTab] = tTab
		
		-- For each tab, ask each module to determine all matches
		for eModule,module in pairs(self.tModules) do
			if module:IsActive() then
				bAnyActiveFilters = true
				local tTabSlots = GBT:GetBankTab(nTab)
				tTab[eModule] = module:GetMatches(tTabSlots)
			end
		end
	end
	
	if bAnyActiveFilters then
		-- Go through matches for individual filters, and build consolidated [tab]->[(slot)->(matches)] table
		local tConsolidatedMatches = {}
		local tTabMatchCounter = {}
		for nTab,tMatchesOnTab in pairs(tMatchesOnTabs) do -- for each tab
			local tTab = {}			
			tConsolidatedMatches[nTab] = tTab
			
			for idx=1, GBT:GetBankTabSlots() do  --(for slots 1 to 128)
				tTab[idx] = true -- Assume match
				
				for eModule,tMatchesByModule in pairs(tMatchesOnTab) do -- for every module filtering this tab
					if tMatchesByModule[idx] == nil then
						-- No match by this filter
						tTab[idx] = false
					end
				end
				
				-- Is index still considered a match, after all filters have been checked?
				if tTab[idx] == true then
					tTabMatchCounter[nTab] = (tTabMatchCounter[nTab] or 0) + 1
				end
			end
		end	

		-- Store consolidated match & counter tables in controller scope for later re-filtering
		self.tMatches = tConsolidatedMatches
		self.tTabMatchCounter = tTabMatchCounter
		
		-- Apply the match-filters for currently selected tab to the Guild Bank window
		self:ApplyFilter(tConsolidatedMatches[GBT:GetCurrentTab()])

		-- Show top hit-count indicators
		self:ShowTabCountIndicators(tTabMatchCounter)
	else
		self.tMatches = nil
		self:ClearFilter()
		self:HideTabCountIndicators()
	end
end

function Filter:ApplyFilter(tMatches)
	tMatches = tMatches or (self.tMatches and self.tMatches[GBT:GetCurrentTab()])
	
	if tMatches == nil then
		self:ClearFilter()
		return
	end
	
	local GB = Apollo.GetAddon("GuildBank")
	if GB.tWndRefs.tBankItemSlots ~= nil then
		-- Go through every bank slot and apply consolidated filter
		for idx,wnd in ipairs(GB.tWndRefs.tBankItemSlots) do
			local bShow = tMatches[idx] == true
			wnd:FindChild("BankItemIcon"):SetOpacity(bShow and GBT.enumOpacity.Visible or GBT.enumOpacity.Hidden)		
		end	
	end
end

function Filter:ClearFilter()
	local GB = Apollo.GetAddon("GuildBank")
	if GB.tWndRefs.tBankItemSlots ~= nil then
		for idx,wnd in ipairs(GB.tWndRefs.tBankItemSlots) do
			wnd:FindChild("BankItemIcon"):SetOpacity(GBT.enumOpacity.Visible)
		end	
	end
end

function Filter:ShowTabCountIndicators(tTabMatchCounter)
	tTabMatchCounter = tTabMatchCounter or self.tTabMatchCounter
	
	if tTabMatchCounter == nil then
		self:HideTabCountIndicators()
	end

	for nTab,wndHighlight in ipairs(self.tTabHighlights) do
		if tTabMatchCounter[nTab] ~= nil and tTabMatchCounter[nTab] > 0 then
			-- Set counter, and show border for non-current tabs
			if wndHighlight:FindChild("Counter") ~= nil then
				wndHighlight:FindChild("Counter"):SetText(tTabMatchCounter[nTab])
			end
			--wndHighlight:FindChild("Border"):Show(GBT:GetCurrentTab() ~= nTab)

			-- Show highlight frame
			wndHighlight:Show(true)
			
		else
			wndHighlight:Show(false)
		end
	end
end

function Filter:HideTabCountIndicators()
	if self.tTabHighlights ~= nil then
		for nTab,wndHighlight in ipairs(self.tTabHighlights) do
			wndHighlight:Show(false)
		end
	end
end

Apollo.RegisterPackage(Filter, "GuildBankTools:Controller:Filter", 1, {}) 
