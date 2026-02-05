local ev = require "samp.events"
local _, nt = pcall(import, "lib/imgui_notf.lua") -- modified to handle colors
local arz = require "arizona-events"

s = {
	timer = {
		visible = false,
		type = "Unknown",
		time = "",
		value = "",
		setTime = function(t)
			s.timer.time = string.format("%02d:%02d", math.floor(t / 60), t - (math.floor(t/60) * 60))
			if s.timer.time == "" then s.timer.time = t end
		end,
	},
	keyboardHint = {
		visible = false,
		title = "",
		buttons = {},
		cd = function(t)
			if cds.keyboardHint ~= nil then
				cds.keyboardHint:terminate()
			end
			cds.keyboardHint = lua_thread.create(function(time)
				wait(time * 1000)
				s.keyboardHint.visible = false
				cds.keyboardHint = nil
			end, t)
		end
	},
	propertyInfo = {
		visible = false,
		title = "",
		image = nil, -- TODO
		description = "",
		information = {},
		buttons = {},
		cd = function(t)
			if cds.propertyInfo ~= nil then
				cds.propertyInfo:terminate()
			end
			cds.propertyInfo = lua_thread.create(function(time)
				wait(time * 1000)
				s.propertyInfo.visible = false
				cds.propertyInfo = nil
			end, t)
		end
	},
	toast = {
		visible = false,
		title = "",
		description = "",
		icon = "",
		cd = function(t)
			if cds.toast ~= nil then
				cds.toast:terminate()
			end
			cds.toast = lua_thread.create(function(time)
				wait(time)
				s.toast.visible = false
				cds.toast = nil
			end, t)
		end
	},
	questHint = {
		visible = false,
		text = "",
		image = nil, -- TODO
		cd = function(t)
			if cds.questHint ~= nil then
				cds.questHint:terminate()
			end
			cds.questHint = lua_thread.create(function(time)
				wait(time * 1000)
				s.questHint.visible = false
				cds.questHint = nil
			end, t)
		end
	},
	npc = {
		visible = false,
		title = "",
		text = "",
		buttons = {},
	},
	cars = {
		visible = false,
		count = 0,
		max = 1,
		vehicles = {}
	},
}

local mc_compat = false

local TIMER_ENABLED = false

local gui = require "mimgui"
local vk = require "vkeys"
local ffi = require "ffi"
local enc = require "encoding"
enc.default = "CP1251"
local u8 = enc.UTF8

ffi.cdef('struct CVector2D {float x, y;}')
local CRadar_TransformRealWorldPointToRadarSpace = ffi.cast('void (__cdecl*)(struct CVector2D*, struct CVector2D*)', 0x583530)
local CRadar_TransformRadarPointToScreenSpace = ffi.cast('void (__cdecl*)(struct CVector2D*, struct CVector2D*)', 0x583480)
local CRadar_IsPointInsideRadar = ffi.cast('bool (__cdecl*)(struct CVector2D*)', 0x584D40)

function TransformRealWorldPointToRadarSpace(x, y)
    local RetVal = ffi.new('struct CVector2D', {0, 0})
    CRadar_TransformRealWorldPointToRadarSpace(RetVal, ffi.new('struct CVector2D', {x, y}))
    return RetVal.x, RetVal.y
end

function TransformRadarPointToScreenSpace(x, y)
    local RetVal = ffi.new('struct CVector2D', {0, 0})
    CRadar_TransformRadarPointToScreenSpace(RetVal, ffi.new('struct CVector2D', {x, y}))
    return RetVal.x, RetVal.y
end

function IsPointInsideRadar(x, y)
    return CRadar_IsPointInsideRadar(ffi.new('struct CVector2D', {x, y}))
end

