local AP = ...

AP.playerNames = {}
AP.slotInfo = {}
AP.datapackage = {}

AP.GetPlayerName = function(slot)
	if not slot then return "Unknown Player" end
	return AP.playerNames[slot] or ("Player " .. slot)
end

AP.GetGameForSlot = function(slot)
	if not slot then return nil end
	local info = AP.slotInfo[slot]
	return info and info.game
end

AP.GetItemName = function(itemId, slot)
	local game = AP.GetGameForSlot(slot)
	if game and AP.datapackage and AP.datapackage[game] and AP.datapackage[game].itemNames then
		local name = AP.datapackage[game].itemNames[tostring(itemId)]
		if name then return name end
	end
	
	-- Fallback to local itemNames if slot is own slot or game is ITGMania
	if slot == AP.SLOT or (game == AP.GAME_NAME) then
		local name = AP.itemNames[itemId] or AP.itemNames[tostring(itemId)]
		if name then return name end
	end
	
	return "Unknown Item (ID " .. tostring(itemId) .. ")"
end

AP.GetLocationName = function(locationId, slot)
	local game = AP.GetGameForSlot(slot)
	if game and AP.datapackage and AP.datapackage[game] and AP.datapackage[game].locationNames then
		local name = AP.datapackage[game].locationNames[tostring(locationId)]
		if name then return name end
	end
	
	return "Unknown Location (ID " .. tostring(locationId) .. ")"
end

AP.ParsePrintJSON = function(parts)
	if not parts then return "" end
	local message = ""
	for _, part in ipairs(parts) do
		local part_type = part.type
		local part_text = part.text or ""
		
		if part_type == "player_id" then
			local slot = tonumber(part_text) or part_text
			message = message .. AP.GetPlayerName(slot)
		elseif part_type == "item_id" then
			local itemId = tonumber(part_text) or part_text
			local slot = part.player
			message = message .. AP.GetItemName(itemId, slot)
		elseif part_type == "location_id" then
			local locationId = tonumber(part_text) or part_text
			local slot = part.player
			message = message .. AP.GetLocationName(locationId, slot)
		else
			-- Fallback for player_name, item_name, location_name, entrance_name, text, etc.
			message = message .. part_text
		end
	end
	return message
end

AP.SaveCacheToDisk = function()
	if not AP.seedName or AP.seedName == "Unknown" or not AP.slotInfo or not AP.datapackage then
		return
	end
	local dir = THEME:GetCurrentThemeDirectory() .. "Modules/Archipelago/SAVE_AP_" .. AP.seedName .. "/"
	for slotId, slot_data in pairs(AP.slotInfo) do
		local playerName = AP.playerNames[slotId] or ("Player_" .. tostring(slotId))
		-- Filter out invalid folder/file name characters
		playerName = playerName:gsub("[%s%c\\/:%*%?\"<>|]", "_")
		local gameName = slot_data.game
		local gameData = AP.datapackage[gameName]
		
		if gameData then
			local playerData = {
				playerName = playerName,
				slot = slotId,
				game = gameName,
				itemNames = gameData.itemNames or {},
				locationNames = gameData.locationNames or {}
			}
			local jsonStr = JsonEncode(playerData)
			local path = dir .. playerName .. ".txt"
			local file = RageFileUtil.CreateRageFile()
			if file:Open(path, 2) then -- Mode 2 = Write
				file:Write(jsonStr)
				file:Close()
				file:destroy()
			else
				file:destroy()
				AP.Trace("Archipelago error: Could not write cache file to " .. path)
			end
		end
	end
end

AP.LoadCacheFromDisk = function()
	if not AP.seedName or AP.seedName == "Unknown" then return end
	local dir = THEME:GetCurrentThemeDirectory() .. "Modules/Archipelago/SAVE_AP_" .. AP.seedName .. "/"
	
	if not AP.playerNames then AP.playerNames = {} end
	if not AP.slotInfo then AP.slotInfo = {} end
	if not AP.datapackage then AP.datapackage = {} end
	
	local files = FILEMAN:GetDirListing(dir .. "*", false, false)
	if files and #files > 0 then
		local loadedCount = 0
		for _, filename in ipairs(files) do
			if filename:match("%.txt$") then
				local path = dir .. filename
				local file = RageFileUtil.CreateRageFile()
				if file:Open(path, 1) then -- Mode 1 = Read
					local content = file:Read()
					file:Close()
					file:destroy()
					
					if content then
						local success, data = pcall(JsonDecode, content)
						if success and data and data.slot and data.game then
							local slotId = tonumber(data.slot) or data.slot
							local gameName = data.game
							local playerName = data.playerName or filename:gsub("%.txt$", "")
							
							AP.playerNames[slotId] = playerName
							AP.slotInfo[slotId] = {
								name = playerName,
								game = gameName,
								type = data.type or 0
							}
							
							if not AP.datapackage[gameName] then
								AP.datapackage[gameName] = {
									itemNames = {},
									locationNames = {}
								}
							end
							
							if data.itemNames then
								for id_str, name in pairs(data.itemNames) do
									AP.datapackage[gameName].itemNames[id_str] = name
								end
							end
							if data.locationNames then
								for id_str, name in pairs(data.locationNames) do
									AP.datapackage[gameName].locationNames[id_str] = name
								end
							end
							
							loadedCount = loadedCount + 1
						end
					end
				else
					file:destroy()
				end
			end
		end
		AP.AP_SM("Loaded " .. tostring(loadedCount) .. " players from local seed cache.")
	end
