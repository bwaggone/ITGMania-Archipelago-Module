local AP = ...

AP.LoadBonusUsage = function()
	AP.bonusUsage = {}
	if AP.seedName == "Unknown" or not AP.SLOT then return end
	local path = "Save/Archipelago_Bonus_" .. AP.seedName .. "_" .. AP.SLOT .. ".txt"
	local file = RageFileUtil.CreateRageFile()
	if file:Open(path, 1) then -- Mode 1 = Read
		local content = file:Read()
		file:Close()
		file:destroy()
		
		if content then
			for line in content:gmatch("[^\r\n]+") do
				-- Format 1: song_name:score_type=count
				local name, score_type, count_str = line:match("^([^:]+):([^=]+)=(%d+)$")
				if name and score_type and count_str then
					if not AP.bonusUsage[name] then AP.bonusUsage[name] = {money=0, ex=0, hex=0} end
					AP.bonusUsage[name][score_type] = tonumber(count_str)
				else
					-- Format 2 (legacy): song_name=count
					local legacy_name, legacy_count_str = line:match("^([^=]+)=(%d+)$")
					if legacy_name and legacy_count_str then
						local count = tonumber(legacy_count_str)
						AP.bonusUsage[legacy_name] = count
					end
				end
			end
		end
	else
		file:destroy()
	end
end

AP.SaveBonusUsage = function()
	if AP.seedName == "Unknown" or not AP.SLOT then return end
	local path = "Save/Archipelago_Bonus_" .. AP.seedName .. "_" .. AP.SLOT .. ".txt"
	local file = RageFileUtil.CreateRageFile()
	if file:Open(path, 2) then -- Mode 2 = Write
		local lines = {}
		for name, usage in pairs(AP.bonusUsage or {}) do
			if type(usage) == "table" then
				if (usage.money or 0) > 0 then
					table.insert(lines, name .. ":money=" .. tostring(usage.money))
				end
				if (usage.ex or 0) > 0 then
					table.insert(lines, name .. ":ex=" .. tostring(usage.ex))
				end
				if (usage.hex or 0) > 0 then
					table.insert(lines, name .. ":hex=" .. tostring(usage.hex))
				end
			else
				-- Save legacy format if unchanged
				table.insert(lines, name .. "=" .. tostring(usage))
			end
		end
		local content = table.concat(lines, "\n")
		file:Write(content)
		file:Close()
		file:destroy()
	else
		file:destroy()
		AP.Trace("Archipelago error: Could not save bonus usage to " .. path)
	end
end

AP.GetTotalUsedBonusItems = function()
	local total = 0
	for _, usage in pairs(AP.bonusUsage or {}) do
		if type(usage) == "table" then
			total = total + (usage.money or 0) + (usage.ex or 0) + (usage.hex or 0)
		else
			total = total + usage
		end
	end
	return total
end

AP.GetAvailableBonusItems = function()
	local _, _, total_received = AP.GetModifierStats()
	local total_used = AP.GetTotalUsedBonusItems()
	return math.max(0, total_received - total_used)
end

AP.ApplyBonusPercentage = function(chart_name, proposed)
	if not AP.bonusUsage[chart_name] or type(AP.bonusUsage[chart_name]) ~= "table" then
		AP.bonusUsage[chart_name] = {money=0, ex=0, hex=0}
	end
	local usage = AP.bonusUsage[chart_name]
	usage.money = usage.money + (proposed.money or 0)
	usage.ex = usage.ex + (proposed.ex or 0)
	usage.hex = usage.hex + (proposed.hex or 0)
	
	AP.SaveBonusUsage()
	AP.FinalizeEvaluationAndSendChecks()
end