function sendcef(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

cds = {
	keyboardHint = nil,
	propertyInfo = nil,
	toast = nil,
}

function getChatPos()
	local strEl = getStructElement(sampGetInputInfoPtr(), 0x8, 4)
    local X = getStructElement(strEl, 0x8, 4) + 12.5
    local Y = getStructElement(strEl, 0xC, 4) + 12.5 
    return {x = X, y = Y}
end

function evalanon(code)
    evalcef(("(() => {%s})()"):format(code))
end

function evalcef(code, encoded)
    encoded = encoded or 0
    local bs = raknetNewBitStream();
    raknetBitStreamWriteInt8(bs, 17);
    raknetBitStreamWriteInt32(bs, 0);
    raknetBitStreamWriteInt16(bs, #code);
    raknetBitStreamWriteInt8(bs, encoded);
    raknetBitStreamWriteString(bs, code);
    raknetEmulPacketReceiveBitStream(220, bs);
    raknetDeleteBitStream(bs);
end

function DeepPrint (t)
  local request_headers_all = ""
  for k, v in pairs(t) do
    if type(v) == "table" then
      request_headers_all = request_headers_all .. "[" .. k .. " " .. DeepPrint(v) .. "] "
    else
      local rowtext = ""
      if type(k) == "string" then
        rowtext = string.format("[%s %s] ", k, v)
      else
        rowtext = string.format("[%s] ", v)
      end    
      request_headers_all = request_headers_all .. rowtext
    end
  end
  return request_headers_all
end

function arz.onArizonaDisplay(packet)	
	if isSampfuncsGlobalVarDefined("ModernControlsInstalled") then
		mc_compat = true
	end

	print(DeepPrint(packet))
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "interactionSidebar") then
		local title = string.match(packet.text, '"title":%s*"([^"]*)"')
		local timer = string.match(packet.text, '"timer":%s*(%d+)')
		local buttons = string.match(packet.text, '"buttons":%s*(%[[^]]*%])')
		--print(buttons)
		buttons = decodeJson(buttons)
		local b = ""
		for i,v in pairs(buttons) do
			b = b .. "[" .. v.keyTitle .. "] " .. v.title .. "\n" 
		end
		if mc_compat then
			runSampfuncsConsoleCommand("moderncontrols.setkey " .. buttons[1].keyTitle)
		end
		if #buttons == 1 and buttons[1].title == "Действие" then
			--nt.addNotification("[" .. buttons[1].keyTitle .."] " .. title, (tonumber(timer) and tonumber(timer) or 7))
			s.keyboardHint.visible = true
			s.keyboardHint.buttons = {{keyTitle = buttons[1].keyTitle, title = title}}
			s.keyboardHint.title = ""
			s.keyboardHint.cd(timer)
		else
			--nt.addNotification(title .."\n" .. b, (tonumber(timer) and tonumber(timer) or 7))
			s.keyboardHint.visible = true
			s.keyboardHint.buttons = buttons
			s.keyboardHint.title = title
			s.keyboardHint.cd(timer)
		end
		
		--print(DeepPrint(buttons))
		return false
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "businessInfo") then
		local title = string.match(packet.text, '"title":%s*"([^"]*)"')
		local description = string.match(packet.text, '"description":%s*"([^"]*)"')
		local timer = string.match(packet.text, '"timer":%s*(%d+)')
		local buttons = string.match(packet.text, '"buttons":%s*(%[[^]]*%])')
		local info = string.match(packet.text, '"info":%s*(%[[^]]*%])')
		--print(buttons)
		buttons = decodeJson(buttons)
		info = decodeJson(info)
		local b = ""
		local inf = ""
		for i,v in pairs(info) do
			inf = inf .. v.title .. ": " .. v.value .. "\n" 
		end
		for i,v in pairs(buttons) do
			b = b .. "[" .. v.keyTitle .. "] " .. v.title .. "\n" 
		end
		
		if mc_compat then
			runSampfuncsConsoleCommand("moderncontrols.setkey " .. buttons[1].keyTitle)
		end
		--nt.addNotification("--- "..title.." ---\n" .. description .."\n\n" .. inf .. "\n" .. b, (tonumber(timer) and tonumber(timer) or 7))
		
		s.propertyInfo.visible = true
		s.propertyInfo.title = title
		s.propertyInfo.buttons = buttons
		s.propertyInfo.information = info
		s.propertyInfo.description = description
		s.propertyInfo.cd(tonumber(timer) and tonumber(timer) or 7)
		--print(DeepPrint(buttons))
		return false
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "dialogTip") then
		local text = string.match(packet.text, '"text":%s*"([^"]*)"')
		s.questHint.visible = true
		s.questHint.text = text
		--nt.addNotification("[i]: " .. text, 7)
		--print(DeepPrint(buttons))
		return false
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "carMenu") then
		--local text = string.match(packet.text, '"text":%s*"([^"]*)"')
		s.cars.visible = true
		--return false
	end
	
	if string.find(packet.text, "event.notify.initialize") then
		local data = string.match(packet.text, '`(.*)`')
		data = decodeJson(data)
		s.toast.visible = true
		s.toast.icon = data[1]
		s.toast.title = data[2]
		s.toast.description = data[3]
		s.toast.cd(data[4])
		--nt.addNotification("[" .. data[1] .. "] " .. data[2] .. "\n" .. data[3], data[4] / 1000)
		return false
	end
	
	if string.find(packet.text, "event.battlepass.MenuPressKeyBattlePass") then
		local data = string.match(packet.text, '`(.*)`')
		data = decodeJson(data)
		if data[2] ~= "" then
			nt.addNotification(data[2] .. "\n" .. data[3], 10)
			return false
		end
	end
	if string.find(packet.text, "cef.modals.closeModal") then
		local modal = decodeJson(string.match(packet.text, '`(.*)`'))[1]
		print(modal)
		if modal == "interactionSidebar" then
			s.keyboardHint.visible = false
		end
		if modal == "businessInfo" then
			s.propertyInfo.visible = false
		end
		if modal == "dialogTip" then
			s.questHint.visible = false
		end
		if modal == "carMenu" then
			s.cars.visible = false
		end
	end
	
	if string.find(packet.text, "event.npcDialog.initializeDialog") then
		local data = decodeJson(string.match(packet.text, "`(.*)`"))
		--print(DeepPrint(data))
		s.npc.title = data[1].title
		s.npc.text = data[1].text
		s.npc.buttons = data[1].keyboard[1]
		--return false
	end
	
	if string.find(packet.text, "event.setActiveView") then
		if string.find(packet.text, '`%["NpcDialog"%]`') then
			s.npc.visible = true
			return false
		end
		
		if string.find(packet.text, "'%[%s*null%s*%]'") then
			s.npc.visible = false
		end
	end
	
	-- TODO: these return falses break phone, reimplement phone first
	
	if TIMER_ENABLED then
		if string.find(packet.text, "event.arizonahud.updateCustomizedCounterVisibility") then
			local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
			s.timer.visible = data
			return not data
		end
		
		if string.find(packet.text, "event.customizedCounter.initializeType") then
			local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
			s.timer.type = data
			--return false
		end
		
		if string.find(packet.text, "event.customizedCounter.initializeCounter") then
			local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
			s.timer.value = data
			--return false
		end
		
		if string.find(packet.text, "event.customizedCounter.initializeTimer") then
			local data, something = string.match(packet.text, '`%[(%d+),%s(%d+)%]`')
			if data then s.timer.setTime(tonumber(data)) end
			--return false
		end
	end
