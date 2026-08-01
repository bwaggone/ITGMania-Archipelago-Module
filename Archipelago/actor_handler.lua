-- actor_handler.lua defines theme actors and screen hooks,
-- delegating connection logic to network.lua.

local AP = ...

AP.MakeScreenActor = function(screenName)
	local af = Def.ActorFrame {}
	
	-- Only add standard popup notifications if it's NOT gameplay to avoid distractions during play
	if screenName ~= "ScreenGameplay" then
		af[#af+1] = AP.MakePopupActor(screenName)
	end

	if screenName == "ScreenSelectMusic" then
		af[#af+1] = Def.Actor {
			ModuleCommand = function(self)
				AP.ClampedWarnings = {} -- Reset warnings on music wheel
				if AP.seedName and AP.seedName ~= "Unknown" and SONGMAN:GetPreferredSortSongs() then
					local top = SCREENMAN:GetTopScreen()
					if top and top:GetName() == "ScreenSelectMusic" then
						local wheel = top:GetMusicWheel()
						if wheel then
							wheel:ChangeSort("SortOrder_Preferred")
						end
					end
				end
			end
		}
		
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


	if screenName == "ScreenGameplay" then
		-- Custom pop-up warning for clamped modifiers on song start
		af[#af+1] = Def.ActorFrame {
			Name = "APGameplayWarningFrame",
			InitCommand = function(self)
				self:xy(_screen.cx, _screen.cy - 120)
				self:diffusealpha(0)
			end,
			ModuleCommand = function(self)
				if AP.ClampedWarnings and #AP.ClampedWarnings > 0 then
					self:playcommand("ShowWarning")
				end
			end,
			ShowWarningCommand = function(self)
				local warning_text = table.concat(AP.ClampedWarnings, "\n")
				local subtext = self:GetChild("Subtext")
				if subtext then
					subtext:settext(warning_text)
				end
				
				-- slide/fade in, hold for 3.5 seconds, fade out
				self:finishtweening()
				self:diffusealpha(0):y(_screen.cy - 140)
				self:decelerate(0.4):diffusealpha(1):y(_screen.cy - 120)
				self:sleep(3.5)
				self:accelerate(0.4):diffusealpha(0):y(_screen.cy - 100)
			end,
			
			-- Background box
			Def.Quad {
				InitCommand = function(self)
					self:zoomto(500, 80)
					self:diffuse(0.05, 0.05, 0.05, 0.85)
				end
			},
			-- Accent outline / border with a yellow color
			Def.Quad {
				InitCommand = function(self)
					self:zoomto(4, 80):x(-250)
					self:diffuse(0.9, 0.8, 0.1, 1) -- yellow warning accent
				end
			},
			-- Warning Title
			LoadFont("Common Bold") .. {
				Text = "ARCHIPELAGO MODIFIERS CLAMPED",
				InitCommand = function(self)
					self:y(-22):zoom(0.65)
					self:diffuse(0.9, 0.8, 0.1, 1) -- yellow warning title
				end
			},
			-- Clamped details subtext
			LoadFont("Common Normal") .. {
				Name = "Subtext",
				Text = "",
				InitCommand = function(self)
					self:y(12):zoom(0.65)
					self:diffuse(0.9, 0.9, 0.9, 1)
				end
			}
		}
		
		-- Hook PlayerOptionsChanged to enforce clamped speed if changed mid-song before first note
		af[#af+1] = Def.Actor {
			PlayerOptionsChangedMessageCommand = function(self, params)
				-- guard from recursion when we re-broadcast our clamp below
				if params and params.Clamped then return end
				if params and params.Player then
					local pn = params.Player
					AP.ClampedWarnings = {}
					AP.ClampSpeedMod(pn)
					if #AP.ClampedWarnings > 0 then
						-- Format and apply new clamped speed immediately to the engine
						local pName = ToEnumShortString(pn)
						local mods = SL[pName].ActiveModifiers
						local fmt = {
							X = "mod,%.2fx",
							C = "mod,c%d",
							M = "mod,m%d"
						}
						local speed_type = mods.SpeedModType or "X"
						local gcString = fmt[speed_type]:format(mods.SpeedMod)
						GAMESTATE:ApplyGameCommand(gcString, pn)
						
						-- Re-broadcast option change so displays update, but guard from recursion
						MESSAGEMAN:Broadcast("PlayerOptionsChanged", {Player=pn, Clamped=true})
					end
				end
			end
		}
	end
	
	return af
end
