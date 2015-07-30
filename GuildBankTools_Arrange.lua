--[[
	Arrange module controller.
--]]

local Arrange = {}
local GBT = Apollo.GetAddon("GuildBankTools")

Arrange.enumModules = {
	Stack = "Stack",
	Sort = "Sort",
}

function Arrange:Initialize()
	-- Load and intialize modules
	self.tModules = {}
	for eModule,_ in pairs(self.enumModules) do
		self.tModules[eModule] = Apollo.GetPackage("GuildBankTools:Module:Arrange:" .. eModule).tPackage
		self.tModules[eModule]:Initialize()
	end
	
	-- Hook into GuildAlerts to suppress the "guild bank busy" log message / throttle speed when it occurs
	-- GuildAlerts is optional, so only hook if it is found
	local GA = Apollo.GetAddon("GuildAlerts")
	if GA ~= nil then
		-- GuildAlerts found, hook OnGuildResult so "guid bank busy" messages can be intercepted and suppressed
		self.Orig_GA_OnGuildResult = GA.OnGuildResult
		GA.OnGuildResult = self.Hook_GA_OnGuildResult	
	else
		-- GuildAlerts not found. React to GuildResult events normally. 
		Apollo.RegisterEventHandler("GuildResult", "OnGuildResult", self) 
	end	
end

-- No forms for Arrange modules (yet)
function Arrange:LoadForms() end


--[[ Utility functions, checks if a/any module is in progress --]]

function Arrange:GetInProgressModule()
	return self.eInProgressModule
end

function Arrange:SetInProgressModule(eModule)
	self.eInProgressModule = eModule
end

function Arrange:ClearInProgressModule()
	self:SetInProgressModule(nil)
end


function Arrange:UpdateModules()
	--Print("UpdateModules")
	for eCurrent,module in pairs(self.tModules) do	
		
		local eInProgress = self:GetInProgressModule()
		
		if self:GetInProgressModule() == nil then
			-- Nothing currently in progress
			-- Recalculate arrangeables, and enable/disable accordingly
			module:DeterminePendingOperations()
			
			if module:HasPendingOperations() then
				module:Enable()
			else			
				module:Disable()
			end
		else
			-- Something currently in progress
			if eInProgress == eCurrent then
				-- This module is in progress, update arrangeables
				module:DeterminePendingOperations()				
				module:UpdateProgress()
			else
				-- Some other module is in progress -- keep disabled
				module:Disable()
			end		
		end
	end	
end


--[[ Control: start/stop of module --]]


function Arrange:StartModule(eModule)
	--Print("StartModule(" .. eModule .. ")")
	if self:GetInProgressModule() ~= nil then
		Print(string.format("WARNING: Attempt to start Arrange-module '%s' while '%s' is already in progress", eModule, self:GetInProgressModule()))
		return
	end

	-- When starting a module, all other modules must be disabled
	for e,module in pairs(self.tModules) do	
		if eModule ~= e then	
			module:Disable()
		end
	end

	-- Set this one as in-progress
	self:SetInProgressModule(eModule)

	-- Tell module to update its current progress indicator
	self.tModules[eModule]:UpdateProgress()
	
	-- Module hasn't actually *done* anything yet though... that happens in the schedulled call below
	self.nThrottleTimer = 0
	self:ScheduleExecution(eModule)
end

function Arrange:StopModule(eModule)
	--Print("StopModule(" .. eModule .. ")")
	-- Stopping an individual module happens by cancel button-click
	-- In that case, run the generic stop-all modules and update all modules
	self:StopModules()
	self:UpdateModules()
end

function Arrange:StopModules()
	--Print("StopModules")
	-- Module was asked to stop, either by user input or due to tab-change etc
	self:ClearInProgressModule()	
end



function Arrange:Hook_GA_OnGuildResult(guildSender, strName, nRank, eResult)	
	-- NB: In this hooked context "self" is GuildAlerts, not GuildBankTools
	if eResult ~= GuildLib.GuildResult_Busy then
		-- Not the busy-signal, just let GuildAlerts handle whatever it is as usual
		Arrange.Orig_GA_OnGuildResult(self, guildSender, strName, nRank, eResult)
	else
		-- Bank complains that it's busy (due to sort/stack spam)
		-- Is it me spamming? (is there an in-progress operation?)
		local eModuleInProgress = Arrange:GetInProgressModule()
	
		if eModuleInProgress ~= nil then		
			-- Yep, GuildBankTools is spamming
			-- "Eat" the busy signal event, engage throttle, and continue the operation
			Arrange.nThrottleTimer = 1
		
			-- Recalculate module status before proceeding (only update for in-progress module to save time)
			Arrange:UpdateModules(eModuleInProgress)
			
			Arrange:ScheduleExecution(eModuleInProgress)		
		else
			-- Something else did this, pass the signal on to GuildAlerts
			Arrange.Orig_GA_OnGuildResult(self, guildSender, strName, nRank, eResult)
		end
	end
end

function Arrange:OnGuildResult(guildSender, strName, nRank, eResult)	
	local eInProgress = Arrange:GetInProgressModule()
	if eResult == GuildLib.GuildResult_Busy and eInProgress ~= nil then
		Arrange.nThrottleTimer = 1
		
		-- Recalculate module status before proceeding
		Arrange.tModules.Stack:IdentifyStackableItems()
		Arrange.tModules.Sort:CalculateSortedList()
		
		Arrange:ScheduleExecution(eInProgress)		
	end
end






--[[ Event-based module execution --]]

-- Schedule execution, with optional throttling
function Arrange:ScheduleExecution(eModule)
	-- Start timer	
	self.timerOperation = ApolloTimer.Create(self.nThrottleTimer + 0.0, false, "Execute", self.tModules[eModule])
	
	-- Slowly ease up on the throttle for next pass
	self.nThrottleTimer = self.nThrottleTimer > 0.05 and self.nThrottleTimer-0.05 or 0
end

-- During a modules :Execute(), it must set this list of pending events 
function Arrange:SetPendingEvents(eModule, tPendingEvents)	
	self.tPendingEvents = self.tPendingEvents or {}
	self.tPendingEvents[eModule] = tPendingEvents
end

-- Each time an event is received
function Arrange:RemovePendingEvent(eModule, nUpdatedInventorySlot, bRemoved)
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

function Arrange:HasPendingEvents(eModule)
	if self.tPendingEvents == nil or self.tPendingEvents[eModule] == nil then return
		false
	end
	
	for k,v in pairs(self.tPendingEvents[eModule]) do
		return true
	end
	
	return false
end



Apollo.RegisterPackage(Arrange, "GuildBankTools:Controller:Arrange", 1, {}) 