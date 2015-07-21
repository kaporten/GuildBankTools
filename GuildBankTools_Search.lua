
local GuildBankTools = Apollo.GetAddon("GuildBankTools")
local GB = Apollo.GetAddon("GuildBank")


-- Go through all bank slots with items, highlight all those with matching name
function GuildBankTools:HighlightSearchMatches()
	-- Extract search string
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	local bPerformSearch = false
	if strSearch ~= nil and strSearch ~= "" then
		strSearch = strSearch:lower()
		bPerformSearch = true
	end
	
	-- Get usable-only marker
	local bPerformUsableCheck = self.wndOverlayForm:FindChild("UsableButton"):IsChecked()

	if GB ~= nil then
		-- Check all tabs for search-hits
		for nTab,wndHighlight in ipairs(self.tTabHighlights) do
			-- Indicates if this tab has any search matches
			local bSearchMatchesOnTab = false
			
			local tTab = self.guildOwner:GetBankTab(nTab)
			if tTab ~= nil then
				for _,tSlot in ipairs(tTab) do				
					if tSlot ~= nil and tSlot.itemInSlot ~= nil then
						-- Default: all checks pass
						local bSearchOK, bUsableOK = true, true

						-- Check match against search string
						if bPerformSearch then
							-- Search criteria present, only show matches
							if string.match(tSlot.itemInSlot:GetName():lower(), strSearch) ~= nil then
								-- Match, keep visible
								bSearchOK = true							
							else
								-- No match, hide
								bSearchOK = false
							end
						end
						
						-- Check usability
						if bPerformUsableCheck then
							bUsableOK = self:IsUsable(tSlot.itemInSlot)				
						end

						
						if nTab == self.nCurrentTab then
							-- For current tab, show/hide individual items
							local bShow = bSearchOK and bUsableOK
							GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(bShow and GuildBankTools.enumOpacity.Visible or GuildBankTools.enumOpacity.Hidden)
						else
							-- For other tabs, just mark tab header for highlighting
							if bPerformSearch and bSearchOK then -- Only highlight if search text is entered/matched								
								if bPerformUsableCheck then
									if bUsableOK then
										-- Usable checked , and usable search-hit found on tab, set indicator
										bSearchMatchesOnTab = true
									end							
								else
									-- Search-hit on tab, usable-only not checked
									bSearchMatchesOnTab = true
								end
							end
						end						
					end
				end
			end
						
			-- Show or hide tab-match indicator based on search matches
			wndHighlight:Show(bSearchMatchesOnTab)
		end
	end	
end

function GuildBankTools:IsUsable(itemInSlot)	
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

--[[ React to changes to the search editbox --]]
function GuildBankTools:OnSearchEditBox_EditBoxChanged(wndHandler, wndControl, strText)
	-- Content changed, highlight matches
	self:HighlightSearchMatches()
	
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	if strSearch ~= nil and strSearch ~= "" then
		self.wndOverlayForm:FindChild("ClearSearchButton"):Show(true)
	else
		self.wndOverlayForm:FindChild("ClearSearchButton"):Show(false)
	end
end

function GuildBankTools:OnClearSearchButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	-- Clicking the clear-button drops focus, clears text and hides the button
	self.wndOverlayForm:FindChild("SearchEditBox"):SetText("")
	self.wndOverlayForm:FindChild("SearchEditBox"):ClearFocus()
	self.wndOverlayForm:FindChild("ClearSearchButton"):Show(false)
	
	self:HighlightSearchMatches()
end



--[[ React to the usable-checkbox --]]
function GuildBankTools:OnUsableButton_ButtonCheck(wndHandler, wndControl, eMouseButton)
	self.tSettings.bUsableOnly = true
	self:HighlightSearchMatches()
end
function GuildBankTools:OnUsableButton_ButtonUncheck(wndHandler, wndControl, eMouseButton)
	self.tSettings.bUsableOnly = false
	self:HighlightSearchMatches()	
end