end

------------------------------------------- MIMGUI ONFRAMES ------------------------------------------------

-- Key hint, shown whenever you walk up to something interactive
local keyHintFrame = gui.OnFrame(
	function() return s.keyboardHint.visible and not sampIsChatInputActive() and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
--		if s.keyboardHint.visible and not sampIsChatInputActive() then
		local cpos = getChatPos()
		gui.SetNextWindowPos(gui.ImVec2(cpos.x, cpos.y), 0, gui.ImVec2(0, 0))		
		gui.Begin("keyboardHint", gui.new.bool(s.keyboardHint.visible and not sampIsChatInputActive()), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		if s.keyboardHint.title ~= "" then gui.Text(u8(s.keyboardHint.title)) end
		for i,v in pairs(s.keyboardHint.buttons) do
			gui.HintButton(u8(v.keyTitle), u8(v.title))
		end
		gui.End()
--		end
	end
)


-- Property info, shown when standing on a house/trailer/business entry pickup
local propertyHintFrame = gui.OnFrame(
	function() return s.propertyInfo.visible and not sampIsChatInputActive() and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local cpos = getChatPos()
		gui.SetNextWindowPos(gui.ImVec2(cpos.x, cpos.y), 0, gui.ImVec2(0, 0))		
		gui.Begin("propertyInfo", gui.new.bool(s.keyboardHint.visible and not sampIsChatInputActive()), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.Text(u8(s.propertyInfo.title))
		if s.propertyInfo.description ~= "" then
			gui.Separator()
			gui.TextWrapped(u8(s.propertyInfo.description))
		end
		gui.Separator()
		for i,v in pairs(s.propertyInfo.information) do
			gui.LabelText(u8(v.value), u8(v.title))
		end
		gui.Separator()
		for i,v in pairs(s.propertyInfo.buttons) do
			gui.HintButton(u8(v.keyTitle), u8(v.title))
		end
		gui.End()
	end
)

-- Toasts. They show up at random in the bottom middle of the screen, say, when you lock your car.
local toastFrame = gui.OnFrame(
	function() return s.toast.visible and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy - 10), 0, gui.ImVec2(0.5, 1))
		gui.Begin("toast", gui.new.bool(s.toast.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		if s.toast.text == nil then s.toast.text = "Уведомление" end
		if s.toast.description == nil then s.toast.description = "" end
		gui.Text(u8(s.toast.text))
		gui.Text(u8(s.toast.description))
		gui.End()
	end
)

-- Quest hints. These show up in the bottom right of the screen with an ugly ass picture.
-- Picture is not implemented yet.
local questHintFrame = gui.OnFrame(
	function() return s.questHint.visible and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx - 10, sy - 10), 0, gui.ImVec2(1, 1))
		gui.Begin("questHint", gui.new.bool(s.questHint.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.Text(u8(s.questHint.text))
		gui.End()
	end
)

-- Timer. Shows up when you're doing taxi missions, delivery missions, etc.
-- Color changing is not implemented yet
local timerFrame = gui.OnFrame(
	function() return s.timer.visible and TIMER_ENABLED end,
	function(player)
		player.HideCursor = true
		local rx, ry = TransformRadarPointToScreenSpace(-1, 1)
		gui.SetNextWindowPos(gui.ImVec2(rx, ry - 30), 0, gui.ImVec2(0, 1))
		gui.Begin("timer", gui.new.bool(s.timer.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.TimerTypeText(s.timer.type)
		gui.Text(u8(s.timer.time))
		gui.Text(u8(s.timer.value))
		gui.End()
	end
)

-- NPC Dialog. For dialogs with NPCs.
local npcDialogFrame = gui.OnFrame(
	function() return s.npc.visible end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx - 10, sy - 10), 0, gui.ImVec2(1, 1))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(500, 0), gui.ImVec2(sx, sy))
		gui.Begin("npc", gui.new.bool(s.toast.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
		if not s.npc.title == "" then gui.Text(u8(s.npc.title)) end
		gui.TextWrapped(u8(string.gsub(s.npc.text, "<br>", "\n")))
		for i,v in pairs(s.npc.buttons) do
			if gui.Button(u8(v.text)) then
				sendcef("answer.npcDialog|" .. v.id)
			end
			gui.SameLine()
		end
		gui.End()
	end
)

-- fUCKING CARS MENU


------------------------------------------- MIMGUI FANCIES --------------------------------------------------

function gui.ColoredButton(text,hex,trans,size)
    local r,g,b = tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
    if tonumber(trans) ~= nil and tonumber(trans) < 101 and tonumber(trans) > 0 then a = trans else a = 60 end

    local button = imgui.Button(text, size)
    imgui.PopStyleColor(3)
    return button
end

gui.HintButton = function(button, name)
    	gui.PushStyleColor(gui.Col.Button, gui.ImVec4(1, 1, 1, 1))
    	gui.PushStyleColor(gui.Col.ButtonHovered, gui.ImVec4(0.8, 0.8, 0.8, 1))
    	gui.PushStyleColor(gui.Col.ButtonActive, gui.ImVec4(0.6, 0.6, 0.6, 1))
    	gui.PushStyleColor(gui.Col.Text, gui.ImVec4(0, 0, 0, 1))
	gui.Button(button)
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.SameLine()
	gui.Text(name)
end

gui.TimerTypeText = function(type)
	if type == "taxi" then
		gui.Text(u8"Таксометр")
	else
		gui.Text(u8(type))
	end
end

------------------------------------------------ THEME -------------------------------------------------------

gui.OnInitialize(function()
    themeExample()
end)
function themeExample()
    gui.SwitchContext()
    local ImVec4 = gui.ImVec4
    gui.GetStyle().WindowPadding = gui.ImVec2(5, 5)
    gui.GetStyle().FramePadding = gui.ImVec2(5, 5)
    gui.GetStyle().ItemSpacing = gui.ImVec2(5, 5)
    gui.GetStyle().ItemInnerSpacing = gui.ImVec2(2, 2)
    gui.GetStyle().TouchExtraPadding = gui.ImVec2(0, 0)
    gui.GetStyle().IndentSpacing = 0
    gui.GetStyle().ScrollbarSize = 10
    gui.GetStyle().GrabMinSize = 10
    gui.GetStyle().WindowBorderSize = 0
    gui.GetStyle().ChildBorderSize = 1
    gui.GetStyle().PopupBorderSize = 1
    gui.GetStyle().FrameBorderSize = 1
    gui.GetStyle().TabBorderSize = 1
    gui.GetStyle().WindowRounding = 0
    gui.GetStyle().ChildRounding = 0
    gui.GetStyle().FrameRounding = 0
    gui.GetStyle().PopupRounding = 0
    gui.GetStyle().ScrollbarRounding = 0
    gui.GetStyle().GrabRounding = 0
    gui.GetStyle().TabRounding = 0
 
    gui.GetStyle().Colors[gui.Col.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
    gui.GetStyle().Colors[gui.Col.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
    gui.GetStyle().Colors[gui.Col.WindowBg]               = ImVec4(0.06, 0.06, 0.06, 0.94)
    gui.GetStyle().Colors[gui.Col.ChildBg]                = ImVec4(1.00, 1.00, 1.00, 0.00)
    gui.GetStyle().Colors[gui.Col.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
    gui.GetStyle().Colors[gui.Col.Border]                 = ImVec4(0.43, 0.43, 0.50, 0.50)
    gui.GetStyle().Colors[gui.Col.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
    gui.GetStyle().Colors[gui.Col.FrameBg]                = ImVec4(0.48, 0.16, 0.16, 0.54)
    gui.GetStyle().Colors[gui.Col.FrameBgHovered]         = ImVec4(0.98, 0.26, 0.26, 0.40)
    gui.GetStyle().Colors[gui.Col.FrameBgActive]          = ImVec4(0.98, 0.26, 0.26, 0.67)
    gui.GetStyle().Colors[gui.Col.TitleBg]                = ImVec4(0.04, 0.04, 0.04, 1.00)
    gui.GetStyle().Colors[gui.Col.TitleBgActive]          = ImVec4(0.48, 0.16, 0.16, 1.00)
    gui.GetStyle().Colors[gui.Col.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.51)
    gui.GetStyle().Colors[gui.Col.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
    gui.GetStyle().Colors[gui.Col.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
    gui.GetStyle().Colors[gui.Col.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
    gui.GetStyle().Colors[gui.Col.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
    gui.GetStyle().Colors[gui.Col.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
    gui.GetStyle().Colors[gui.Col.CheckMark]              = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.SliderGrab]             = ImVec4(0.88, 0.26, 0.24, 1.00)
    gui.GetStyle().Colors[gui.Col.SliderGrabActive]       = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.Button]                 = ImVec4(0.98, 0.26, 0.26, 0.40)
    gui.GetStyle().Colors[gui.Col.ButtonHovered]          = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.ButtonActive]           = ImVec4(0.98, 0.06, 0.06, 1.00)
    gui.GetStyle().Colors[gui.Col.Header]                 = ImVec4(0.98, 0.26, 0.26, 0.31)
    gui.GetStyle().Colors[gui.Col.HeaderHovered]          = ImVec4(0.98, 0.26, 0.26, 0.80)
    gui.GetStyle().Colors[gui.Col.HeaderActive]           = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.Separator]              = ImVec4(0.43, 0.43, 0.50, 0.50)
    gui.GetStyle().Colors[gui.Col.SeparatorHovered]       = ImVec4(0.75, 0.10, 0.10, 0.78)
    gui.GetStyle().Colors[gui.Col.SeparatorActive]        = ImVec4(0.75, 0.10, 0.10, 1.00)
    gui.GetStyle().Colors[gui.Col.ResizeGrip]             = ImVec4(0.98, 0.26, 0.26, 0.25)
    gui.GetStyle().Colors[gui.Col.ResizeGripHovered]      = ImVec4(0.98, 0.26, 0.26, 0.67)
    gui.GetStyle().Colors[gui.Col.ResizeGripActive]       = ImVec4(0.98, 0.26, 0.26, 0.95)
    gui.GetStyle().Colors[gui.Col.Tab]                    = ImVec4(0.98, 0.26, 0.26, 0.40)
    gui.GetStyle().Colors[gui.Col.TabHovered]             = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.TabActive]              = ImVec4(0.98, 0.06, 0.06, 1.00)
    gui.GetStyle().Colors[gui.Col.TabUnfocused]           = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.TabUnfocusedActive]     = ImVec4(0.98, 0.26, 0.26, 1.00)
    gui.GetStyle().Colors[gui.Col.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
    gui.GetStyle().Colors[gui.Col.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
    gui.GetStyle().Colors[gui.Col.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
    gui.GetStyle().Colors[gui.Col.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
    gui.GetStyle().Colors[gui.Col.TextSelectedBg]         = ImVec4(0.98, 0.26, 0.26, 0.35)
end
