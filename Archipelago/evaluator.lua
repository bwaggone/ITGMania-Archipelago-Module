local AP = ...

AP.EvaluateCompletedSong = function()
	local song = GAMESTATE:GetCurrentSong()
	if not song then return end
	
	local songFilePath = song:GetSongFilePath()
	if not songFilePath then return end
	
	-- Extract the folder name from the song's virtual directory path
	local songDir = song:GetSongDir()
	local parts = {}
	for part in songDir:gmatch("[^/]+") do
		table.insert(parts, part)
	end
	local folderName = parts[#parts]
	
	if not folderName then return end
	
	-- Verify if the song is part of the Archipelago run by looking up its folder name
	local chart_name = AP.folderToChartName[folderName]
	if not chart_name then
		-- Not an AP song, ignore silently
		return
	end
	
	AP.AP_SM("Evaluating completed AP song: " .. chart_name)
	
	AP.LastEvaluation = {
		chart_name = chart_name,
		players = {},
		proposed_items = { money = 0, ex = 0, hex = 0 }
	}
	
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
		if pss then
			local is_failed = pss:GetFailed()
			local moneyPercent = pss:GetPercentDancePoints() * 100
			
			-- EX Percent and High EX Percent (High EX has use_actual_w0_weight = true)
			local exPercent = 0
			local highExPercent = 0
			if CalculateExScore then
				local success_ex, val_ex = pcall(CalculateExScore, pn)
				if success_ex then exPercent = val_ex end
				
				local success_hex, val_hex = pcall(CalculateExScore, pn, nil, true)
				if success_hex then highExPercent = val_hex end
			else
				AP.Trace("Archipelago warning: CalculateExScore function not found in global scope!")
			end
			
			-- Select score percentage based on option
			local activePercent = moneyPercent
			local score_system_name = "Money"
			if AP.slotOptions.score_type == 1 then
				activePercent = exPercent
				score_system_name = "EX"
			elseif AP.slotOptions.score_type == 2 then
				activePercent = highExPercent
				score_system_name = "High EX (FA+)"
			end
			
			local adjustedPercent = activePercent
			
			AP.AP_SM("Player " .. ToEnumShortString(pn) .. " Performance - " .. score_system_name .. " Score: " .. string.format("%.2f", activePercent) .. "% (Money: " .. string.format("%.2f", moneyPercent) .. "%" .. (CalculateExScore and (", EX: " .. string.format("%.2f", exPercent) .. "%") or "") .. "), Failed: " .. tostring(is_failed))
			
			-- Cache player stats for the score adjuster overlay
			AP.LastEvaluation.players[pn] = {
				is_failed = is_failed,
				moneyPercent = moneyPercent,
				exPercent = exPercent,
				highExPercent = highExPercent,
				activePercent = activePercent,
				adjustedPercent = adjustedPercent,
				score_system_name = score_system_name,
			}
		end
	end
	
	-- If the player has no available bonus items, finalize and send checks immediately.
	-- Otherwise, let them decide via the auto-popup overlay before finalizing.
	local available = AP.GetAvailableBonusItems()
	if available == 0 then
		AP.FinalizeEvaluationAndSendChecks()
	end
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
	
	local money_applied = 0
	local ex_applied = 0
	local hex_applied = 0
	
	if AP.LastEvaluation and AP.LastEvaluation.proposed_items then
		money_applied = AP.LastEvaluation.proposed_items.money or 0
		ex_applied = AP.LastEvaluation.proposed_items.ex or 0
		hex_applied = AP.LastEvaluation.proposed_items.hex or 0
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