end

AP.FormatNotificationName = function(name)
	if not name then return "Unknown" end
	if name:find("/") then
		local parts = {}
		for part in name:gmatch("[^/]+") do
			table.insert(parts, part)
		end
		if #parts >= 2 then
			return parts[2]
		elseif #parts == 1 then
			return parts[1]
		end
	end
	return name
end

AP.CreateRequest = function(event, data)
	return JsonEncode({
		event=event,
		data=data
	})
end

-- Helper function to get all unlocked songs / charts from received items.
-- Unlocked songs are defined as received items containing a "/" character in their name.
AP.GetUnlockedSongs = function()
	local songs = {}
	local seen = {}
	if AP.AP_AllReceivedItems then
		for _, item in ipairs(AP.AP_AllReceivedItems) do
			local name = AP.itemNames[item.item]
			if name and name:find("/") and not seen[name] then
				seen[name] = true
				table.insert(songs, name)
			end
		end
	end
	-- Sort alphabetically for better navigation
	table.sort(songs)
	return songs
end

AP.GetChecksForSong = function(chart_name)
	local total = 0
	local completed = 0
	if AP.locationIds then
		for name, id in pairs(AP.locationIds) do
			if name:sub(1, #chart_name + 1) == chart_name .. "-" then
				-- If activeLocationIds is populated, only count active locations.
				-- Otherwise, fall back to counting all defined locations.
				if not AP.activeLocationIds or AP.activeLocationIds[id] then
					total = total + 1
					if AP.checkedLocations and AP.checkedLocations[id] then
						completed = completed + 1
					end
				end
			end
		end
	end
	return completed, total
end

-- Helper to get stats on unlocked Archipelago modifiers.
-- Traverses received items to determine:
-- 1. Highest BPM speed limit modifier item (e.g. "Speed 550bpm")
-- 2. Darkest background filter modifier item (e.g. "Darker Filter")
-- 3. Number of "Score Booster" items received
AP.GetModifierStats = function()
	local max_bpm = "Default (250)"
	local max_filter = "None"
	local mini = "Default (100%)"
	local bonus_count = 0

	local speed_items = {
		["Speed 350bpm"] = 350,
		["Speed 450bpm"] = 450,
		["Speed 550bpm"] = 550,
		["Speed 650bpm"] = 650,
		["Speed 750bpm"] = 750,
		["Speed Any BPM"] = 9999,
	}

	local mini_items = {
		["90% Mini"] = 90,
		["70% Mini"] = 70,
		["50% Mini"] = 50,
		["Any Mini"] = 0,
	}

	local filter_items = {
		["Dark Filter"] = 1,
		["Darker Filter"] = 2,
		["Darkest Filter"] = 3,
	}

	local highest_speed_val = 0
	local highest_filter_val = 0
	local lowest_mini_val = 100

	if AP.AP_AllReceivedItems then
		for _, item in ipairs(AP.AP_AllReceivedItems) do
			local name = AP.itemNames[item.item]
			if name then
				if name == "Score Booster" then
					bonus_count = bonus_count + 1
				elseif speed_items[name] then
					if speed_items[name] > highest_speed_val then
						highest_speed_val = speed_items[name]
						if name == "Speed Any BPM" then
							max_bpm = "Unlimited"
						else
							max_bpm = name:gsub("Speed ", ""):upper()
						end
					end
				elseif filter_items[name] then
					if filter_items[name] > highest_filter_val then
						highest_filter_val = filter_items[name]
						max_filter = name:gsub(" Filter", "")
					end
				elseif mini_items[name] then
					if mini_items[name] < lowest_mini_val then
						lowest_mini_val = mini_items[name]
						mini = name:gsub(" Mini", "")
					end
				end
			end
		end
	end

	return max_bpm, max_filter, mini, bonus_count
end

AP.IsEnforcingMods = function()
	return AP.apHandlerInstance and AP.apHandlerInstance.connected and AP.slotOptions and AP.slotOptions.enable_mod_items
end

AP.GetMaxAllowedMini = function()
	if not AP.IsEnforcingMods() then
		return 100
	end
	local lowest_mini_val = 100
	if AP.AP_AllReceivedItems then
		for _, item in ipairs(AP.AP_AllReceivedItems) do
			local name = AP.itemNames[item.item]
			if name then
				if name == "90% Mini" then
					if 90 < lowest_mini_val then lowest_mini_val = 90 end
				elseif name == "70% Mini" then
					if 70 < lowest_mini_val then lowest_mini_val = 70 end
				elseif name == "50% Mini" then
					if 50 < lowest_mini_val then lowest_mini_val = 50 end
				elseif name == "Any Mini" then
					lowest_mini_val = 0
				end
			end
		end
	end
	if lowest_mini_val == 100 then return 0
	elseif lowest_mini_val == 90 then return 10
	elseif lowest_mini_val == 70 then return 30
	elseif lowest_mini_val == 50 then return 50
	else return 100
	end
end

AP.ClampedWarnings = {}

AP.ClampSpeedMod = function(pn)
	if not AP.IsEnforcingMods() then return end
	
	local max_bpm_str, _, _, _ = AP.GetModifierStats()
	local max_bpm_limit = 250
	if max_bpm_str == "Unlimited" then
		return -- No limit
	elseif max_bpm_str:match("^%d+") then
		max_bpm_limit = tonumber(max_bpm_str:match("^%d+")) or 250
	end
	
	local pName = ToEnumShortString(pn)
	local mods = SL[pName].ActiveModifiers
	if not mods or not mods.SpeedMod then return end
	
	local speed = mods.SpeedMod
	local speed_type = mods.SpeedModType or "X"
	
	if speed_type == "C" or speed_type == "M" then
		if speed > max_bpm_limit then
			mods.SpeedMod = max_bpm_limit
			local playerState = GAMESTATE:GetPlayerState(pn)
			if playerState then
				for _, level in ipairs({"ModsLevel_Preferred", "ModsLevel_Song"}) do
					local playeroptions = playerState:GetPlayerOptions(level)
					if playeroptions then
						playeroptions[speed_type.."Mod"](playeroptions, max_bpm_limit)
					end
				end
			end
			GAMESTATE:ApplyGameCommand("mod," .. speed_type:lower() .. tostring(max_bpm_limit), pn)
			table.insert(AP.ClampedWarnings, "Speed capped to " .. speed_type .. tostring(max_bpm_limit) .. " (Limit: " .. tostring(max_bpm_limit) .. " BPM)")
		end
	elseif speed_type == "X" then
		local bpms = GetDisplayBPMs(pn)
		if bpms and bpms[2] and bpms[2] > 0 then
			local max_chart_bpm = bpms[2]
			local rate = SL.Global.ActiveModifiers.MusicRate or 1.0
			local current_scroll_bpm = speed * max_chart_bpm * rate
			if current_scroll_bpm > max_bpm_limit then
				local max_mult = max_bpm_limit / (max_chart_bpm * rate)
				max_mult = math.floor(max_mult / 0.05) * 0.05
				if max_mult < 0.05 then max_mult = 0.05 end
				
				mods.SpeedMod = max_mult
				local playerState = GAMESTATE:GetPlayerState(pn)
				if playerState then
					for _, level in ipairs({"ModsLevel_Preferred", "ModsLevel_Song"}) do
						local playeroptions = playerState:GetPlayerOptions(level)
						if playeroptions then
							playeroptions:XMod(max_mult)
						end
					end
				end
				GAMESTATE:ApplyGameCommand("mod," .. string.format("%.2f", max_mult) .. "x", pn)
				table.insert(AP.ClampedWarnings, ("Speed capped to %.2fx (Limit: %d BPM)"):format(max_mult, max_bpm_limit))
			end
		end
	end
end

AP.ClampBackgroundFilter = function(pn)
	if not AP.IsEnforcingMods() then return end
	
	local _, max_filter, _, _ = AP.GetModifierStats()
	local pName = ToEnumShortString(pn)
	local mods = SL[pName].ActiveModifiers
	if not mods or not mods.BackgroundFilter then return end
	
	local filter_val = { Off = 0, Dark = 1, Darker = 2, Darkest = 3 }
	local limit_val = filter_val[max_filter] or 0
	local current_val = filter_val[mods.BackgroundFilter] or 0
	if current_val > limit_val then
		local reverse_val = { [0] = "Off", [1] = "Dark", [2] = "Darker", [3] = "Darkest" }
		local clamped_name = reverse_val[limit_val] or "Off"
		mods.BackgroundFilter = clamped_name
		table.insert(AP.ClampedWarnings, "BG Filter capped to " .. clamped_name)
	end
end

AP.ClampMini = function(pn)
	if not AP.IsEnforcingMods() then return end
	
	local max_allowed = AP.GetMaxAllowedMini()
	local pName = ToEnumShortString(pn)
	local mods = SL[pName].ActiveModifiers
	if not mods or not mods.Mini then return end
	
	local current_val = tonumber((tostring(mods.Mini):gsub("%%", ""))) or 0
	if current_val > max_allowed then
		mods.Mini = tostring(max_allowed) .. "%"
		local playerState = GAMESTATE:GetPlayerState(pn)
		if playerState then
			for _, level in ipairs({"ModsLevel_Preferred", "ModsLevel_Song"}) do
				local playeroptions = playerState:GetPlayerOptions(level)
				if playeroptions then
					playeroptions:Mini(max_allowed / 100)
				end
			end
		end
		GAMESTATE:ApplyGameCommand("mod," .. tostring(max_allowed) .. "% mini", pn)
		table.insert(AP.ClampedWarnings, "Mini limited to " .. tostring(max_allowed) .. "%")
	end
end