AP.FinalizeEvaluationAndSendChecks = function()
	if not AP.LastEvaluation or AP.LastEvaluation.finalized then return end
	AP.LastEvaluation.finalized = true
	
	local chart_name = AP.LastEvaluation.chart_name
	local checks_to_send = {}
	local queue_check = function(suffix)
		local loc_name = chart_name .. "-" .. suffix
		local loc_id = AP.locationIds[loc_name]
		if loc_id and not AP.checkedLocations[loc_id] then
			table.insert(checks_to_send, loc_id)
		end
	end
	
	local usage = AP.bonusUsage[chart_name]
	local money_applied = 0
	local ex_applied = 0
	local hex_applied = 0
	
	if usage then
		if type(usage) == "table" then
			money_applied = usage.money or 0
			ex_applied = usage.ex or 0
			hex_applied = usage.hex or 0
		else
			if AP.slotOptions.score_type == 0 then
				money_applied = usage
			elseif AP.slotOptions.score_type == 2 then
				hex_applied = usage
			else
				ex_applied = usage
			end
		end
	end
	
	for pn, pdata in pairs(AP.LastEvaluation.players) do
		local moneyPercent = pdata.moneyPercent
		local exPercent = pdata.exPercent
		local highExPercent = pdata.highExPercent
		local is_failed = pdata.is_failed
		
		-- Calculate adjusted percentages for each score type
		local adjMoney = moneyPercent + (money_applied * 0.25)
		local adjEx = exPercent + (ex_applied * 0.25)
		local adjHex = highExPercent + (hex_applied * 0.25)
		
		-- Select adjusted percentage based on active score option
		local adjustedPercent = adjEx
		if AP.slotOptions.score_type == 0 then
			adjustedPercent = adjMoney
		elseif AP.slotOptions.score_type == 2 then
			adjustedPercent = adjHex
		end
		
		-- Check clear condition
		local fail_allowed = (AP.slotOptions.fail_allowed == true or AP.slotOptions.fail_allowed == 1)
		local passed_clear = false
		if not is_failed or fail_allowed then
			if adjustedPercent >= AP.slotOptions.passing_score then
				passed_clear = true
			end
		end
		
		if passed_clear then
			AP.AP_SM("Player " .. ToEnumShortString(pn) .. " CLEARED the song logic!")
			queue_check("0")
			queue_check("1")
			
			-- Check score thresholds
			if adjustedPercent >= 85 then queue_check("85") end
			if adjustedPercent >= 90 then queue_check("90") end
			if adjustedPercent >= 96 then queue_check("96") end
			if adjustedPercent >= 98 then queue_check("98") end
			if adjustedPercent >= 99 then queue_check("99") end
		else
			AP.AP_SM("Player " .. ToEnumShortString(pn) .. " did not clear the song logic (Passing Score target: " .. tostring(AP.slotOptions.passing_score) .. "%)")
		end
		
		-- Quad and Quint are independent of the selected score_type
		if adjMoney >= 100 then
			AP.AP_SM("Player " .. ToEnumShortString(pn) .. " got a QUAD money score!")
			queue_check("quad")
		end
		if adjEx >= 100 and CalculateExScore then
			AP.AP_SM("Player " .. ToEnumShortString(pn) .. " got a QUINT EX score!")
			queue_check("quint")
		end
	end
	
	if #checks_to_send > 0 and AP.apHandlerInstance and AP.apHandlerInstance.connected and AP.apHandlerInstance.socket then
		AP.AP_SM("Sending " .. tostring(#checks_to_send) .. " location checks to server...")
		local checks_packet = {
			["cmd"] = "LocationChecks",
			locations = checks_to_send
		}
		local payload = JsonEncode({ checks_packet })
		AP.apHandlerInstance.socket:Send(payload, false)
		MESSAGEMAN:Broadcast("APItemNotification", { type = "Sent", name = chart_name })
		
		-- Locally mark checks as completed immediately
		for _, loc_id in ipairs(checks_to_send) do
			AP.checkedLocations[loc_id] = true
		end
	else
		AP.AP_SM("No locations to check or client is not connected.")
	end
end
