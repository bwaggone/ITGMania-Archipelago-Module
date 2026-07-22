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
	
	-- Reset bonus usage for this song on a new completion/replay (fresh slate)
	if AP.bonusUsage then
		AP.bonusUsage[chart_name] = nil
		AP.SaveBonusUsage()
	end
	
	AP.LastEvaluation = {
		chart_name = chart_name,
		players = {}
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
			
			local usage = AP.bonusUsage and AP.bonusUsage[chart_name]
			local bonus_applied = 0
			if usage then
				if type(usage) == "table" then
					if AP.slotOptions.score_type == 0 then
						bonus_applied = usage.money or 0
					elseif AP.slotOptions.score_type == 2 then
						bonus_applied = usage.hex or 0
					else
						bonus_applied = usage.ex or 0
					end
				else
					bonus_applied = usage
				end
			end
			local adjustedPercent = activePercent + (bonus_applied * 0.25)
			
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
