local ev = require "samp.events"
local _, nt = pcall(import, "lib/imgui_notf.lua") -- modified to handle colors
local arz = require "arizona-events"
local fa = require('fAwesome6')
local mc_compat = false
local gui = require "mimgui"
local vk = require "vkeys"
local ffi = require "ffi"
local enc = require "encoding"
enc.default = "CP1251"
local u8 = enc.UTF8


local cfg = require "inicfg"

local cfgOpenerDialog = {
	id = 0,
	item = 0
}

c = cfg.load({
main = {
	disableOriginalInterfaces = true,
	useCustomTimer = false,
	leftAlignedCars = false,
	centeredCarInfoPanel = true,
},
}, "../ArizonaMimgui/config.ini")

function save()
	cfg.save(c, "../ArizonaMimgui/config.ini")
end

s = {
	settings = {
		visible = gui.new.bool(false),
	},
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
	carinfo = {
		visible = false,
		info = {},
		labels = {},
		toggles = {},
		buttons = {},
		radials = {},
		stats = {},
	},
}

bonusname = {
	[0] = "Ржавеет",
	[1] = "Разбитые стёкла",
	[2] = "Чёрный дым",
	[3] = "Искры из выхлопа",
	[4] = "Продажа в гос ниже",
	[5] = "Нет ржавчины или царапин",
	[6] = "Целые стёкла",
	[7] = "Стандартный расход топлива",
	[8] = "Стандартная скорость поломки",
	[9] = "Стандартная скорость загрязнения",
	[10] = "Пониженный расход топлива",
	[11] = "Пониженная скорость износа состояния и масла",
	[12] = "Транспорт не пачкается",
	[13] = "Бонус к ХП",
	[14] = "Бонус к продаже в гос",
	[15] = "Увеличенное ускорение",
	[16] = "Бесячие искры",
	[17] = "Цвет тормозных суппортов",
	[18] = "Качественная резина",
	[26] = "Повышенная максимальная скорость",
}

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

gui.OnInitialize(function()
    gui.GetIO().IniFilename = nil
    local config = gui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = gui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    gui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 14, config, iconRanges) -- solid - тип иконок, так же есть thin, regular, light и duotone
end)

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
		return not c.main.disableOriginalInterfaces
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
		return not c.main.disableOriginalInterfaces
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "dialogTip") then
		local text = string.match(packet.text, '"text":%s*"([^"]*)"')
		s.questHint.visible = true
		s.questHint.text = text
		--nt.addNotification("[i]: " .. text, 7)
		--print(DeepPrint(buttons))
		return not c.main.disableOriginalInterfaces
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "carMenu") then
		--local text = string.match(packet.text, '"text":%s*"([^"]*)"')
		s.cars.visible = true
		s.carinfo.visible = false
		s.cars.vehicles = {}
		sendcef("vehicleMenu.loadList")
		return not c.main.disableOriginalInterfaces
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushVehicleItem") then
		if not string.find(packet.text, '`%[%s*null%s*%]`') then
			local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
			--print(DeepPrint(data))
			local exists = false
			for i,v in pairs(s.cars.vehicles) do
				if v.id == data.id then exists = true end
			end
			if not exists then table.insert(s.cars.vehicles, data) end
		end
	end
	
	if string.find(packet.text, "event.vehicleMenu.setVehicleUsedSlot") then
		local e = string.match(packet.text, '`%[(%d+)%]`')
		s.cars.count = e
	end
	
	if string.find(packet.text, "event.vehicleMenu.setVehicleMaxSlot") then
		local e = string.match(packet.text, '`%[(%d+)%]`')
		s.cars.max = e
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
		return not c.main.disableOriginalInterfaces
	end
	
	--[[if string.find(packet.text, "event.battlepass.MenuPressKeyBattlePass") then
		local data = string.match(packet.text, '`(.*)`')
		data = decodeJson(data)
		if data[2] ~= "" then
			nt.addNotification(data[2] .. "\n" .. data[3], 10)
			return not c.main.disableOriginalInterfaces
		end
	end]]
	
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
			s.carinfo.visible = false
			s.cars.vehicles = {}
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
			return not c.main.disableOriginalInterfaces
		end
		
		if string.find(packet.text, "'%[%s*null%s*%]'") then
			s.npc.visible = false
		end
	end
	
	if string.find(packet.text, "event.vehicleMenu.setVehicleInfoList") then
		s.carinfo.visible = true
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushLabels") then
		s.carinfo.labels = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	if string.find(packet.text, "event.vehicleMenu.initializeVehicleInformation") then
		s.carinfo.info = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushToggles") then
		s.carinfo.toggles = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushActions") then
		s.carinfo.buttons = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushRadials") then
		s.carinfo.radials = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushStats") then
		s.carinfo.stats = decodeJson(string.match(packet.text, '`(.*)`'))[1]
	end
	
	-- TODO: these return falses break phone, reimplement phone first
	
	if c.main.useCustomTimer then
		if string.find(packet.text, "event.arizonahud.updateCustomizedCounterVisibility") then
			local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
			s.timer.visible = data
			return not data and not c.main.disableOriginalInterfaces
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
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300, 0), gui.ImVec2(sx, sy))
		gui.Begin("npc", gui.new.bool(s.npc.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
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

-- settings for the mod
local settingsFrame = gui.OnFrame(
	function() return s.settings.visible[0] end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300, 0), gui.ImVec2(300, sy))
		gui.Begin("settings", s.settings.visible, gui.WindowFlags.AlwaysAutoResize)
		
		for i,v in pairs(c.main) do
			gui.Checkbox(u8(i), gui.new.bool(v))
			if gui.IsItemClicked() then
				c.main[i] = not c.main[i]
				save()
			end
		end
		
		gui.End()
	end
)

