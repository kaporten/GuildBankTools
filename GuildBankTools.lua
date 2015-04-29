require "Apollo"
require "Window"

-- Addon class itself
local GuildBankTools = {}

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
	Apollo.RegisterAddon(self, false, "GuildBankTools", nil)	
end

function GuildBankTools:OnLoad()	
	-- Register for bank-tab updated events
	Apollo.RegisterEventHandler("GuildBankTab", "OnGuildBankTab", self) -- Guild bank tab opened/changed.
	Apollo.RegisterEventHandler("GuildBankItem", "OnGuildBankItem", self) -- Guild bank tab contents changed.

	-- Load form for later use
	self.xmlDoc = XmlDoc.CreateFromFile("GuildBankTools.xml")
end

-- Whenever bank tab is changed, interrupt stacking (if it is in progress) and calc stackability
function GuildBankTools:OnGuildBankTab(guildOwner, nTab)	
	Print("OnGuildBankTab")
	-- Load-once; Search for the Bank window, attach overlay form if not already done
	local guildBankAddon = Apollo.GetAddon("GuildBank")
	if guildBankAddon ~= nil and self.xmlDoc ~= nil and (self.wndOverlayForm == nil or guildBankAddon.tWndRefs.wndMain:FindChild("GuildBankToolsForm") == nil) then		
		Print("Loading form")
		self.wndOverlayForm = Apollo.LoadForm(self.xmlDoc, "GuildBankToolsForm", guildBankAddon.tWndRefs.wndMain, self)			
	end

	self.bIsStacking = false
	self:UpdateStackableList(guildOwner, nTab)
	
	self:ResetHighlights()
	self:HighlightSearchMatches()
end

-- React to bank changes by re-calculating stackability
-- If stacking is in progress, mark progress on the current stacking (pendingUpdates)
function GuildBankTools:OnGuildBankItem(guildOwner, nTab, nInventorySlot, itemUpdated, bRemoved)
	Print("OnGuildBankItem")
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
	Print("UpdateStackableList")
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
	
	-- Nothing in self.tStackable? Just die quietly then.
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

-- Pulse all items-to-stack on the current tab
function GuildBankTools:HighlightStackables()
	local guildBankAddon = Apollo.GetAddon("GuildBank")
	
	-- Build lookuptable of all stackable ids. key=itemId, value=true (value not used).
	local tStackableItemIds = {}
	for _,tStackableSlot in ipairs(self.tStackable) do
		tStackableItemIds[tStackableSlot[1].itemInSlot:GetItemId()] = true
	end
		
	if guildBankAddon ~= nil then
		for _,tSlot in ipairs(self.guildOwner:GetBankTab(self.nTab)) do
			if tSlot ~= nil and tSlot.itemInSlot ~= nil then
				if tStackableItemIds[tSlot.itemInSlot:GetItemId()] ~= nil then
					guildBankAddon.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
				else
					guildBankAddon.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Hidden)
				end
			end
		end
	end	
end

function GuildBankTools:HighlightSearchMatches()
	-- If filter is present, use that
	local strSearch = self.wndOverlayForm:FindChild("SearchEditBox"):GetText()
	if strSearch ~= nil and strSearch ~= "" then
		strSearch = strSearch:lower()
	end

	local guildBankAddon = Apollo.GetAddon("GuildBank")
	if guildBankAddon ~= nil then
		for _,tSlot in ipairs(self.guildOwner:GetBankTab(self.nTab)) do
			if tSlot ~= nil and tSlot.itemInSlot ~= nil then
				if strSearch ~= nil and strSearch ~= "" then 
					-- Search criteria present, only show matches
					if string.match(tSlot.itemInSlot:GetName():lower(), strSearch) ~= nil then
						guildBankAddon.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
					else
						guildBankAddon.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Hidden)
					end
				else
					-- No search criteria present, show all slots
					guildBankAddon.tWndRefs.tBankItemSlots[tSlot.nIndex]:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
				end
			end
		end
	end	
end

function GuildBankTools:ResetHighlights()
	local guildBankAddon = Apollo.GetAddon("GuildBank")
	if guildBankAddon ~= nil then
		for _,wndSlot in ipairs(guildBankAddon.tWndRefs.tBankItemSlots) do
			wndSlot:FindChild("BankItemIcon"):SetOpacity(enumOpacity.Visible)
		end
	end
end

function GuildBankTools:OnSearchEditBox_EditBoxChanged( wndHandler, wndControl, strText )
	self:HighlightSearchMatches()
end

-- Standard addon initialization
GuildBankToolsInst = GuildBankTools:new()
GuildBankToolsInst:Init()