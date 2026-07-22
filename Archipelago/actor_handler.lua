-- actor_handler.lua is our main init of the apHandler. It handles the initial
-- websocket startup as well.

local AP = ...

AP.CreateAPHandler = function() 
  if AP.apHandler == nil then
    AP.apHandler = Def.ActorFrame{
      Name="ArchipelagoHandler",
		InitCommand=function(self)
			AP.apHandlerInstance = self
			AP.apHandlerShuttingDown = false
			self.socket = nil
			self.connected = false
			self.errorMsg = nil

			AP.AP_SM("Connecting to Archipelago server at: " .. AP.HOST)

			-- Connection time.
			self.socket = NETWORK:WebSocket{
				url=AP.HOST,
				pingInterval=15,
				automaticReconnect=true,
				enableDeflate=true,
				onMessage=function(msg)
					AP.HandleMessage(self, msg)
				end
			}
        end,
      }
  end

  return AP.apHandler
end

AP.MakeScreenActor = function(screenName)
	local af = Def.ActorFrame {
		AP.MakePopupActor(screenName),
	}
	
	if screenName == "ScreenSelectMusic" then
		-- Small helper text in the footer: "Press F10 for AP Status"
		af[#af+1] = LoadFont("Common Normal") .. {
			Name = "APStatusHelperText",
			Text = "Press F10 for AP Status",
			InitCommand = function(self)
				self:xy(_screen.cx + SL_WideScale(138, 191), _screen.h - 9)
				self:zoom(SL_WideScale(0.8, 0.9))
				self:diffusealpha(0)
				self:halign(0.5):valign(1)
			end,
			ModuleCommand = function(self)
				self:stoptweening()
				self:diffusealpha(0):sleep(0.1):decelerate(0.33):diffusealpha(1)
			end
		}
		
		af[#af+1] = AP.MakeStatusOverlayActor()
	end
	
	if screenName:find("ScreenEvaluation") then
		af[#af+1] = Def.Actor {
			ModuleCommand = function(self)
				AP.EvaluateCompletedSong()
			end
		}
		af[#af+1] = AP.MakeEvaluationOverlayActor()
	end
	
	return af
end

