--[[
	Filter:Usable module.
--]]

local Usable = {}
local GBT = Apollo.GetAddon("GuildBankTools")

function Usable:Initialize()
	self.tSettings = self.tSettings or {}
end

function Usable:IsActive()
	return self.tSettings.bEnabled == true
end

function Usable:SetSettings(tSettings)
	self.tSettings = tSettings
	
	-- Form may not have been loaded when this happens
	if GBT:GetToolbarForm() ~= nil and GBT:GetToolbarForm():FindChild("UsableButton") ~= nil then
		GBT:GetToolbarForm():FindChild("UsableButton"):SetCheck(self.tSettings.bEnabled == true)
	end
end

-- Returns list of matches for input tab
function Usable:GetMatches(tTab)
	-- Extract search string
	local strSearch = GBT:GetToolbarForm():FindChild("SearchEditBox"):GetText()
	
	-- Is the Usable checkbox checked? search criteria present?
	local bPerformUsableCheck = GBT:GetToolbarForm():FindChild("UsableButton"):IsChecked()
	
	local tMatches = {}	
	for _,tSlot in pairs(tTab) do		
		if bPerformUsableCheck then
			-- Usable-only checked, check if item is usable
			if self:IsMatch(tSlot) then
				tMatches[tSlot.nIndex] = tSlot
			end
		else
			-- Usable-only not checked, everything matches.
			tMatches[tSlot.nIndex] = tSlot
		end
	end
	
	return tMatches
end

function Usable:IsMatch(tSlot)
	local itemInSlot = tSlot.itemInSlot
	
	if itemInSlot == nil then 
		return true 
	end
	
	local tDetails = itemInSlot:GetDetailedInfo()
	if tDetails == nil then
		return true
	end
	
	-- Item has level requirements?
	if type(tDetails.tPrimary.tLevelRequirement) == "table" and not tDetails.tPrimary.tLevelRequirement.bRequirementMet then
		return false
	end
	
	-- Dyes and AMPs only have a "strFailure" spell property when they're already known
	if tDetails.tPrimary ~= nil and type(tDetails.tPrimary.arSpells) == "table" and #tDetails.tPrimary.arSpells == 1 and tDetails.tPrimary.arSpells[1].strFailure ~= nil then
		return false
	end
	
	-- Check item class requirement
	if tDetails.tPrimary ~= nil and type(tDetails.tPrimary.arClassRequirement) == "table" and not tDetails.tPrimary.arClassRequirement.bRequirementMet then
		return false
	end
	
	-- Weapon profficiency requirement
	if tDetails.tPrimary ~= nil and type(tDetails.tPrimary.tProfRequirement) == "table" and not tDetails.tPrimary.tProfRequirement.bRequirementMet then
		return false
	end
	
	-- Schematics must be learnable and unknown
	-- Item family 19 = schematic. Can't find the darn enum anywhere :(. So here's some examples:
	--[[
		Dye
		category 54 = "Dyes"
		type 332 = "Dye"
		family 16 = "Consumable"

		Weaponsmith Schematic
		category 66 = ""
		type 257 = "Weaponsmith Schematic"
		family 19 = "Schematic"

		Outfitter Guide
		category 66 = ""
		type 255 = "Outfitter Guide"
		family 19 = "Schematic"
	--]]
	if itemInSlot:GetItemFamily() == 19 then
		-- No tradeskill requirements means this tradeskill is not known by player
		if tDetails.tPrimary ~= nil and tDetails.tPrimary.arTradeskillReqs == nil then
			return false
		elseif tDetails.tPrimary ~= nil and #tDetails.tPrimary.arTradeskillReqs == 1 and (tDetails.tPrimary.arTradeskillReqs[1].bCanLearn == false or tDetails.tPrimary.arTradeskillReqs[1].bIsKnown == true) then
			-- Tradeskill requirements present (=known tradeskill) but item is known or unlearnable
			return false
		end
	end
	
	-- Catalysts (NB: Some catalysts lack the tCatalyst info structure and will not be hidden accordingly)
	if tDetails.tPrimary ~= nil and type(tDetails.tPrimary.tCatalyst) == "table" then
		local bKnown = false
		for _,skill in ipairs(CraftingLib.GetKnownTradeskills()) do
			if skill.eId == tDetails.tPrimary.tCatalyst.eTradeskill then
				bKnown = true
			end
		end
		
		if not bKnown then
			return false
		end
	end
	
	-- Pets only have a arSpecialFailures property when they're already known
	if tDetails.tPrimary ~= nil and tDetails.tPrimary.arSpecialFailures ~= nil then
		return false
	end	

	-- Nothing borked up the match yet, item must be usable
	return true
end


	--[[ React to the usable-checkbox --]]

function GBT:OnUsableButton_ButtonCheck(wndHandler, wndControl, eMouseButton)
	Usable.tSettings.bEnabled = true

	-- Tell Filter-controller to update modules due to filter changes
	Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage:UpdateModules()
end

function GBT:OnUsableButton_ButtonUncheck(wndHandler, wndControl, eMouseButton)
	Usable.tSettings.bEnabled = false
	
	-- Tell Filter-controller to update modules due to filter changes
	Apollo.GetPackage("GuildBankTools:Controller:Filter").tPackage:UpdateModules()
end


Apollo.RegisterPackage(Usable, "GuildBankTools:Module:Filter:Usable", 1, {}) 