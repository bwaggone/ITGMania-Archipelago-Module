-- This file hanldes AP communication with the server, which includes
-- populating the local map of items to human readable names.

local AP = ...

AP.HandleMessage = function(self, msg)
	if msg.type == "WebSocketMessageType_Open" then
		AP.AP_SM("WebSocket transport connected. Waiting for RoomInfo...")
	elseif msg.type == "WebSocketMessageType_Close" then
		self.connected = false
		AP.initialSyncComplete = false
		AP.connectedSlotName = nil
		AP.AP_SM("Archipelago connection closed: " .. tostring(msg.reason))
		AP.QueueNotification({ type = "Disconnected" })
	elseif msg.type == "WebSocketMessageType_Error" then
		self.connected = false
		AP.initialSyncComplete = false
		AP.connectedSlotName = nil
		AP.AP_SM("Archipelago connection error: " .. tostring(msg.reason))
		AP.QueueNotification({ type = "Disconnected" })
	elseif msg.type == "WebSocketMessageType_Message" then
		local success, packets = pcall(JsonDecode, msg.data)
		if not success then
			AP.AP_SM("Failed to decode JSON from Archipelago server: " .. tostring(msg.data))
			return
		end

		for _, packet in ipairs(packets) do
			local packet_cmd = packet["cmd"]
			if packet_cmd == "RoomInfo" then
				AP.seedName = packet["seed_name"] or "Unknown"
				AP.LoadCacheFromDisk()
				AP.AP_SM("Received RoomInfo (Seed: " .. AP.seedName .. "). Requesting DataPackage...")
				local get_dp_packet = {
					["cmd"] = "GetDataPackage",
					games = packet["games"]
				}
				local payload = JsonEncode({ get_dp_packet })
				self.socket:Send(payload, false)
			elseif packet_cmd == "DataPackage" then
				local games = packet.data and packet.data.games
				
				AP.datapackage = AP.datapackage or {}
				if games then
					for game_name, game_package in pairs(games) do
						AP.datapackage[game_name] = {
							itemNames = {},
							locationNames = {}
						}
						local item_to_id = game_package.item_name_to_id
						if item_to_id then
							for name, id in pairs(item_to_id) do
								AP.datapackage[game_name].itemNames[tostring(id)] = name
							end
						end
						local location_to_id = game_package.location_name_to_id
						if location_to_id then
							for name, id in pairs(location_to_id) do
								AP.datapackage[game_name].locationNames[tostring(id)] = name
							end
						end
					end
				end

				local game_data = games and games[AP.GAME_NAME]
				local item_to_id = game_data and game_data.item_name_to_id
				local location_to_id = game_data and game_data.location_name_to_id

				AP.itemNames = {}
				local count = 0
				if item_to_id then
					for name, id in pairs(item_to_id) do
						AP.itemNames[id] = name
						AP.itemNames[tostring(id)] = name
						count = count + 1
					end
				end

				AP.locationIds = {}
				AP.folderToChartName = {}
				local loc_count = 0
				local cached_folders = 0
				if location_to_id then
					for name, id in pairs(location_to_id) do
						AP.locationIds[name] = id
						loc_count = loc_count + 1
						
						if name:match("%-0$") then
							local base_chart = name:gsub("%-0$", "")
							local parts = {}
							for part in base_chart:gmatch("[^/]+") do
								table.insert(parts, part)
							end
							local folderName = nil
							if #parts >= 2 then
								folderName = parts[2]
							elseif #parts == 1 then
								folderName = parts[1]
							end
							if folderName then
								AP.folderToChartName[folderName] = base_chart
								cached_folders = cached_folders + 1
							end
						end
					end
				end
				AP.AP_SM("Loaded " .. tostring(count) .. " item names, " .. tostring(loc_count) .. " locations, and " .. tostring(cached_folders) .. " folder mappings from DataPackage.")

				-- Save updated cache to disk
				AP.SaveCacheToDisk()

				AP.AP_SM("Sending Connect packet...")
				local connect_packet = {
					["cmd"] = "Connect",
					game = AP.GAME_NAME,
					name = AP.SLOT,
					uuid = "itgmania-ap-client-uuid",
					version = { major = 0, minor = 6, build = 8, ["class"] = "Version" },
					items_handling = 7, -- Receive all items (remote, own, starting)
					password = AP.PASSWORD,
					tags = {},
					slot_data = true
				}
				local connect_payload = JsonEncode({ connect_packet })
				self.socket:Send(connect_payload, false)
			elseif packet_cmd == "Connected" then
				self.connected = true
				AP.initialSyncComplete = false
				AP.connectedSlotName = packet.slot
				AP.SLOT = packet.slot
				AP.LoadBonusUsage()
				AP.AP_SM("Successfully connected to Archipelago! Slot: " .. tostring(packet.slot))
				
				-- Store players and slot info
				AP.playerNames = AP.playerNames or {}
				if packet["players"] then
					for _, player in ipairs(packet["players"]) do
						AP.playerNames[player.slot] = player.alias or player.name
					end
				end

				AP.slotInfo = AP.slotInfo or {}
				if packet["slot_info"] then
					for slot_id, info in pairs(packet["slot_info"]) do
						local id = tonumber(slot_id) or slot_id
						AP.slotInfo[id] = {
							name = info.name,
							game = info.game,
							type = info.type
						}
					end
				end

				-- Save updated cache to disk
				AP.SaveCacheToDisk()

				AP.checkedLocations = {}
				AP.activeLocationIds = {}
				if packet["checked_locations"] then
					for _, loc_id in ipairs(packet["checked_locations"]) do
						AP.checkedLocations[loc_id] = true
						AP.activeLocationIds[loc_id] = true
					end
				end
				if packet["missing_locations"] then
					for _, loc_id in ipairs(packet["missing_locations"]) do
						AP.activeLocationIds[loc_id] = true
					end
				end
				
				if packet["slot_data"] then
					AP.slotOptions.score_type = packet["slot_data"]["score_type"] or 1
					AP.slotOptions.passing_score = packet["slot_data"]["passing_score"] or 0
					AP.slotOptions.fail_allowed = packet["slot_data"]["fail_allowed"]
					AP.slotOptions.win_count = packet["slot_data"]["win_count"] or 15
					AP.AP_SM("Slot Options - Score Type: " .. tostring(AP.slotOptions.score_type) .. 
					   ", Passing Score: " .. tostring(AP.slotOptions.passing_score) .. 
					   ", Fail Allowed: " .. tostring(AP.slotOptions.fail_allowed) ..
					   ", Win Count: " .. tostring(AP.slotOptions.win_count))
				end
			elseif packet_cmd == "RoomUpdate" then
				AP.AP_SM("Received RoomUpdate from server.")
				
				if packet["checked_locations"] then
					if not AP.checkedLocations then AP.checkedLocations = {} end
					if not AP.activeLocationIds then AP.activeLocationIds = {} end
					for _, loc_id in ipairs(packet["checked_locations"]) do
						AP.checkedLocations[loc_id] = true
						AP.activeLocationIds[loc_id] = true
					end
				end
				
				if packet["slot_data"] then
					AP.slotOptions.score_type = packet["slot_data"]["score_type"] or AP.slotOptions.score_type
					AP.slotOptions.passing_score = packet["slot_data"]["passing_score"] or AP.slotOptions.passing_score
					AP.slotOptions.fail_allowed = packet["slot_data"]["fail_allowed"] or AP.slotOptions.fail_allowed
					AP.slotOptions.win_count = packet["slot_data"]["win_count"] or AP.slotOptions.win_count
					AP.AP_SM("Updated Slot Options - Score Type: " .. tostring(AP.slotOptions.score_type) .. 
					   ", Passing Score: " .. tostring(AP.slotOptions.passing_score) .. 
					   ", Fail Allowed: " .. tostring(AP.slotOptions.fail_allowed) ..
					   ", Win Count: " .. tostring(AP.slotOptions.win_count))
				end
			elseif packet_cmd == "ConnectionRefused" then
				self.connected = false
				local errs = packet.errors or {}
				local errStr = table.concat(errs, ", ")
				AP.AP_SM("Archipelago connection refused: " .. errStr)
			elseif packet_cmd == "PrintJSON" then
				local message = AP.ParsePrintJSON(packet.data)
				AP.AP_SM(message)
				
				-- If it's an ItemSend and we are the finder but not the receiver (foreign item sent)
				if packet.type == "ItemSend" and packet.item then
					local finder = packet.item.player
					local receiver = packet.receiving
					if finder == AP.SLOT and receiver ~= AP.SLOT then
						local item_id = packet.item.item
						local itemName = AP.GetItemName(item_id, receiver)
						local receiverName = AP.GetPlayerName(receiver)
						AP.QueueNotification({
							type = "Sent",
							name = itemName,
							receiver = receiverName
						})
					end
				end
			elseif packet_cmd == "ReceivedItems" then
				local item_count = packet.items and #packet.items or 0
				local base_idx = packet["index"] or 0
				AP.AP_SM("Received " .. tostring(item_count) .. " items from server (index " .. tostring(base_idx) .. ")")
				if packet.items then
					local isNewItem = self.connected and AP.initialSyncComplete
					if base_idx == 0 then
						AP.AP_AllReceivedItems = {}
					end
					for i, item in ipairs(packet.items) do
						AP.AP_AllReceivedItems[base_idx + i] = item
						local item_id = item.item
						local name = AP.itemNames[item_id] or "Unknown Item"
						if name:find("/") then
							AP.AP_SM("Received Song: " .. name .. " (ID=" .. tostring(item_id) .. ", Location=" .. tostring(item.location) .. ", Player=" .. tostring(item.player) .. ")")
						else
							AP.AP_SM("Received Mod/Filler (Non-Song): " .. name .. " (ID=" .. tostring(item_id) .. ", Location=" .. tostring(item.location) .. ", Player=" .. tostring(item.player) .. ")")
						end
						if isNewItem then
							local sender = AP.GetPlayerName(item.player)
							AP.QueueNotification({ type = "Received", name = name, sender = sender })
						end
					end
					AP.initialSyncComplete = true
					AP.UpdatePlaylist()
					
					if AP.connectedSlotName then
						AP.QueueNotification({ type = "Connected", name = AP.connectedSlotName })
						AP.connectedSlotName = nil
					end
				end
			else
				AP.Trace("Received unhandled cmd: " .. tostring(packet_cmd))
			end
		end
	end
end
