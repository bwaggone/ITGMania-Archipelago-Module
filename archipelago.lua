-- Module configuration / shared state
local AP = {}

-- Constants
AP.HOST = "ws://localhost:38281"
AP.SLOT = "ITGManiaPlayer"
AP.PASSWORD = ""
AP.MODULE_TAG = "[AP-Module]"
AP.ENABLE_PENDING_SCORES = true
AP.MAX_PENDING_SCORES = 50
AP.GAME_NAME = "ITGMania"

-- State
AP.apHandler = nil
AP.apHandlerInstance = nil
AP.apHandlerShuttingDown = false
AP.itemNames = {}
AP.locationIds = {}
AP.folderToChartName = {}
AP.seedName = "Unknown"
AP.AP_AllReceivedItems = {}
AP.bonusUsage = {}
AP.initialSyncComplete = false
AP.hasShownConnectedPopup = false
AP.slotOptions = {
	score_type = 1,
	passing_score = 0,
	fail_allowed = false,
}

-- UI state
AP.notificationQueue = {}
AP.isNotificationActive = false

-- Define local logging wrappers that prepend MODULE_TAG to all screen and log outputs
local original_SM = SM
AP.AP_SM = function(msg)
	if original_SM then
		original_SM(AP.MODULE_TAG .. " " .. tostring(msg))
	else
		SCREENMAN:SystemMessage(AP.MODULE_TAG .. " " .. tostring(msg))
	end
end

local original_Trace = Trace
AP.Trace = function(msg)
	if original_Trace then
		original_Trace(AP.MODULE_TAG .. " " .. tostring(msg))
	else
		print(AP.MODULE_TAG .. " " .. tostring(msg))
	end
end

AP.AP_SM("Hola from lua!")

-- Guarded stub declarations (only for tooling; real objects provided by engine at runtime)
if not PROFILEMAN then PROFILEMAN = { GetProfileDir = function(...) return "" end } end
if not NETWORK then NETWORK = { HttpRequest = function(...) return {} end } end
if not FILEMAN then FILEMAN = { DoesFileExist = function(...) return false end, GetDirListing = function(...) return {} end, Remove = function(...) return true end } end

-- Global getter for apHandlerInstance
GetAPHandlerInstance = function()
	return AP.apHandlerInstance
end

-- Helper to load sub-files
local function loadSubFile(filename)
	local path = THEME:GetCurrentThemeDirectory() .. "Modules/Archipelago/" .. filename
	local chunk, err = loadfile(path)
	if not chunk then
		AP.Trace("Archipelago error loading " .. filename .. ": " .. tostring(err))
		error("Archipelago failed to load sub-file: " .. filename)
	end
	
	-- Run the chunk and pass the shared AP context
	local success, result = pcall(chunk, AP)
	if not success then
		AP.Trace("Archipelago error running " .. filename .. ": " .. tostring(result))
		error("Archipelago failed to execute sub-file: " .. filename)
	end
	return result
end

-- Load Archipelago components
loadSubFile("helpers.lua")
loadSubFile("playlist.lua")
loadSubFile("item_handler.lua")
loadSubFile("evaluator.lua")
loadSubFile("message_handler.lua")
loadSubFile("actor_handler.lua")
loadSubFile("ui.lua")

-- Start the connection handler
AP.CreateAPHandler()
AP.apHandler:InitCommand()

-- Build modules table for Simply Love screen registration
local screens = {
	"ScreenTitleMenu",
	"ScreenSelectMusic",
	"ScreenEvaluationNormal",
	"ScreenEvaluationStage",
	"ScreenEvaluationNonstop"
}

local modules = {}
for _, screen in ipairs(screens) do
	modules[screen] = AP.MakeScreenActor(screen)
end

return modules
