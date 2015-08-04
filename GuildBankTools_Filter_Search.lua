--[[
	Filter:Search module.
--]]

local Search = {}
local GBT = Apollo.GetAddon("GuildBankTools")

function Search:Initialize()
end

function Search:IsActive()
	-- Extract search string
	local strSearch = GBT:GetToolbarForm():FindChild("SearchEditBox"):GetText()
	return strSearch ~= nil and strSearch ~= ""
end

function Search:SetDefaultSettings()
	self.tSettings = {}
end

function Search:GetSettings()
	if self.tSettings == nil then
		self:SetDefaultSettings()
	end
	
	return self.tSettings
end

function Search:SetSettings(tSettings)
	-- No settings "accepted" by this module
end

-- Returns list of matches for input tab
function Search:GetMatches(tTab)
	-- Extract search string
	local strSearch = GBT:GetToolbarForm():FindChild("SearchEditBox"):GetText()
	
	-- Any search criteria present?
	local bSearch = false
	if strSearch ~= nil and strSearch ~= "" then
		strSearch = strSearch:lower()	
		bSearch = true
	end
	
	local tMatches = {}	
	for _,tSlot in pairs(tTab) do		
		if bSearch then
			-- Search string present, name must match string
			if self:IsMatch(tSlot, strSearch) then
				tMatches[tSlot.nIndex] = tSlot
			end
		else
			-- No search criteria, everything matches
			tMatches[tSlot.nIndex] = tSlot
		end
	end
	
	return tMatches
end

-- Determines if a single slot is a search-match
function Search:IsMatch(tSlot, strSearch)
	if tSlot == nil or tSlot.itemInSlot == nil then
		return false
	end
	
	return string.match(tSlot.itemInSlot:GetName():lower(), strSearch) ~= nil
end


	--[[ React to changes to the search editbox --]]
	
function GBT:OnSearchEditBox_EditBoxChanged(wndHandler, wndControl, strText)
	-- Show or hide Clear button
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	if strSearch ~= nil and strSearch ~= "" then
		GBT:GetToolbarForm():FindChild("ClearSearchButton"):Show(true)
	else
		GBT:GetToolbarForm():FindChild("ClearSearchButton"):Show(false)
	end
	
	-- Tell Filter-controller that settings have changed for this module
	Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage:UpdateModules()
end

function GBT:OnClearSearchButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	-- Clicking the clear-button drops focus, clears text and hides the button
	GBT:GetToolbarForm():FindChild("SearchEditBox"):SetText("")
	GBT:GetToolbarForm():FindChild("SearchEditBox"):ClearFocus()
	GBT:GetToolbarForm():FindChild("ClearSearchButton"):Show(false)
	
	-- Tell Filter-controller that settings have changed for this module
	Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage:UpdateModules()	
end


Apollo.RegisterPackage(Search, "GuildBankTools:Module:Filter:Search", 1, {}) 