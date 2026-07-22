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
	local max_bpm = "Default (300)"
	local max_filter = "None"
	local bonus_count = 0

	local speed_items = {
		["Speed 350bpm"] = 350,
		["Speed 450bpm"] = 450,
		["Speed 550bpm"] = 550,
		["Speed 650bpm"] = 650,
		["Speed 750bpm"] = 750,
		["Speed Any BPM"] = 9999,
	}

	local filter_items = {
		["Dark Filter"] = 1,
		["Darker Filter"] = 2,
		["Darkest Filter"] = 3,
	}

	local highest_speed_val = 0
	local highest_filter_val = 0

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
				end
			end
		end
	end

	return max_bpm, max_filter, bonus_count
end
