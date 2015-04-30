--[[
	GuildBankTools by porten. 
	Comments/suggestions/questions? Find me on Curse or porten@gmail.com.
--]]

require "Apollo"
require "Window"

-- Addon class itself
local GuildBankTools = {}

-- Ref to the GuildBank addon
local GB

-- Opacity levels to use when highlighting items
local enumOpacity = {
	Hidden = 0.2,
	Visible = 1
}

function GuildBankTools:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

function GuildBankTools:Init()
	Apollo.RegisterAddon(self, false, "GuildBankTools", {"GuildBank"})	
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

-- Whenever bank tab is changed, interrupt stacking (if it is in progress) and calc stackability
function GuildBankTools:OnGuildBankTab(guildOwner, nTab)	
	-- First-hit form loading when the items (vault) tab is shown	
	if GB ~= nil and self.xmlDoc ~= nil and (self.wndOverlayForm == nil or GB.tWndRefs.wndMain:FindChild("GuildBankToolsForm") == nil) then		
		self.wndOverlayForm = Apollo.LoadForm(self.xmlDoc, "GuildBankToolsForm", GB.tWndRefs.wndMain, self)					
	end

	-- Changed tab, interrupt any in-progress stacking
	self.bIsStacking = false
	
	-- Calculate list of stackable items
	self:UpdateStackableList(guildOwner, nTab)
	
	-- Ensure all items are visible when changing tabs
	--[[ 
		This is done, even if a search pattern is available, 
		to ensure that match-status is reset for empty bank slots as well.
		(HighlightSearchMatches only touches bank slots with items)
	--]]
	self:ResetHighlights()
	
	-- Then highlight any search criteria matches
	self:HighlightSearchMatches()
end

-- React to bank changes by re-calculating stackability
-- If stacking is in progress, mark progress on the current stacking (pendingUpdates)
function GuildBankTools:OnGuildBankItem(guildOwner, nTab, nInventorySlot, itemUpdated, bRemoved)
	-- Re-calculate stackable items list
	self:UpdateStackableList(guildOwner, nTab)
	
	-- Remove pending update-event matched by this update-event (if any)
	if self.pendingUpdates ~= nil then
		for idx,nSlot in ipairs(self.pendingUpdates) do
			if nSlot == nInventorySlot then
				table.remove(self.pendingUpdates, idx)
			end
		end
	end
		
	-- If stacking is in progress - and last pending update was just completed - continue stacking
	if self.bIsStacking == true and self.pendingUpdates ~= nil and #self.pendingUpdates == 0 then
		self:Stack()
	end	
end

