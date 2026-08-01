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