-- fUCKING CARS MENU
local carsFrame = gui.OnFrame(
	function() return s.cars.visible and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2((c.main.leftAlignedCars and 0 or sx), sy/2), 0, gui.ImVec2((c.main.leftAlignedCars and 0 or 1), 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300, 0), gui.ImVec2(300, sy))
		gui.Begin("cars", gui.new.bool(s.cars.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
		gui.Text(u8"Мой автопарк")
		gui.SameLine()
		if gui.Button(u8"Рейтинг") then
			sendcef("vehicleMenu.openRating")
		end
		gui.SameLine()
		if gui.Button(u8"Закрыть") then
			sendcef("vehicleMenu.close")
		end
		gui.TextDisabled(u8("Слоты: " .. s.cars.count .. "/" .. s.cars.max))
		
		for i,v in pairs(s.cars.vehicles) do -- favs, loaded
			if v.favorite > 0 and v.status == "loaded" then
				gui.CarInfoCard(i, v)
			end
		end
	
		for i,v in pairs(s.cars.vehicles) do -- non favs, loaded
			if v.favorite == 0 and v.status == "loaded" then
				gui.CarInfoCard(i, v)
			end
		end
		
		for i,v in pairs(s.cars.vehicles) do -- favs, not loaded
			if v.favorite > 0 and v.status ~= "loaded" then
				gui.CarInfoCard(i, v)
			end
		end
		
		for i,v in pairs(s.cars.vehicles) do -- non favs, not loaded
			if v.favorite == 0 and v.status ~= "loaded" then
				gui.CarInfoCard(i, v)
			end
		end
	end
)

function gui.CarInfoCard(i, v)
	gui.BeginChild("car"..i, gui.ImVec2(280, 120), true)
	if v.favorite > 0 then
		gui.PushStyleColor(gui.Col.Button, gui.ImVec4(1, 1, 0, 1))
    		gui.PushStyleColor(gui.Col.ButtonHovered, gui.ImVec4(0.8, 0.8, 0, 1))
    		gui.PushStyleColor(gui.Col.ButtonActive, gui.ImVec4(0.6, 0.6, 0, 1))
    		gui.PushStyleColor(gui.Col.Text, gui.ImVec4(0, 0, 0, 1))
    	else
    		gui.PushStyleColor(gui.Col.Button, gui.ImVec4(0.2, 0.2, 0.2, 0.5))
    		gui.PushStyleColor(gui.Col.ButtonHovered, gui.ImVec4(0.2, 0.2, 0.2, 1))
    		gui.PushStyleColor(gui.Col.ButtonActive, gui.ImVec4(0.4, 0.4, 0.4, 1))
    		gui.PushStyleColor(gui.Col.Text, gui.ImVec4(1, 1, 1, 0.7))
    	end
	if gui.Button(fa("STAR")) then
		sendcef("vehicleMenu.vehicle-item.facorite|" .. v.id)
	end
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.Hint("car"..i.."hint", u8("Переключить избранное для машины " .. v.id))
	gui.SameLine()
	if v.status == "loaded" then
		gui.Text(u8(v.title))
	else
		gui.TextDisabled(u8(v.title))
	end
	--gui.Text("" .. v.status)
	gui.Text(u8"Редкость: ")
	gui.SameLine()
	rarity(v.rarity)
	gui.SameLine()
	gui.TextDisabled(u8("" .. v.rarityLevel))
	
	gui.PushStyleColor(gui.Col.Button, gui.ImVec4(0.2, 0.2, 0.2, 0.5))
	gui.PushStyleColor(gui.Col.ButtonHovered, gui.ImVec4(0.2, 0.2, 0.2, 1))
	gui.PushStyleColor(gui.Col.ButtonActive, gui.ImVec4(0.2, 0.2, 0.2, 1))
	gui.PushStyleColor(gui.Col.Text, gui.ImVec4(1, 1, 1, 1))
	
	for u,w in pairs(v.labels) do
		gui.Button(u8(w.title))
		gui.SameLine()
	end
	
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	gui.PopStyleColor()
	
	gui.NewLine()
	if gui.Button(u8"Подробнее") then
		sendcef("vehicleMenu.loadVehicleInfo|" .. v.id)
	end
	
	gui.EndChild()
end

-- car info page
local carInfoFrame = gui.OnFrame(
	function() return s.carinfo.visible and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function(player)
		local sx, sy = getScreenResolution()
		if c.main.centeredCarInfoPanel then
			gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		else
			gui.SetNextWindowPos(gui.ImVec2((c.main.leftAlignedCars and 0 or sx), sy/2), 0, gui.ImVec2((c.main.leftAlignedCars and 0 or 1), 0.5))
		end
		gui.SetNextWindowSizeConstraints(gui.ImVec2(400, 0), gui.ImVec2(400, sy))
		gui.Begin("carinfo", gui.new.bool(s.carinfo.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
		if gui.Button(u8("«")) then
			sendcef("vehicleMenu.backToList")
			s.carinfo.visible = false
			s.cars.vehicles = {}
			sendcef("vehicleMenu.loadList")
		end
		gui.SameLine()
		if gui.Button(fa("PEN")) then
			sendcef("vehicleMenu.rename")
		end
		gui.SameLine()
		gui.Text(u8(s.carinfo.info.title))
		rarity(s.carinfo.info.rarity)
		gui.SameLine()
		gui.TextDisabled("" .. s.carinfo.info.rarityLevel)
		if #s.carinfo.info.bonuses > 0 then
			local bns = ""
			for u,w in pairs(s.carinfo.info.bonuses) do
				bns = bns .. (bonusname[w.id] and bonusname[w.id] or w.id) .. (w.valueString == "" and "" or (": " .. w.valueString)) .. "\n"		
			end
			gui.Hint("hintBonuses", u8(bns))
		end
		
		if s.carinfo.info.ratingPosition then gui.Text(u8("Позиция в рейтинге: " .. s.carinfo.info.ratingPosition)) end
		
		gui.PushStyleColor(gui.Col.Button, gui.ImVec4(0.2, 0.2, 0.2, 0.5))
		gui.PushStyleColor(gui.Col.ButtonHovered, gui.ImVec4(0.2, 0.2, 0.2, 1))
		gui.PushStyleColor(gui.Col.ButtonActive, gui.ImVec4(0.2, 0.2, 0.2, 1))
		gui.PushStyleColor(gui.Col.Text, gui.ImVec4(1, 1, 1, 1))
		
		for i,v in pairs(s.carinfo.labels) do
			gui.Button(u8(v.title))
			local icon = string.gsub(v.icon, "icon-", "")
			gui.Hint("labelHint" .. i, u8(icon))
			gui.SameLine()
		end
		
		gui.PopStyleColor()
		gui.PopStyleColor()
		gui.PopStyleColor()
		gui.PopStyleColor()
		
		gui.NewLine()
		gui.Separator()
		gui.Columns(4)
		for i,v in pairs(s.carinfo.buttons) do
			if gui.Button(u8(v.title)) then
				sendcef("vehicleMenu.buttonClick|"..v.id)
			end
			gui.NextColumn()
		end
		gui.Columns(1)
		gui.Separator()
		gui.Columns(3)
		
		for i,v in pairs(s.carinfo.toggles) do
			local cb = gui.new.bool(v.value == 1)
			gui.Checkbox(u8(v.title), cb)
			if gui.IsItemClicked() then
				sendcef("vehicleMenu.switchToggle|" .. v.id .. "|" .. (v.value == 0 and "true" or "false"))
			end
			gui.NextColumn()
		end
		gui.Columns(1)
		gui.Separator()
		
		gui.Columns(2)
		for i,v in pairs(s.carinfo.radials) do
			gui.ProgressBar(v.value / v.maxValue, nil, u8(v.title .. ": " .. v.value .. "/" .. v.maxValue .. v.postfix))
			gui.NextColumn()
		end
		gui.Columns(1)
		gui.Separator()
		gui.Columns(2)
		for i,v in pairs(s.carinfo.stats) do
			gui.TextInColor(u8(v.title), gui.ImVec4(1, 1, 0.7, 1))
			gui.NextColumn()
			gui.Text(u8(v.value))
			gui.NextColumn()
		end
		gui.End()
	end
)

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

gui.TextInColor = function(text, color)
	gui.PushStyleColor(gui.Col.Text, color)
	gui.Text(text)
	gui.PopStyleColor()
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

function rarity(rar)
	if tonumber(rar) then
		local r = tonumber(rar)
		if r == 0 then
			return gui.TextInColor(u8"Не определена", gui.ImVec4(0.7, 0.7, 0.7, 1))
		elseif r == 1 then
			return gui.TextInColor(u8"Хлам", gui.ImVec4(0.7, 0.7, 0.7, 1))
		elseif r == 2 then
			return gui.TextInColor(u8"Обычный", gui.ImVec4(0.5, 0.5, 1.0, 1))
		elseif r == 3 then
			return gui.TextInColor(u8"Легендарный", gui.ImVec4(1, 1, 0.2, 1))
		end
	else
		return gui.TextInColor(u8"Не определена", gui.ImVec4(1, 0.7, 0.7, 1))
	end
end



function gui.Hint(str_id, hint, delay)
    local hovered = gui.IsItemHovered()
    local animTime = 0.2
    local delay = delay or 0.00
    local show = true

    if not allHints then allHints = {} end
    if not allHints[str_id] then
        allHints[str_id] = {
            status = false,
            timer = 0
        }
    end

    if hovered then
        for k, v in pairs(allHints) do
            if k ~= str_id and os.clock() - v.timer <= animTime  then
                show = false
            end
        end
    end

    if show and allHints[str_id].status ~= hovered then
        allHints[str_id].status = hovered
        allHints[str_id].timer = os.clock() + delay
    end

    if show then
        local between = os.clock() - allHints[str_id].timer
        if between <= animTime then
            local s = function(f)
                return f < 0.0 and 0.0 or (f > 1.0 and 1.0 or f)
            end
            local alpha = hovered and s(between / animTime) or s(1.00 - between / animTime)
            gui.PushStyleVarFloat(gui.StyleVar.Alpha, alpha)
            gui.SetTooltip(hint)
            gui.PopStyleVar()
        elseif hovered then
            gui.SetTooltip(hint)
        end
    end
end

function ev.onShowDialog(id, style, title, left, right, content)
	if closeNextDialog then
		closeNextDialog = false
		sampSendDialogResponse(id, 0, 0, "")
		return false
	end
	if title:find("Кастомизация интерфейса") and style == 5 then
		local c = 1
		for i in string.gmatch(content, "\n") do c = c + 1 end
		content = content .. "\n{ff6666}[" .. c .. "]{ffffff} Настройки Arizona Mimgui\t{cccccc}Открыть"
		cfgOpenerDialog = {id = id, item = c-1}
		return {id, style, title, left, right, content}
	end
	--print(id, style, title, left, right, content)
end

function ev.onSendDialogResponse(id, button, list, text)
	if id == cfgOpenerDialog.id and button == 1 and list == cfgOpenerDialog.item then
		s.settings.visible[0] = true
		closeNextDialog = true
		return {id, 0, 0, ""}
	end
end