-- Identifies which slots can be stacked. Table of stackable slots is stored in self.tStackable
function GuildBankTools:UpdateStackableList(guildOwner, nTab)
	-- Build table containing 
	--  key = itemId, 
	--  value = list of stackable slots
	local tStackableItems = {}
	
	-- Identify all stackable slots in the current tab, and add to tStackableItems
	for _,tSlot in ipairs(guildOwner:GetBankTab(nTab)) do
		if tSlot ~= nil and self:IsItemStackable(tSlot.itemInSlot) then
			local nItemId = tSlot.itemInSlot:GetItemId()
			
			-- Add current tSlot to tSlots-list containing all slots for this itemId
			local tSlots = tStackableItems[nItemId] or {}
			tSlots[#tSlots+1] = tSlot
			
			-- Add slot details to list of stackable items
			tStackableItems[nItemId] = tSlots
		end
	end
	
	-- Addon-scoped resulting list of stackable slots on current bank tab
	self.tStackable = {}
	self.nTab = nTab
	self.guildOwner = guildOwner
	
	for itemId,tSlots in pairs(tStackableItems) do
		-- More than one stackable stack of this stackable item? If so, add to tStackable. Stack!
		if #tSlots > 1 then 		
			self.tStackable[#self.tStackable+1] = tSlots
		end
	end
	
	-- Update the button enable-status accordingly
	self:UpdateStackButton()
end

function GuildBankTools:UpdateStackButton()
	-- Do nothing if overlay form is not loaded
	if self.wndOverlayForm == nil then
		return
	end
	
	local bEnable = self.tStackable ~= nil and #self.tStackable > 0
	local wndButton = self.wndOverlayForm:FindChild("StackButton")
	if wndButton ~= nil then
		wndButton:Enable(bEnable)	
	end
end

-- An item is considered stackable if it has a current stacksize < max stacksize.
-- TODO: Manually handle BoE bags and other stackable items with a non-visible max stack size.
function GuildBankTools:IsItemStackable(tItem)	
	return tItem:GetMaxStackCount() > 1 and tItem:GetStackCount() < tItem:GetMaxStackCount()
end

-- Performs one single stacking operation.
-- Sets a flag indicating if further stacking is possible, but takes no further action 
-- (awaits Event indicating this stacking-operation has fully completed)
function GuildBankTools:Stack()
	-- Set flag for retriggering another stack after this one	
	self.bIsStacking = true

	-- Reset opacity to search matches, then stack
	self:HighlightSearchMatches()
	
	-- Safeguard, but should only happen if someone calls :Stack() before opening the guild bank
	if self.tStackable == nil then
		self.bIsStacking = false
		return
	end
	
	-- Grab last element from the tStackable list of item-types
	local tSlots = table.remove(self.tStackable)
	
	-- Nothing in self.tStackable? Just do nothing then.
	if tSlots == nil then
		self.bIsStacking = false
		return
	end

	-- Shorthands for first slot (target) and last slot (source)
	local tFirstSlot = tSlots[1]
	local tLastSlot = tSlots[#tSlots]

	-- Determine current stack move size
	local nRoomInFirstSlot = tLastSlot.itemInSlot:GetMaxStackCount() - tFirstSlot.itemInSlot:GetStackCount()
	local nItemsToMove = math.min(nRoomInFirstSlot, tLastSlot.itemInSlot.GetStackCount())			
			
	-- Make a note of slot-indices that are being updated. We need to await events for both slots before triggering next pass.
	self.pendingUpdates = {tFirstSlot.nIndex, tLastSlot.nIndex}
	
	-- Fire off the update by beginning and ending the bank transfer
	self.guildOwner:BeginBankItemTransfer(tLastSlot.itemInSlot, nItemsToMove)
	self.guildOwner:EndBankItemTransfer(self.nTab, tFirstSlot.nIndex) -- Expected to trigger OnGuildBankItem
end

-- When the stack-button is clicked, execute the stack operation
function GuildBankTools:OnStackButton_ButtonSignal(wndHandler, wndControl, eMouseButton)
	self:Stack()
end

-- When mousing over the button, change bank-slot opacity to identify stackables
function GuildBankTools:OnStackButton_MouseEnter(wndHandler, wndControl, x, y)
	if wndControl:IsEnabled() then
		self:HighlightStackables()
	end
end

-- When no longer hovering over the button, reset opacity for stackables to whatever matches search criteria
function GuildBankTools:On_StackButton_MouseExit(wndHandler, wndControl, x, y)
	self:HighlightSearchMatches()
end

-- Highlight all items-to-stack on the current tab
function GuildBankTools:HighlightStackables()
	-- Build lookuptable of all stackable ids. key=itemId, value=true (value not used).
	local tStackableItemIds = {}
	for _,tStackableSlot in ipairs(self.tStackable) do
		tStackableItemIds[tStackableSlot[1].itemInSlot:GetItemId()] = true
	end
		
	-- Go through all filled slots in the current tab and highlight all which contains a stackable itemId
	-- (Or, more correctly: dim down those who DON'T)
	if GB ~= nil then
		for _,tSlot in ipairs(self.guildOwner:GetBankTab(self.nTab)) do
			if tSlot ~= nil and tSlot.itemInSlot ~= nil then
				if tStackableItemIds[tSlot.itemInSlot:GetItemId()] ~= nil then
					GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
				else
					GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Hidden)
				end
			end
		end
	end	
end

-- Go through all bank slots with items, highlight all those with matching name
function GuildBankTools:HighlightSearchMatches()
	-- Extract search string
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	if strSearch ~= nil and strSearch ~= "" then
		strSearch = strSearch:lower()
	end

	if GB ~= nil then
		for _,tSlot in ipairs(self.guildOwner:GetBankTab(self.nTab)) do
			if tSlot ~= nil and tSlot.itemInSlot ~= nil then
				if strSearch ~= nil and strSearch ~= "" then 
					-- Search criteria present, only show matches
					if string.match(tSlot.itemInSlot:GetName():lower(), strSearch) ~= nil then
						-- Match, keep visible
						GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
					else
						-- No match, hide
						GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Hidden)
					end
				else
					-- No search criteria present, keep slot visible
					GB.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
				end
			end
		end
	end	
end

-- Go through all GUI slots in the bank tab, reset opacity on all
function GuildBankTools:ResetHighlights()
	if GB ~= nil then
		for _,wndSlot in ipairs(GB.tWndRefs.tBankItemSlots) do
			wndSlot:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
		end
	end
end

--[[ React to changes to the search editbox --]]
function GuildBankTools:OnSearchEditBox_EditBoxChanged(wndHandler, wndControl, strText)
	-- Content changed, highlight matches
	self:HighlightSearchMatches()
end
function GuildBankTools:OnSearchEditBox_WindowGainedFocus(wndHandler, wndControl)
	-- Focus gained, hide the background "Search for..." text
	self.wndOverlayForm:FindChild("SearchBackgroundText"):Show(false)
end
function GuildBankTools:OnSearchEditBox_WindowLostFocus(wndHandler, wndControl)
	-- Focus lost, show background text, if no search criteria is entered
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	if strSearch ~= nil and strSearch ~= "" then
		self.wndOverlayForm:FindChild("SearchBackgroundText"):Show(false)
	else
		self.wndOverlayForm:FindChild("SearchBackgroundText"):Show(true)
	end
end


-- Standard addon initialization
GuildBankToolsInst = GuildBankTools:new()
GuildBankToolsInst:Init()