script_name("arizona-mimgui")
script_description("An attempt to rewrite Arizona's CEF interfaces using mimgui. Because fuck CEF, that's why")
script_author("Alex Gravitos aka Безликий")

require('lib.moonloader')
local ev = require "samp.events"
--local _, nt = pcall(import, "lib/imgui_notf.lua")
local arz = require "arizona-events"
local fa = require('fAwesome6')
local mc_compat = false
local gui = require "mimgui"
local memory = require "memory"
local vk = require "vkeys"
local ffi = require "ffi"
local enc = require "encoding"
local lfs = require "lfs"
enc.default = "CP1251"
local u8 = enc.UTF8

local font
local font16
local clockfont
local datefont

function explode_argb(argb)
  local a = bit.band(bit.rshift(argb, 24), 0xFF)
  local r = bit.band(bit.rshift(argb, 16), 0xFF)
  local g = bit.band(bit.rshift(argb, 8), 0xFF)
  local b = bit.band(argb, 0xFF)
  return a, r, g, b
end

function join_argb(a, r, g, b)
    local argb = b  -- b
    argb = bit.bor(argb, bit.lshift(g, 8))  -- g
    argb = bit.bor(argb, bit.lshift(r, 16)) -- r
    argb = bit.bor(argb, bit.lshift(a, 24)) -- a
    return argb
end

function argb_abgr(argb)
	local a, r, g, b = explode_argb(argb)
	return join_argb(a, b, g, r)
end

local copas = require "copas"
local socket = require "socket"
local http = require "copas.http"
local req = require "requests"

local cachedir = getWorkingDirectory() .. "/ArizonaMimgui/icon-cache/"

local cfg = require "inicfg"

local getBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 0x5E4280)
function getBodyPartCoordinates(id, handle)
  local pedptr = getCharPointer(handle)
  local vec = ffi.new("float[3]")
  getBonePosition(ffi.cast("void*", pedptr), vec, id, true)
  return vec[0], vec[1], vec[2]
end

local cfgOpenerDialog = {
	id = 0,
	item = 0
}

inventory = {} -- inventory in particular is a weird one, it gets sent to the client passively and is stored on the client, so we need some kind of persistance to keep it loaded in between script reloads
-- mostly because we reload the script to set its DPI really
items_data = {} -- data about items. what else is there to say

function updateItemsData()
    --async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/items_data.json")
    --async_http_request:create('json', 'GET', "https://items.shinoa.tech/items.php")
    resp = req.request('GET', "https://server-api.arizona.games/client/json/table/get?project=arizona&server=0&key=inventory_items")
    if resp.status_code == 200 then
		items_data = {}
		items_arz = decodeJson(resp.text)
		for i,v in pairs(items_arz) do
			items_data[v.id] = v
		end
		--print(DeepPrint(items_data))
	else
		printStringNow("Item data update failed~n~Error: '".. resp.status_code .. "'", 5000)
		print(resp.status_code, resp.err, resp.text)
	end
end

TIMEZONE = 3

c = cfg.load({
main = {
	disableOriginalInterfaces = true,
	useCustomTimer = false,
	leftAlignedCars = false,
	centeredCarInfoPanel = true,
	replaceInventory = false,
	replaceTime = false,
	replacePopups = true,
	replaceCars = true,
	replaceNpcDialogs = true,
},
ui = {
	density = 1,
},
staminaBar = {
	enabled = true,
	showGameStamina = true,
},
legacy = {
	useLegacyDialogs = true,
	useLegacyPauseMenu = true,
	useNewNametags = false,
},
inventory = {
	usePaginatedInventory = false,
},
}, "../ArizonaMimgui/config.ini")

local MAX_COLUMNS = 6

local quesada_ntags_toggle_ntags = nil
local quesada_ntags_flag_addr    = nil 

local cc = {
	ui = {
		density = {
			v = gui.new.float(c.ui.density),
			min = 0.7,
			max = 2.0,
			type = "float"
		}
	}
}

function save()
	for i, v in pairs(cc) do
		for u, w in pairs(v) do
			c[i][u] = cc[i][u].v[0]
		end
	end
	cfg.save(c, "../ArizonaMimgui/config.ini")
end

cacher = {
	queue = {},
	working = false,
	maxqueue = 0,
}

function main()
	while not isSampAvailable() do wait(100) end
	updateItemsData()
	if c.legacy.useLegacyDialogs then lua_thread.create(quesada_dialogs) end
	if c.legacy.useLegacyPauseMenu then lua_thread.create(pauseMenuThread) end
	quesada_ntags_load()
	quesada_nametags_force_state(c.legacy.useNewNametags)

	--sampRegisterChatCommand("tinv",function() s.inventory.visible = not s.inventory.visible end)
	--sampRegisterChatCommand("amimset",function() s.settings.visible[0] = not s.settings.visible[0] end)

	while true do
		wait(0)
		if not cacher.working and #cacher.queue > 0 then
			cacher.working = true
			--wait(1)
			local image = table.remove(cacher.queue)
			local iid = string.gsub(image.url, ".*arizona%-rp", "")
			if image.url and image.cachepath then
				download_file(image.url, image.cachepath)
				--imagesthreads[iid] = lua_thread.create(download_file, image.url, image.cachepath)
			end
		end

	end
end

s = {
	settings = {
		visible = gui.new.bool(false),
	},
	stamina = {
		value = 0,
		x = 0,
		y = 0,
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
		image = nil,
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
	inventory = {
		visible = false,
	},
	time = {
		visible = false,
		components = {},
		timestamp = 0,
		playedToday = 0,
		playedHour = 0,
	},
	rightclick = {
		visible = false,
		slot = 0,
		container = 0,
		pos = gui.ImVec2(0,0)
	}

}

imagesbuffer = {}
imagesthreads = {}

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
	[19] = "Нельзя продать игроку",
	[20] = "Нельзя продать в гос",
	[21] = "Нельзя выставить на аукцион",
	[22] = "Нельзя обменять в центре обмена",
	[23] = "Нельзя перевести в семью",
	[24] = "Нельзя перевести во фракцию",
	[25] = "Нельзя перевести в бизнес",
	[26] = "Повышенная максимальная скорость",
}

itemtypes = {
	[3] = "Аксессуар",
	[21] = "Объект",
	[4] = "Деталь тюнинга",
	[7] = "Покраска",
	[8] = "Обвес для оружия",
	[23] = "Визуальный тюнинг",
	[10] = "Скин",
	[15] = "Расходник",
	[76] = "Другое",
	[57] = "Номерной знак",
	[31] = "Еда",
	[41] = "Прицел",
	[35] = "Аптечка",
	[20] = "Точильный камень",
	[24] = "Технический тюнинг",
	[51] = "Эликсир",
	[37] = "Выпивка",
	[55] = "Краситель",
	[9] = "Оружие",
	[11] = "Телефон",

}

cdn = {
	res = {
		["0"] = 'https://cdn.azresources.cloud',
		[0] = 'https://cdn.azresources.cloud',
  		["1"] = 'https://reserve-cdn.azresources.cloud',
  		[1] = 'https://reserve-cdn.azresources.cloud',
	},
	sounds = {
		["0"] = 'https://cdn.azsounds.cloud',
  		["1"] = 'https://reserve-cdn.azsounds.cloud',
  		[0] = 'https://cdn.azsounds.cloud',
  		[1] = 'https://reserve-cdn.azsounds.cloud',
	},
	serverapi = {
		["0"] = 'https://server-api.arizona.games',
		["1"] = 'https://reserve-server-api.arizona.games',
		[0] = 'https://server-api.arizona.games',
		[1] = 'https://reserve-server-api.arizona.games',
	},
}

ffi.cdef('struct CVector2D {float x, y;}')

ffi.cdef('const char* GetCommandLineA(void);')

local cmdline = ffi.string(ffi.C.GetCommandLineA())
local rescdn, soundcdn, apicdn = cmdline:match("-cdn (%d),(%d),(%d)")
if not rescdn then rescdn = 0 end
if not soundcdn then soundcdn = 0 end
if not apicdn then apicdn = 0 end
--print("CDN", rescdn, soundcdn, apicdn)

function httpRequest(request, body, handler) -- copas.http
    -- start polling task
    --[[if not copas.running then
        copas.running = true
        lua_thread.create(function()
            wait(0)
            while not copas.finished() do
                local ok, err = copas.step(0)
                if ok == nil then error(err) end
                wait(0)
            end
            copas.running = false
        end)
    end
    -- do request
    if handler then
        return copas.addthread(function(r, b, h)
            copas.setErrorHandler(function(err) h(nil, err) end)
            h(http.request(r, b))
        end, request, body, handler)
    else
        local results
        local thread = copas.addthread(function(r, b)
            copas.setErrorHandler(function(err) results = {nil, err} end)
            results = table.pack(http.request(r, b))
        end, request, body)
        while coroutine.status(thread) ~= 'dead' do wait(0) end
        return table.unpack(results)
    end
	]]
	resp = req.request("GET", request)
	return resp.text, resp.status_code, "{}", resp.err
end

function download_file(url, file_path)
    -- Make an asynchronous HTTP GET request using copas.http.request
    local iid = string.gsub(url, ".*arizona%-rp", "")

    local d = file_path:gsub("/[^/]*$", "")
    if not doesDirectoryExist(d) then
    		print(d)
    		createDirectory(d)
    end
    
    print(url, "»", file_path)
    local body, status, headers, err = httpRequest(url)
	
	print(status)
	
    if status == 200 then
        -- Open the local file in write mode
        local file, file_err = io.open(file_path, "wb")
        if file then
            -- Write the downloaded body to the file
            file:write(body)
            file:close()
            print("Successfully downloaded " .. url .. " to " .. file_path)
        else
            print("Error opening file: " .. file_err)
        end
    else
        print("Error downloading file: HTTP status " .. status .. " (" .. tostring(err) .. ")")
    end
    cacher.working = false
	imagesthreads[iid].dead = true
end

function getGameStamina()
  local float = memory.getfloat(0xB7CDB4)
  return math.floor(float/31.47000244)
end

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

--------------------- persistence -------------------------

local persistence_write, persistence_writeIndent, persistence_writers, persistence_refCount;

persistence =
{
	store = function (path, ...)
		local file, e = io.open(path, "w");
		if not file then
			return error(e);
		end
		local n = select("#", ...);
		-- Count references
		local objRefCount = {}; -- Stores reference that will be exported
		for i = 1, n do
			persistence_refCount(objRefCount, (select(i,...)));
		end;
		-- Export Objects with more than one ref and assign name
		-- First, create empty tables for each
		local objRefNames = {};
		local objRefIdx = 0;
		file:write("-- Persistent Data\n");
		file:write("local multiRefObjects = {\n");
		for obj, count in pairs(objRefCount) do
			if count > 1 then
				objRefIdx = objRefIdx + 1;
				objRefNames[obj] = objRefIdx;
				file:write("{};"); -- table objRefIdx
			end;
		end;
		file:write("\n} -- multiRefObjects\n");
		-- Then fill them (this requires all empty multiRefObjects to exist)
		for obj, idx in pairs(objRefNames) do
			for k, v in pairs(obj) do
				file:write("multiRefObjects["..idx.."][");
				persistence_write(file, k, 0, objRefNames);
				file:write("] = ");
				persistence_write(file, v, 0, objRefNames);
				file:write(";\n");
			end;
		end;
		-- Create the remaining objects
		for i = 1, n do
			file:write("local ".."obj"..i.." = ");
			persistence_write(file, (select(i,...)), 0, objRefNames);
			file:write("\n");
		end
		-- Return them
		if n > 0 then
			file:write("return obj1");
			for i = 2, n do
				file:write(" ,obj"..i);
			end;
			file:write("\n");
		else
			file:write("return\n");
		end;
		if type(path) == "string" then
			file:close();
		end;
	end;

	load = function (path)
		local f, e;
		if type(path) == "string" then
			f, e = loadfile(path);
		else
			f, e = path:read('*a')
		end
		if f then
			return f();
		else
			return nil, e;
		end;
	end;
}

-- Private methods

-- write thing (dispatcher)
persistence_write = function (file, item, level, objRefNames)
	persistence_writers[type(item)](file, item, level, objRefNames);
end;

-- write indent
persistence_writeIndent = function (file, level)
	for i = 1, level do
		file:write("\t");
	end;
end;

-- recursively count references
persistence_refCount = function (objRefCount, item)
	-- only count reference types (tables)
	if type(item) == "table" then
		-- Increase ref count
		if objRefCount[item] then
			objRefCount[item] = objRefCount[item] + 1;
		else
			objRefCount[item] = 1;
			-- If first encounter, traverse
			for k, v in pairs(item) do
				persistence_refCount(objRefCount, k);
				persistence_refCount(objRefCount, v);
			end;
		end;
	end;
end;

-- Format items for the purpose of restoring
persistence_writers = {
	["nil"] = function (file, item)
			file:write("nil");
		end;
	["number"] = function (file, item)
			file:write(tostring(item));
		end;
	["string"] = function (file, item)
			file:write(string.format("%q", item));
		end;
	["boolean"] = function (file, item)
			if item then
				file:write("true");
			else
				file:write("false");
			end
		end;
	["table"] = function (file, item, level, objRefNames)
			local refIdx = objRefNames[item];
			if refIdx then
				-- Table with multiple references
				file:write("multiRefObjects["..refIdx.."]");
			else
				-- Single use table
				file:write("{\n");
				for k, v in pairs(item) do
					persistence_writeIndent(file, level+1);
					file:write("[");
					persistence_write(file, k, level+1, objRefNames);
					file:write("] = ");
					persistence_write(file, v, level+1, objRefNames);
					file:write(";\n");
				end
				persistence_writeIndent(file, level);
				file:write("}");
			end;
		end;
	["function"] = function (file, item)
			-- Does only work for "normal" functions, not those
			-- with upvalues or c functions
			local dInfo = debug.getinfo(item, "uS");
			if dInfo.nups > 0 then
				file:write("nil --[[functions with upvalue not supported]]");
			elseif dInfo.what ~= "Lua" then
				file:write("nil --[[non-lua function not supported]]");
			else
				local r, s = pcall(string.dump,item);
				if r then
					file:write(string.format("loadstring(%q)", s));
				else
					file:write("nil --[[function could not be dumped]]");
				end
			end
		end;
	["thread"] = function (file, item)
			file:write("nil --[[thread]]\n");
		end;
	["userdata"] = function (file, item)
			file:write("nil --[[userdata]]\n");
		end;
}

--------------------------------------------------

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
    glyph_ranges = gui.GetIO().Fonts:GetGlyphRangesCyrillic() 
    font = gui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\arialbd.ttf', math.floor(12 * c.ui.density), _, glyph_ranges)
	font16 = gui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\arialbd.ttf', math.floor(16 * c.ui.density), _, glyph_ranges)
	datefont = gui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\arialbd.ttf', math.floor(20 * c.ui.density), _, glyph_ranges)
	clockfont = gui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\ariblk.ttf', math.floor(64 * c.ui.density), _, glyph_ranges)
	iconRanges = gui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    gui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), math.floor(14 * c.ui.density), config, iconRanges)
end)

function arz.onArizonaDisplay(packet)	
	if isSampfuncsGlobalVarDefined("ModernControlsInstalled") then
		mc_compat = true
	end

    if string.find(packet.text, "event.player.updateMoney") then
        print("##MONEY", packet.text)
        local money = decodeJson(string.match(packet.text, '`(.*)`'))[1]
        --printStringNow(data,1000)
        if money < 2000000000 then
            givePlayerMoney(PLAYER_HANDLE,money - getPlayerMoney(PLAYER_HANDLE))
        else
            money = -1 * (money / 1000)
            givePlayerMoney(PLAYER_HANDLE,money - getPlayerMoney(PLAYER_HANDLE))
        end
        --int money = getPlayerMoney(Player player)
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
		return not (c.main.disableOriginalInterfaces and c.main.replacePopups)
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "businessInfo") then
		local data = decodeJson(string.match(packet.text, '`(.*)`'))[2]["businessInfo"]
		local timer = string.match(packet.text, '"timer":%s*(%d+)')
		--print(buttons)
		local b = ""
		local inf = ""
		for i,v in pairs(data.info) do
			inf = inf .. v.title .. ": " .. v.value .. "\n" 
		end
		for i,v in pairs(data.buttons) do
			b = b .. "[" .. v.keyTitle .. "] " .. v.title .. "\n" 
		end
		
		if mc_compat then
			runSampfuncsConsoleCommand("moderncontrols.setkey " .. data.buttons[1].keyTitle)
		end
		--nt.addNotification("--- "..title.." ---\n" .. description .."\n\n" .. inf .. "\n" .. b, (tonumber(timer) and tonumber(timer) or 7))
		
		s.propertyInfo.visible = true
		s.propertyInfo.title = data.title
		s.propertyInfo.buttons = data.buttons
		s.propertyInfo.information = data.info
		s.propertyInfo.description = data.description
		s.propertyInfo.image = data.img
		s.propertyInfo.cd(tonumber(timer) and tonumber(timer) or 7)
		--print(DeepPrint(buttons))
		return not (c.main.disableOriginalInterfaces and c.main.replacePopups)
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "dialogTip") then
		local data = decodeJson(string.match(packet.text, '({[^}]*})'))
		s.questHint.visible = true
		s.questHint.text = data.text
		s.questHint.image = data.backgroundImage
		--nt.addNotification("[i]: " .. text, 7)
		--print(DeepPrint(buttons))
		return not (c.main.disableOriginalInterfaces and c.main.replacePopups)
	end
	
	if string.find(packet.text, "cef.modals.showModal") and string.find(packet.text, "carMenu") then
		--local text = string.match(packet.text, '"text":%s*"([^"]*)"')
		s.cars.visible = true
		s.carinfo.visible = false
		s.cars.vehicles = {}
		sendcef("vehicleMenu.loadList")
		return not (c.main.disableOriginalInterfaces and c.main.replaceCars)
	end
	
	if string.find(packet.text, "event.vehicleMenu.pushVehicleItem") then
		if not string.find(packet.text, 'null') then
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
		return not (c.main.disableOriginalInterfaces and c.main.replacePopups)
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
			return not (c.main.disableOriginalInterfaces and c.main.replaceNpcDialogs)
		end
		
		if string.find(packet.text, "'%[%s*null%s*%]'") then
			s.npc.visible = false
			s.inventory.visible = false
		end
	end

	if string.find(packet.text, "event.arizonahud.setTimeWidgetInfo") then
		local data = decodeJson(string.match(packet.text, "`(.*)`"))[1]
		s.time.visible = true
		s.time.timestamp = data.timestamp + TIMEZONE * 60 * 60
		s.time.playedToday = data.playedToday
		s.time.playedHour = data.playedHour
		s.time.components = data.components
		lua_thread.create(timeTick)
		return not (c.main.disableOriginalInterfaces and c.main.replaceTime)
	end

	if string.find(packet.text, "event.arizonahud.setTimeWidgetHide") then
		s.time.visible = false
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
	
	if string.find(packet.text, "event.arizonahud.playerPower") then
		s.stamina.value = decodeJson(string.match(packet.text, '`(.*)`'))[1]
--		printStringNow(s.stamina.value, 100)
	end
	
	if string.find(packet.text, "event.inventory.setPlayerInventoryVisible") then
		s.inventory.visible = decodeJson(string.match(packet.text, '`(.*)`'))[1]
		return not c.main.disableOriginalInterfaces or not c.main.replaceInventory
	end
	
	if string.find(packet.text, "event.inventory.playerInventory") then
		local data = decodeJson(string.match(packet.text, '`(.*)`'))[1]
		handleInventoryEvent(data.action, data.data)
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
	function() return s.keyboardHint.visible and c.main.replacePopups and not sampIsChatInputActive() and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
--		if s.keyboardHint.visible and not sampIsChatInputActive() then
		local cpos = getChatPos()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(cpos.x, cpos.y), 0, gui.ImVec2(0, 0))		
		gui.Begin("keyboardHint", gui.new.bool(s.keyboardHint.visible and not sampIsChatInputActive()), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		if s.keyboardHint.title ~= "" then gui.Text(u8(s.keyboardHint.title)) end
		for i,v in pairs(s.keyboardHint.buttons) do
			gui.HintButton(u8(v.keyTitle), u8(v.title))
		end
		gui.End()
		gui.PopFont()
--		end
	end
)

-- Download progress - if only i knew how to properly display it huh
local downloadFrame = gui.OnFrame(
	function() return cacher.working and #cacher.queue > 0 end,
	function(player)
		player.HideCursor = true
		gui.PushFont(font)
		sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		gui.Begin("download", gui.new.bool(cacher.working and #cacher.queue > 0), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.Text(u8"Загрузка ресурсов...")
		if #cacher.queue > 1 then
			gui.Text(cacher.queue[#cacher.queue].iid)
		end
		gui.ProgressBar((cacher.maxqueue - #cacher.queue) / cacher.maxqueue)
		gui.End()
		gui.PopFont()
	end
)


-- Property info, shown when standing on a house/trailer/business entry pickup
local propertyHintFrame = gui.OnFrame(
	function() return s.propertyInfo.visible and c.main.replacePopups and not sampIsChatInputActive() and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local cpos = getChatPos()
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(cpos.x, cpos.y), 0, gui.ImVec2(0, 0))	
		--gui.SetNextWindowSizeConstraints(gui.ImVec2(300, 0), gui.ImVec2(300, sy))
		gui.Begin("propertyInfo", gui.new.bool(s.keyboardHint.visible and c.main.replacePopups and not sampIsChatInputActive()), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.Text(u8(s.propertyInfo.title))
		--[[
		if s.propertyInfo.image and s.propertyInfo.image ~= "" then
			gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/systems/image_business_temp/" .. s.propertyInfo.image .. ".png", gui.ImVec2(280, 140))
		end]] -- apparently arizona backend does not provide pngs for businesses, and mimgui cant load webps because webp is a bad file format
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
		gui.PopFont()
	end
)

-- Toasts. They show up at random in the bottom middle of the screen, say, when you lock your car.
local toastFrame = gui.OnFrame(
	function() return s.toast.visible and c.main.replacePopups and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy - 10 * c.ui.density), 0, gui.ImVec2(0.5, 1))
		gui.Begin("toast", gui.new.bool(s.toast.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		if s.toast.icon == "success" then gui.TextInColor(fa("CHECK"), gui.ImVec4(0, 1, 0, 1))
		elseif s.toast.icon == "error" then gui.TextInColor(fa("EXCLAMATION"), gui.ImVec4(1, 0, 0, 1))
		elseif s.toast.icon == "info" then gui.Text(fa("INFO"))
		elseif s.toast.icon == "halloween" then gui.Text(fa("GHOST")) end
		gui.SameLine()
		if s.toast.text == nil then s.toast.text = "Уведомление" end
		if s.toast.description == nil then s.toast.description = "" end
		gui.Text(u8(s.toast.text))
		gui.Text(u8(s.toast.description))
		gui.End()
		gui.PopFont()
	end
)

-- Quest hints. These show up in the bottom right of the screen with an ugly ass picture.
local questHintFrame = gui.OnFrame(
	function() return s.questHint.visible and c.main.replacePopups and sampIsChatVisible() end,
	function(player)
		player.HideCursor = true
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(sx - 10, sy - 10), 0, gui.ImVec2(1, 1))
		gui.PushStyleColor(gui.Col.WindowBg, gui.ImVec4(0, 0, 0, 0))
		gui.Begin("questHintBG", gui.new.bool(s.questHint.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/systems/quest_notify/" .. s.questHint.image:gsub("webp", "png"), gui.ImVec2(200, 200))
		gui.End()
		gui.PopStyleColor()
		gui.SetNextWindowPos(gui.ImVec2(sx - 10, sy - 10), 0, gui.ImVec2(1, 1))
		gui.Begin("questHint", gui.new.bool(s.questHint.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.Text(u8(s.questHint.text))
		gui.End()
		gui.PopFont()
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
	function() return s.npc.visible and c.main.replaceNpcDialogs end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.SetNextWindowPos(gui.ImVec2(sx - 10, sy - 10), 0, gui.ImVec2(1, 1))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300 * c.ui.density, 0), gui.ImVec2(sx, sy))
		gui.PushFont(font)
		gui.Begin("npc", gui.new.bool(s.npc.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
		if not s.npc.title == "" then gui.Text(u8(s.npc.title)) end
		local t = s.npc.text:gsub("<br>", "\n")
		gui.TextWrapped(u8(t))
		for i,v in pairs(s.npc.buttons) do
			if gui.Button(u8(v.text)) then
				sendcef("answer.npcDialog|" .. v.id)
			end
			gui.SameLine()
		end
		gui.End()
		gui.PopFont()
	end
)

-- settings for the mod

local settingsFrame = gui.OnFrame(
	function() return s.settings.visible[0] end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300 * c.ui.density, 0), gui.ImVec2((sx < 300 * c.ui.density and 300 * c.ui.density or sx), sy))
		gui.Begin("settings", s.settings.visible, gui.WindowFlags.AlwaysAutoResize)
		
		for u,m in pairs(c) do
			if gui.CollapsingHeader(u8(u)) then
				for i,v in pairs(m) do
					local readableName = i:gsub("([A-Z])", " %1")
					if type(v) == "boolean" then
						gui.Checkbox(u8(readableName), gui.new.bool(v))
						if gui.IsItemClicked() then
							c[u][i] = not c[u][i]
							save()
						end
					elseif type(v) == "number" then
						if cc[u][i].type == "float" then
							gui.SliderFloat(u8(readableName), cc[u][i].v, cc[u][i].min, cc[u][i].max)
						end
					end
				end
			end
		end
		
		--gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/assets/images/inventory/vehicles/512/1272.png", gui.ImVec2(200, 200))
		
		if gui.Button(u8"Перезагрузить кэш") then
			imagesbuffer = {}
		end
		gui.SameLine()
		if gui.Button(u8"Сохранить") then
			save()
			thisScript():reload()
		end
		
		gui.End()
		gui.PopFont()
	end
)

-- fUCKING CARS MENU
local carsFrame = gui.OnFrame(
	function() return s.cars.visible and c.main.replaceCars and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function(player)
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2((c.main.leftAlignedCars and 0 or sx), sy/2), 0, gui.ImVec2((c.main.leftAlignedCars and 0 or 1), 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(300 * c.ui.density, 0), gui.ImVec2(300 * c.ui.density, sy))
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
		gui.End()
		gui.PopFont()
	end
)

function gui.CarInfoCard(i, v)
	gui.BeginChild("car"..i, gui.ImVec2(280 * c.ui.density, 120 * c.ui.density), true)
	if v.sysName then
		gui.SetCursorPos(gui.ImVec2(100 * c.ui.density, 0))
		--print(rescdn, cdn.res[rescdn], "/projects/arizona-rp/assets/images/inventory/vehicles/512/", v.sysName)
		gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/assets/images/inventory/vehicles/512/" .. v.sysName:gsub("webp", "png"), gui.ImVec2(180 * c.ui.density, 110 * c.ui.density))
		if gui.IsItemClicked() then
			sendcef("vehicleMenu.loadVehicleInfo|" .. v.id)
		end
	end
	gui.SetCursorPos(gui.GetStyle().FramePadding)
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
		gui.PushFont(font)
		if c.main.centeredCarInfoPanel then
			gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		else
			gui.SetNextWindowPos(gui.ImVec2((c.main.leftAlignedCars and 0 or sx), sy/2), 0, gui.ImVec2((c.main.leftAlignedCars and 0 or 1), 0.5))
		end
		gui.SetNextWindowSizeConstraints(gui.ImVec2(400 * c.ui.density, 0), gui.ImVec2(400 * c.ui.density, sy))
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
		gui.PopFont()
	end
)

-- stamina bar, for things like skateboards and jet packs
local staminaFrame = gui.OnFrame(
	function()
		if (s.stamina.value > 0 and c.staminaBar.enabled) or (c.staminaBar.showGameStamina and s.stamina.value == 0 and getGameStamina() < 100) then
			local x, y, z = getBodyPartCoordinates(2, PLAYER_PED)
			s.stamina.x, s.stamina.y = convert3DCoordsToScreen(x, y, z)
			s.stamina.x = s.stamina.x + 50
		end
		return (s.stamina.value > 0 and c.staminaBar.enabled) or (c.staminaBar.showGameStamina and s.stamina.value == 0 and getGameStamina() < 100)
	end,
	function(player)
		player.HideCursor = true
		gui.SetNextWindowPos(gui.ImVec2(s.stamina.x, s.stamina.y), 0, gui.ImVec2(0.5, 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(50 * c.ui.density, 50 * c.ui.density), gui.ImVec2(50 * c.ui.density, 50 * c.ui.density))
		gui.PushStyleColor(gui.Col.WindowBg, gui.ImVec4(0,0,0,0))
		gui.Begin("stamina", gui.new.bool((s.stamina.value > 0 and c.staminaBar.enabled) or (c.staminaBar.showGameStamina and s.stamina.value == 0 and getGameStamina() < 100)), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		draw_list = gui.GetWindowDrawList()
		draw_list:PathArcTo(gui.ImVec2(s.stamina.x, s.stamina.y), 20 * c.ui.density, math.pi * -1/4, math.pi * 1/4, 64)
		draw_list:PathStroke(gui.ColorConvertFloat4ToU32(gui.ImVec4(0, 0, 0, 0.4)), false, 4 * c.ui.density)
		if s.stamina.value > 0 then
			draw_list:PathArcTo(gui.ImVec2(s.stamina.x, s.stamina.y), 20 * c.ui.density, math.pi * (1/4 - 0.5 * (s.stamina.value / 100)), math.pi * 1/4, 64)
		else
			draw_list:PathArcTo(gui.ImVec2(s.stamina.x, s.stamina.y), 20 * c.ui.density, math.pi * (1/4 - 0.5 * (getGameStamina() / 100)), math.pi * 1/4, 64)
		end
		draw_list:PathStroke(gui.ColorConvertFloat4ToU32(gui.ImVec4(1, 1, 0, 1)), false, 2 * c.ui.density)
		gui.End()
		gui.PopStyleColor()
	end
)

-- cef /time replacement
function timeTick()
	while s.time.visible do
		wait(1000)
		s.time.timestamp = s.time.timestamp + 1
		s.time.playedHour = s.time.playedHour + 1
	end
end

local timeMonths = {
	"ЯНВАРЯ", "ФЕВРАЛЯ", "МАРТА", "АПРЕЛЯ", "МАЯ", "ИЮНЯ",
	"ИЮЛЯ", "АВГУСТА", "СЕНТЯБРЯ", "ОКТЯБРЯ", "НОЯБРЯ", "ДЕКАБРЯ"
}

function stamptostring(timestamp)
	if timestamp > 3600 then
		return os.date("!%H:%M:%S", timestamp)
	else
		return os.date("!%M:%S", timestamp)
	end
end

local timeFrame = gui.OnFrame(
	function() return c.main.replaceTime and s.time.visible end,
	function(player)
		player.HideCursor = true
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(sx, sy - 50 * c.ui.density), 0, gui.ImVec2(1, 1))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(230 * c.ui.density, 0), gui.ImVec2(230 * c.ui.density, sy))
		gui.PushStyleColor(gui.Col.WindowBg, gui.ImVec4(0,0,0,0))
		gui.Begin("timewindow", gui.new.bool(s.time.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoInputs)
		gui.PushFont(datefont)
		local m = timeMonths[tonumber(os.date("!%m", s.time.timestamp))]
		gui.RightTextColored(gui.ImVec4(0.7, 0.7, 0.7, 1), os.date("!%d " .. u8(m) .. " %Y", s.time.timestamp))
		gui.PopFont()
		gui.SetCursorPos(gui.GetCursorPos() + gui.ImVec2(0, -10))
		gui.PushFont(clockfont)
		gui.Text(os.date("!%H:%M:%S", s.time.timestamp))
		gui.PopFont()

		gui.PushStyleColor(gui.Col.ChildBg, gui.ImVec4(0.2, 0.2, 0.2, 0.7))
		gui.BeginChild("#online", gui.ImVec2(220 * c.ui.density, 22 * c.ui.density), true)
		--gui.TextColored(gui.ImVec4(0.9, 0.9, 0.9, 1), u8"ВАШ ОНЛАЙН")
		--gui.SameLine()
		gui.TextColored(gui.ImVec4(0.7, 0.7, 0.7, 1),u8"Сегодня")
		gui.SameLine()
		gui.Text(stamptostring(s.time.playedToday))
		gui.SameLine()
		gui.TextColored(gui.ImVec4(0.7, 0.7, 0.7, 1), u8"За час")
		gui.SameLine()
		gui.Text(stamptostring(s.time.playedHour))
		gui.EndChild()
		gui.PopStyleColor()
		gui.Columns(2)
		local DL = gui.GetWindowDrawList()
		local wPos = gui.GetWindowPos()
		for i,component in pairs(s.time.components) do
			local cPos = gui.GetCursorPos()
			local leftcolor = argb_abgr(tonumber(component.gradientColors[1]:gsub("#", "FF"), 16))
			local rightcolor = argb_abgr(tonumber(component.gradientColors[2]:gsub("#", "FF"), 16))
			DrawRoundedGradientRect(
				DL,
				wPos + cPos,
				gui.ImVec2(100 * c.ui.density, 40 * c.ui.density),
				leftcolor, rightcolor, leftcolor, rightcolor,
				5, 12
			)
			cpos = gui.GetCursorPos()
			gui.SetCursorPos(cpos + gui.ImVec2(40 * c.ui.density, 0))
			gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/systems/time/icons/" .. component.image:gsub("webp", "png"), gui.ImVec2(60 * c.ui.density, 40 * c.ui.density))
			gui.SetCursorPos(cpos)
			gui.BeginChild("#" .. u8(component.title), gui.ImVec2(100 * c.ui.density, 40 * c.ui.density), true)
			gui.Text(u8(component.title))
			gui.Text(u8(component.description and component.description or stamptostring(component.timer)))
			gui.EndChild()
			gui.NextColumn()
		end
		gui.Columns(1)
		gui.SetCursorPos(gui.GetCursorPos() + gui.ImVec2(100 * c.ui.density, 5 * c.ui.density))

		gui.PushFont(font16)
		gui.Text(u8"ЗАКРЫТЬ")
		gui.PopFont()
		gui.SameLine()
		gui.SetCursorPos(gui.GetCursorPos() - gui.ImVec2(0, 5 * c.ui.density))
		gui.HintButton(u8("Esc"), "")
		gui.End()
		gui.PopStyleColor()
		gui.PopFont()
	end
)

-- inventory

INVENTORY_CONTAINERS = {
	player = 1, -- игрок
	accs = 2, -- аксы из 1 сета
	trade = 3, -- продать в трейде
	fortrade = 4, -- купить в трейде
	house = 5, -- шкаф
	trailer = 6, -- трейлер
	trash = 7, -- мусорка
	trunk = 8, -- багажник
	chest = 9, -- дефолтное улучшение
	enhs = 10, -- улучшения 
	craft = 11, -- верстак? возможно, мастерская одежды
	car_visual = 12, -- виз. модификации на машине
	shop_buy = 13, -- /ashop? какие-то магазины
	select_shop = 14, -- ну тут даже я хз
	tuning = 15, -- половина этих значений вряд ли даже где-то используется
	store = 16, -- ещё один магазин?
	utils = 17, -- инструменты (бронежилет, чемодан)
	car_paintjob = 18, -- аэрография на машине
	car_tt = 19, -- тт на машине
	mod_skin = 20, -- ааааа, это модификация скина!
	workshop = 21, -- вот это - мастерская, а 11 тогда кто
	skin = 22, -- скины но в инвентаре
	car_tech = 23, -- тех. модификации на машине
	cardholder = 24, -- бумажник
	storehouse = 25, -- склад
	hotel_backup_room = 26,
	pawnshop = 27, -- ломбард
	shop_sell = 28,
	fam_flat = 29, -- шкаф в фам кв
	security_acs = 30, -- аксы охранников
	painting_acs = 31, -- покраска аксов?
	security_guns = 32, -- оружие охры
	security = 33, -- инвентарь охранника
	hotel = 34, -- шкаф отеля
	fishbag = 35, -- рыбацкая сумка
	car_plate = 36, -- номер машины
	view_attach = 37, -- /viewplayer?
	view_gun_improv = 38,
	view_improv = 39,
	view_skin = 40,
	view_mod_skin = 41,
	trash_bag = 43,
	admin_fund = 46,
	fam_house = 47,
	social_house = 48,
	warehouse_matter = 49,
}

VIEW_IDs = {
	Menu= 0,
	Trade= 32,
	Warehouse= 35,
	Vehicle= 30,
	Shop= 4,
	Workshop= 31,
	Character= 27,
	Security= 28,
	Repair= 7,
	ArmourSsharpening= 8,
	ACSColor= 9,
	Enchant= 10,
	ACSDisassembly= 11,
	SetCharacteristics= 12,
	HouseFreeze= 13,
	Wallet= 29,
	Fishbag= 15,
	View= 36
}

ACTIONS_BITS = {
  Use= 1,
  Put= 32768,
  Put_on= 2,
  Take= 65536,
  Take_on= 256,
  Item_open= 64,
  Item_close= 128,
  Drop= 4,
  Split= 8,
  Clear= 512,
  Install= 1024,
  Edit= 2048,
  Open= 4096,
  Rent= 8192,
  Color= 16384,
  Info= 16,
  ItemLink= 1048576,
  Sell= 131072,
  PutInGift= 262144,
  Send= 524288,
  CancelRent= 2097152,
  Rating= 4194304,
  Close= 32
}
ACTIONS_NAMES = {
  Use= "Использовать",
  Put= "Положить",
  Put_on= "Надеть",
  Take= "Забрать",
  Take_on= "Снять",
  Item_open= "Открыть",
  Item_close= "Закрыть",
  Drop= "Выбросить",
  Split= "Разделить",
  Clear= "Очистить",
  Install= "Установить",
  Edit= "Изменить",
  Open= "Открыть",
  Rent= "Сдать в аренду",
  Color= "Покрасить",
  Info= "Свойства",
  ItemLink= "Упомянуть",
  Sell= "Продать",
  PutInGift= "Подарить",
  Send= "Отправить",
  CancelRent= "Отменить аренду",
  Rating= "Рейтинг",
  Close= "Закрыть"
}
BUTTONS_BITS = {
  Inventory= 1,
  Security= 4,
  CarInventory= 2,
  Chest= 2048,
  HotelRoom= 8,
  Trunk= 16,
  FamFlat= 32,
  House= 64,
  Trailer= 128,
  Storehouse= 256,
  Pawnshop= 512,
  Trash= 1024,
  TrashBag= 32768,
  SocialHouse= 65536
}

SECURITY_STUFF = {
	[INVENTORY_CONTAINERS.security] = true,
	[INVENTORY_CONTAINERS.security_acs] = true,
	[INVENTORY_CONTAINERS.security_guns] = true
}
WAREHOUSES = {
	[INVENTORY_CONTAINERS.chest] = true,
	[INVENTORY_CONTAINERS.house] = true,
	[INVENTORY_CONTAINERS.storehouse] = true,
	[INVENTORY_CONTAINERS.pawnshop] = true,
	[INVENTORY_CONTAINERS.trailer] = true,
	[INVENTORY_CONTAINERS.trash] = true,
	[INVENTORY_CONTAINERS.trunk] = true,
	[INVENTORY_CONTAINERS.hotel] = true,
	[INVENTORY_CONTAINERS.fam_flat] = true,
	[INVENTORY_CONTAINERS.trash_bag] = true,
	[INVENTORY_CONTAINERS.admin_fund] = true,
	[INVENTORY_CONTAINERS.fam_house] = true,
	[INVENTORY_CONTAINERS.social_house] = true,
	[INVENTORY_CONTAINERS.warehouse_matter] = true,
}

local inventoriesHandledElsewhere = {
	[INVENTORY_CONTAINERS.player] = true,
	[INVENTORY_CONTAINERS.accs] = true,
	[INVENTORY_CONTAINERS.enhs] = true,
	[INVENTORY_CONTAINERS.skin] = true,
	[INVENTORY_CONTAINERS.utils] = true,
}



local invFrame = gui.OnFrame(
	function() return false and s.inventory.visible and c.main.replaceInventory and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function(player)
		local sx, sy = getScreenResolution()
		for i,container in pairs(inventory) do
			local col = #container < MAX_COLUMNS and (#container > 0 and #container or 1) or MAX_COLUMNS
			gui.SetNextWindowSizeConstraints(gui.ImVec2(50 * col * c.ui.density, 50 * c.ui.density), gui.ImVec2(sx * 0.75, sy * 0.75))
			gui.PushFont(font)
			gui.Begin("container" .. i, gui.new.bool(s.inventory.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize)
			gui.Text(u8(getContainerTextId(i)))
			gui.Columns(col)
			local max_id = 0
			for u,item in pairs(container) do
				max_id = (tonumber(u) > max_id and tonumber(u) or max_id)
			end
			for u=0,max_id do
				if container[u] then
					gui.InventoryItem(container[u], gui.ImVec2(48 * c.ui.density, 48 * c.ui.density), i)
					gui.NextColumn()
				end
			end
			gui.Columns(1)
			gui.End()
			gui.PopFont()
		end
	end
)

local inventoryPagination = {
	min = 0,
	max = 35,
	page = 1
}

local InventoryTabs = {
	player = 0,
}

local InventoryTab = 0
local PlayerSet = 1

local EnhancementsShown = gui.new.bool(false)

local move = {}

local playerInventory = gui.OnFrame(
	function() return s.inventory.visible and c.main.replaceInventory and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function(player)
		local iw, ih = 600, 440
		local sx, sy = getScreenResolution()
		gui.PushFont(font)
		gui.SetNextWindowPos(gui.ImVec2(sx/2, sy/2), 0, gui.ImVec2(0.5, 0.5))
		gui.SetNextWindowSizeConstraints(gui.ImVec2(iw * c.ui.density, ih * c.ui.density), gui.ImVec2(iw * c.ui.density, ih * c.ui.density))
		gui.Begin("playerinventory", gui.new.bool(s.inventory.visible), gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoScrollbar + gui.WindowFlags.NoScrollWithMouse)
		local wpos = gui.GetWindowPos()
		gui.SetCursorPos(gui.ImVec2(0,0))
		gui.BeginChild("playerinventoryleft", gui.ImVec2(250 * c.ui.density, ih * c.ui.density), true)
			if InventoryTab == InventoryTabs.player then
				
				if gui.Button(u8"Помощь", gui.ImVec2(75 * c.ui.density, 30 * c.ui.density)) then sampSendChat("/help") end
				gui.SameLine()
				if gui.Button(u8"Репорт", gui.ImVec2(75 * c.ui.density, 30 * c.ui.density)) then sampSendChat("/report") end
				gui.SameLine()
				if gui.Button(u8"GPS", gui.ImVec2(75 * c.ui.density, 30 * c.ui.density)) then sampSendChat("/gps") end

				wpos = wpos + gui.GetCursorPos()
				gui.Checkbox("##Enhancements", EnhancementsShown)
				gui.Hint("##EnhancementsHint", u8"Улучшения, обувь и ножи")
				gui.SameLine(70 * c.ui.density)

				--gui.SetCursorPosX(70 * c.ui.density)
				gui.InventoryContainer(inventory[INVENTORY_CONTAINERS.accs], INVENTORY_CONTAINERS.accs, 3, gui.ImVec2(170 * c.ui.density, 110 * c.ui.density), (PlayerSet - 1) * 6, (PlayerSet * 6) - 1)
				--gui.SetCursorPos(gui.GetCursorPos() + gui.ImVec2(0, -80 * c.ui.density))
				
				gui.InventoryItem(inventory[INVENTORY_CONTAINERS.skin][PlayerSet - 1], gui.ImVec2(48 * c.ui.density, 48*c.ui.density), 22)
				gui.SameLine(100 * c.ui.density)
				gui.InventoryContainer(inventory[INVENTORY_CONTAINERS.utils], INVENTORY_CONTAINERS.utils, 2, gui.ImVec2(115 * c.ui.density, 58 * c.ui.density), (PlayerSet - 1) * 2, (PlayerSet * 2) - 1)
				
				gui.SetCursorPosX(90 * c.ui.density)

				if gui.Button("1##Setset1") then
					sendcef("inventory.setAccessoryPage|1")
					PlayerSet = 1
				end
				gui.SameLine()
				if gui.Button("2##Setset2") then
					sendcef("inventory.setAccessoryPage|2")
					PlayerSet = 2
				end
				gui.SameLine()
				if gui.Button("3##Setset3") then
					sendcef("inventory.setAccessoryPage|3")
					PlayerSet = 3
				end

				local buts = gui.ImVec2(115  * c.ui.density, 43 * c.ui.density)

				if gui.Button(u8"Меню", buts) then sampSendChat("/mn") end
				gui.SameLine()
				if gui.Button(u8"Настройки", buts) then sampSendChat("/settings") end
				if gui.Button(u8"Транспорт", buts) then sampSendChat("/cars") end
				gui.SameLine()
				if gui.Button(u8"Бизнес", buts) then sampSendChat("/biz") end
				if gui.Button(u8"Донат", buts) then sampSendChat("/donate") end
				gui.SameLine()
				if gui.Button(u8"Семья", buts) then sampSendChat("/fammenu") end
				if gui.Button(u8"Квесты", buts) then sampSendChat("/quest") end
				gui.SameLine()
				if gui.Button(u8"Достижения", buts) then sampSendChat("/rewards") end

				gui.SetCursorPos(wpos - gui.GetWindowPos() + gui.ImVec2(10, 60))
				gui.TextColored(gui.ImVec4(0.5,0.5,0.5,0.5), u8"ARIZONA\n MIMGUI")

			else
				gui.Text("PLAYER INFO/TAB STUFF")
			end
		gui.EndChild()
		gui.SetCursorPos(gui.ImVec2(250 * c.ui.density, 0 * c.ui.density))
		gui.BeginChild("playerinventoryright", gui.ImVec2(350 * c.ui.density, ih * c.ui.density), true)
			gui.PushFont(font16)
			gui.Text(u8"Инвентарь")
			gui.PopFont()
			gui.SetCursorPosX(0)
			if c.inventory.usePaginatedInventory then
				gui.InventoryContainer(inventory[INVENTORY_CONTAINERS.player], INVENTORY_CONTAINERS.player, MAX_COLUMNS, gui.ImVec2(350 * c.ui.density, 360 * c.ui.density), inventoryPagination.min, inventoryPagination.max)
				if gui.Button("<##PaginatedInventoryLeft") then
					inventoryPagination.page = math.max(1, inventoryPagination.page - 1)
				end
				gui.SameLine()
				gui.Text(tostring(inventoryPagination.page))
				gui.SameLine()
				if gui.Button(">##PaginatedInventoryRight") then
					inventoryPagination.page = math.min(5, inventoryPagination.page + 1)
				end

				inventoryPagination.min = (inventoryPagination.page - 1) * 36
				inventoryPagination.max = (inventoryPagination.page * 36) - 1
			else
				gui.InventoryContainer(inventory[INVENTORY_CONTAINERS.player], INVENTORY_CONTAINERS.player, MAX_COLUMNS, gui.ImVec2(350 * c.ui.density, 360 * c.ui.density))
			end
			gui.SetCursorPos(gui.ImVec2((350 - 100) * c.ui.density, (ih - 30) * c.ui.density))
			if gui.Button(u8"Закрыть", gui.ImVec2(95 * c.ui.density, 25 * c.ui.density)) then
				sendcef("inventoryClose")
			end
		gui.EndChild()
		gui.End()
		
		if EnhancementsShown[0] then
			gui.SetNextWindowPos(wpos, 0, gui.ImVec2(1, 0))
			gui.SetNextWindowSizeConstraints(gui.ImVec2(120, 160), gui.ImVec2(120, 160))
			gui.Begin("EnhancementsWindow", EnhancementsShown, gui.WindowFlags.NoTitleBar + gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoScrollbar + gui.WindowFlags.NoScrollWithMouse)
				gui.SetCursorPos(gui.ImVec2(0, 0))
				gui.InventoryContainer(inventory[INVENTORY_CONTAINERS.enhs], INVENTORY_CONTAINERS.enhs, 2, gui.ImVec2(120, 160))
			gui.End()
		end

		gui.PopFont()
	end
)

gui.InventoryContainer = function(data, container_id, max_columns, size, min_slot, max_slot)
	if not min_slot then min_slot = 0 end
	if not size then size = gui.ImVec2(50 * col * c.ui.density, 50 * c.ui.density) end
	if not data then 
		local c = gui.GetCursorPos()
		gui.Text(u8"Данные контейнера не загружены.\nВы загрузили скрипт впервые без перезахода в игру?\n\nПереподключитесь к серверу (/rec), чтобы загрузить данные.")
		gui.SetCursorPos(c)
		gui.Dummy(size)
	return end
	local columns = math.max(#data < max_columns and (#data > 0 and #data or 1) or max_columns)
	gui.BeginChild("#container"..container_id, size, true)
	if data ~= nil then
		gui.Columns(math.max(#data < max_columns and (#data > 0 and #data or 1) or max_columns))
		local max_id = 0
		for u,item in pairs(data) do
			max_id = (tonumber(u) > max_id and tonumber(u) or max_id)
		end
		if not max_slot then max_slot = max_id
		else max_slot = math.min(max_slot, max_id)
		end
		for u=min_slot, max_slot do
			gui.SetColumnWidth(-1, 56 * c.ui.density)
			if data[u] then
				gui.InventoryItem(data[u], gui.ImVec2(48 * c.ui.density, 48 * c.ui.density), container_id)
			else
				gui.Dummy(gui.ImVec2(48 * c.ui.density, 48 * c.ui.density))
			end
			gui.NextColumn()
		end
		gui.Columns(1)
	end
	gui.EndChild()
end

gui.InventoryItem = function(item, size, container)
	if not item then 
		local c = gui.GetCursorPos()
		gui.Text(u8"Данные контейнера не загружены.\nВы загрузили скрипт впервые без перезахода в игру?\n\nПереподключитесь к серверу (/rec), чтобы загрузить данные.")
		gui.SetCursorPos(c)
		gui.Dummy(size)
	return end
	gui.PushStyleVarVec2(gui.StyleVar.WindowPadding, gui.ImVec2(0, 0))
	gui.PushStyleVarVec2(gui.StyleVar.FramePadding, gui.ImVec2(0, 0))
	gui.PushStyleVarVec2(gui.StyleVar.ItemSpacing, gui.ImVec2(0, 0))
	if item.background then
		local a,r,g,b = explode_argb(item.background)
		gui.PushStyleColor(gui.Col.ChildBg, gui.ImVec4(a / 255, r / 255, g / 255, b / 255))
	end
	gui.BeginChild("item" .. item.slot, size, true, gui.WindowFlags.NoScrollbar + gui.WindowFlags.NoScrollWithMouse)
	gui.SetCursorPos(gui.ImVec2(0,0))
	if item.item then
		gui.WebImage(cdn.res[rescdn] .. "/projects/arizona-rp/assets/images/donate/" .. item.item .. ".png", size)
	else
		gui.Dummy(size)
	end
	if gui.IsItemClicked(0) then
		--sampAddChatMessage("click",-1)
		if not move.active then move = {
			active = true,
			from = {
				slot = item.slot,
				type = container
			}
		}
		else
			if move.active and not (
				move.from.slot == item.slot and
				move.from.container == container
			) then
				move.to = {
					slot = item.slot,
					type = container
				}
				move.active = nil
				local send = "ЬНinventory.moveItem|" .. encodeJson(move)
				--print(send)
				sendcef(send)
				move = {}
			end
		end
	end
	if gui.IsItemClicked(1) then
		sendcef('rightClickOnBlock|' .. encodeJson({slot = item.slot, type = container}))
		s.rightclick.container = container
		s.rightclick.slot = item.slot
		s.rightclick.pos = gui.ImVec2(getCursorPos())
		s.rightclick.visible = true
	end
	gui.SetCursorPos(gui.ImVec2(0,0))
	if item.text then gui.Text(u8(item.text)) end
	gui.EndChild()
	if item.background then
		gui.PopStyleColor()
	end
	gui.PopStyleVar()
	gui.PopStyleVar()
	gui.PopStyleVar()
	if items_data[tonumber(item.item)] then
		gui.Hint("itemHint" .. item.item .. "#" .. item.slot, getItemHint(item))
	end
end

function checkkey(value, id)
	return ((bit.band(value, id) == id) or nil)
end

local rightclickmenu = gui.OnFrame(
	function() return s.rightclick.visible and not sampIsDialogActive() and not sampIsChatInputActive() end,
	function() 
		gui.PushFont(font)
		gui.SetNextWindowPos(s.rightclick.pos, _, gui.ImVec2(0, 0))
		gui.Begin("Rightclick", gui.new.bool(s.rightclick.visible and not sampIsDialogActive() and not sampIsChatInputActive()), gui.WindowFlags.AlwaysAutoResize + gui.WindowFlags.NoTitleBar)
		if inventory[s.rightclick.container] and inventory[s.rightclick.container][s.rightclick.slot] and inventory[s.rightclick.container][s.rightclick.slot].bits then
			for i,v in pairs(ACTIONS_BITS) do
				if checkkey(inventory[s.rightclick.container][s.rightclick.slot].bits, v) then
					if gui.Button(u8(ACTIONS_NAMES[i]), gui.ImVec2(100 * c.ui.density, 25 * c.ui.density)) then
						if v == ACTIONS_BITS.ItemLink then 
							sampSetChatInputEnabled(true)
							local str = sampGetChatInputText()
							sampSetChatInputText(str .. " :slot" .. s.rightclick.slot .. "_" .. s.rightclick.container .. ": ")
						else
							sendcef('clickOnButton|' .. encodeJson({type = s.rightclick.container, slot = s.rightclick.slot, action = v}))
						end
						s.rightclick.visible = false
					end
				end
			end
		end
		gui.End()
		gui.PopFont()
		if not s.inventory.visible then s.rightclick.visible = false end
	end
)

function getItemHint(item)
	local s = items_data[tonumber(item.item)].name
	s = s .. ((items_data[tonumber(item.item)].type and itemtypes[items_data[tonumber(item.item)].type]) and "\n" .. u8(itemtypes[items_data[tonumber(item.item)].type]) or "")
	s = s .. ((item.text and item.text ~= "") and "\n" .. u8(item.text) or "") .. "\n"
	s = s .. ((items_data[tonumber(item.item)].type) and u8("\nТип предмета: ") .. items_data[tonumber(item.item)].type or "")
	s = s .. ((items_data[tonumber(item.item)].active and items_data[tonumber(item.item)].active > 0) and u8("\nМожно использовать") or "")
	s = s .. ((items_data[tonumber(item.item)].acs_slot and items_data[tonumber(item.item)].acs_slot ~= -1) and u8("\nАксессуар для слота: ") .. items_data[tonumber(item.item)].acs_slot or "")
	s = s .. u8("\nСлот: ") .. item.slot
	return s
end

function getContainerTextId(id)
	for i,v in pairs(INVENTORY_CONTAINERS) do
		if v == id then return i end
	end
	return "Unknown container " .. id
end

INVENTORY_ACTIONS = {
	init = 0,
	updateButtons = 1,
	change = 2,
	infoData = 3,
	tradeConfirmation = 4,
	tradeMoney = 6,
}

function handleInventoryEvent(action, data)
	print(DeepPrint(data))
	if action == INVENTORY_ACTIONS.init and data then
		if not data or not data.type then return end
		if not inventory[data.type] then inventory[data.type] = {} end
		for i,item in pairs(data.items) do
			local slot = item.slot
			if item.id then slot = (item.slot + 100 * item.id) end
			inventory[data.type][slot] = item
		end
	end
	if action == INVENTORY_ACTIONS.change and data then
		if not data or not data.type then return end
		if not inventory[data.type] then inventory[data.type] = {} end
		for i, item in pairs(data.items) do
			local slot = item.slot
			if item.id then slot = (item.slot + 100 * item.id) end
			inventory[data.type][slot] = item
		end
	end
	if action == INVENTORY_ACTIONS.infoData then
		if not data or not data.type or not data.slot then return end
		if not inventory[data.type] then inventory[data.type] = {} end
		if not inventory[data.type][data.slot] then inventory[data.type][data.slot] = {
			slot = data.slot,
			available = 1,
			blackout = 0
		}
		end
		inventory[data.type][data.slot].bits = data.bits
	end
	saveInventory()
end

function saveInventory()
	persistence.store(getWorkingDirectory() .. "/ArizonaMimgui/inventory-data.lua", inventory)
end

function loadInventory()
	local invfile, err = io.open(getWorkingDirectory() .. "/ArizonaMimgui/inventory-data.lua", "r")
	if invfile then
		inventory = persistence.load(getWorkingDirectory() .. "/ArizonaMimgui/inventory-data.lua")
	end
	if inventory == nil then inventory = {} end
end

loadInventory()
------------------------------------------- MIMGUI FANCIES --------------------------------------------------

function gui.RightText(text)
 
  	gui.SetCursorPosX(gui.GetWindowWidth() - gui.CalcTextSize(text).x - gui.GetStyle().WindowPadding.x);
    gui.Text(text);
end

function gui.RightTextColored(color, text)
	gui.SetCursorPosX(gui.GetWindowWidth() - gui.CalcTextSize(text).x - gui.GetStyle().WindowPadding.x);
    gui.TextColored(color, text);
end

function DrawRoundedGradientRect(DL, pos, size, colTL, colTR, colBL, colBR, radius, segments)
    segments = segments or 12
    radius = radius or 0
    radius = math.min(radius, size.x / 2, size.y / 2)

    local function drawCorner(DL, cx, cy, radius, color, quadrant, segments)
        segments = segments or 12
        local startAngle, endAngle

        if quadrant == 1 then
            startAngle, endAngle = math.pi, math.pi * 1.5
        elseif quadrant == 2 then
            startAngle, endAngle = math.pi * 1.5, math.pi * 2
        elseif quadrant == 3 then
            startAngle, endAngle = math.pi * 0.5, math.pi
        elseif quadrant == 4 then
            startAngle, endAngle = 0, math.pi * 0.5
        end

        DL:PathClear()
        DL:PathLineTo(gui.ImVec2(cx, cy))
        for i = 0, segments do
            local angle = startAngle + (endAngle - startAngle) * (i / segments)
            DL:PathLineTo(gui.ImVec2(cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
        end
        DL:PathFillConvex(color)
    end

    local cxTL, cyTL = pos.x + radius, pos.y + radius
    local cxTR, cyTR = pos.x + size.x - radius, pos.y + radius
    local cxBL, cyBL = pos.x + radius, pos.y + size.y - radius
    local cxBR, cyBR = pos.x + size.x - radius, pos.y + size.y - radius

    drawCorner(DL, cxTL, cyTL, radius, colTL, 1, segments)
    drawCorner(DL, cxTR, cyTR, radius, colTR, 2, segments)
    drawCorner(DL, cxBL, cyBL, radius, colBL, 3, segments)
    drawCorner(DL, cxBR, cyBR, radius, colBR, 4, segments)

    DL:AddRectFilledMultiColor(
        gui.ImVec2(pos.x + radius, pos.y),
        gui.ImVec2(pos.x + size.x - radius, pos.y + radius),
        colTL, colTR, colTR, colTL
    )

    DL:AddRectFilledMultiColor(
        gui.ImVec2(pos.x + radius, pos.y + size.y - radius),
        gui.ImVec2(pos.x + size.x - radius, pos.y + size.y),
        colBL, colBR, colBR, colBL
    )

    DL:AddRectFilledMultiColor(
        gui.ImVec2(pos.x, pos.y + radius),
        gui.ImVec2(pos.x + radius, pos.y + size.y - radius),
        colTL, colTL, colBL, colBL
    )

    DL:AddRectFilledMultiColor(
        gui.ImVec2(pos.x + size.x - radius, pos.y + radius),
        gui.ImVec2(pos.x + size.x, pos.y + size.y - radius),
        colTR, colTR, colBR, colBR
    )

    DL:AddRectFilledMultiColor(
        gui.ImVec2(pos.x + radius, pos.y + radius),
        gui.ImVec2(pos.x + size.x - radius, pos.y + size.y - radius),
        colTL, colTR, colBR, colBL
    )
end

function gui.ColoredButton(text,hex,trans,size)
    local r,g,b = tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
    if tonumber(trans) ~= nil and tonumber(trans) < 101 and tonumber(trans) > 0 then a = trans else a = 60 end

    local button = gui.Button(text, size)
    gui.PopStyleColor(3)
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

gui.WebImage = function(url, size)
	local iid = string.gsub(url, ".*arizona%-rp", "")
	local cachepath = cachedir .. string.gsub(url, ".*arizona%-rp", "")
	if imagesbuffer[iid] == nil then
		imagesbuffer[iid] = -1
		local file, file_err = io.open(cachepath)
		if not file then
			table.insert(cacher.queue, {url = url, cachepath = cachepath, iid = iid})
			cacher.maxqueue = math.max(#cacher.queue, cacher.maxqueue)
			imagesthreads[iid] = {dead = false}
			download_file(url, cachepath)--lua_thread.create(download_file, url, cachepath)
		else
			imagesthreads[iid] = {dead = true}
			file:close()
		end
	end
	if imagesbuffer[iid] == -1 then
		gui.Dummy(size)
		if imagesthreads[iid] and imagesthreads[iid].dead then
			imagesbuffer[iid] = gui.CreateTextureFromFile(cachepath)
		end
	else
		gui.Image(imagesbuffer[iid], size)
	end
end

------------------------------------------------ THEME -------------------------------------------------------

gui.OnInitialize(function()
    themeExample()
end)
function themeExample()
    gui.SwitchContext()
    local ImVec4 = gui.ImVec4
    
    gui.GetStyle().WindowPadding = gui.ImVec2(5 * c.ui.density, 5 * c.ui.density)
    gui.GetStyle().FramePadding = gui.ImVec2(5 * c.ui.density, 5 * c.ui.density)
    gui.GetStyle().ItemSpacing = gui.ImVec2(5 * c.ui.density, 5 * c.ui.density)
    gui.GetStyle().ItemInnerSpacing = gui.ImVec2(2 * c.ui.density, 2 * c.ui.density)
    gui.GetStyle().TouchExtraPadding = gui.ImVec2(0, 0)
    gui.GetStyle().IndentSpacing = 0
    gui.GetStyle().ScrollbarSize = 10 * c.ui.density
    gui.GetStyle().GrabMinSize = 10 * c.ui.density
    gui.GetStyle().WindowBorderSize = 0
    gui.GetStyle().ChildBorderSize = 1 * c.ui.density
    gui.GetStyle().PopupBorderSize = 1 * c.ui.density
    gui.GetStyle().FrameBorderSize = 1 * c.ui.density
    gui.GetStyle().TabBorderSize = 1 * c.ui.density
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
    if style == 6 and c.legacy.useLegacyDialogs then
        title = convert_money_tags(title)
        text = convert_money_tags(text)
        return {id, 1, title, button1, button2, text}
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

function onScriptTerminate(script, quit)
	if script == thisScript() then
		saveInventory()
	end
end

----------- Fix money display on legacy HUDs ------------

function ev.onResetPlayerMoney()
    return false
end

function ev.onGivePlayerMoney(money)
    return false
end

----------------- Legacy dialogs -- by quesada -----------

ffi.cdef[[
    void* LoadLibraryA(const char* lpLibFileName);
    void* GetProcAddress(void* hModule, const char* lpProcName);
    int   FreeLibrary(void* hModule);
]]

local kernel32 = ffi.load('kernel32')

local function format_with_dots(num) -- https://www.blast.hk/threads/253262/
    num = math.floor(tonumber(num) or 0)
    local s = tostring(num)
    local rev = s:reverse():gsub("(%d%d%d)", "%1.")
    s = rev:reverse()
    if s:sub(1, 1) == "." then
        s = s:sub(2)
    end
    return s
end

local function parse_k_value(str) -- https://www.blast.hk/threads/253262/
    str = tostring(str or "")
    str = str:gsub("%.", "")
    return tonumber(str) or 0
end

local function build_money(m, kk, k) -- https://www.blast.hk/threads/253262/
    local total = 0

    if m then
        total = total + (tonumber(m) or 0) * 1000000000
    end

    if kk then
        total = total + (tonumber(kk) or 0) * 1000000
    end

    if k then
        total = total + parse_k_value(k)
    end

    return format_with_dots(total)
end

local function convert_money_tags(text) -- https://www.blast.hk/threads/253262/
    if type(text) ~= "string" or text == "" then
        return text
    end

    text = text:gsub(":M:%s*(%d+)%s*:KK:%s*(%d+)%s*:K:%s*([%d%.]+)", function(m, kk, k)
        return build_money(m, kk, k)
    end)

    text = text:gsub(":M:%s*(%d+)%s*:KK:%s*(%d+)", function(m, kk)
        return build_money(m, kk, nil)
    end)

    text = text:gsub(":M:%s*(%d+)%s*:K:%s*([%d%.]+)", function(m, k)
        return build_money(m, nil, k)
    end)

    text = text:gsub(":KK:%s*(%d+)%s*:K:%s*([%d%.]+)", function(kk, k)
        return build_money(nil, kk, k)
    end)

    text = text:gsub(":M:%s*(%d+)", function(m)
        return build_money(m, nil, nil)
    end)

    text = text:gsub(":KK:%s*(%d+)", function(kk)
        return build_money(nil, kk, nil)
    end)

    text = text:gsub(":K:%s*([%d%.]+)", function(k)
        return build_money(nil, nil, k)
    end)

    return text
end

function loadDll()
    local hDll = kernel32.LoadLibraryA('vorbisFile.dll')
    if hDll == nil or hDll == ffi.cast('void*', 0) then
        print('error in LoadLibraryA')
        return nil, nil
    end
    local fnToggle = kernel32.GetProcAddress(hDll, 'ToggleCefDialogs')
    local fnAreEnabled = kernel32.GetProcAddress(hDll, 'AreCefDialogsEnabled')
    if fnToggle == nil or fnToggle == ffi.cast('void*', 0) then
        print('ToggleCefDialogs not found')
        return nil, nil
    end
    if fnAreEnabled == nil or fnAreEnabled == ffi.cast('void*', 0) then
        print('AreCefDialogsEnabled not found')
        return nil, nil
    end
    return ffi.cast('void(__cdecl*)(int)', fnToggle),
           ffi.cast('int(__cdecl*)(void)', fnAreEnabled)
end

function quesada_dialogs()
	toggleFn, areEnabledFn = loadDll()
    if not toggleFn then
        return print('error load dll!')
    end

    local ok, err = pcall(function() toggleFn(c.legacy.useLegacyDialogs and 0 or 1) end)
    if ok then
        print('CEF Dialogs disabled!')
    else
        print('error call ToggleCefDialogs: ' .. tostring(err))
        return
    end

    while c.legacy.useLegacyDialogs do wait(2000)
        local ok2, result = pcall(areEnabledFn)
        if ok2 and result ~= 0 then
            pcall(function() toggleFn(c.legacy.useLegacyDialogs and 0 or 1) end)
        end
    end
end

----------------- Legacy pause menu -- by Codex -------------

local WM_KEYDOWN = 0x0100
local VK_ESCAPE = 0x1B

local FIX_JS = [[
try {
  if (window && window.cef && typeof window.cef.HandleGameMenu === 'function') {
    window.cef.HandleGameMenu(false);
  }

  if (typeof window.executeEvent === 'function') {
    window.executeEvent('event.mainMenu.setMainMenuDisabled', `[true]`);
  }
} catch (e) {}
]]

local UNFIX_JS = [[
try {
  if (window && window.cef && typeof window.cef.HandleGameMenu === 'function') {
    window.cef.HandleGameMenu(true);
  }

  if (typeof window.executeEvent === 'function') {
    window.executeEvent('event.mainMenu.setMainMenuDisabled', `[false]`);
  }
} catch (e) {}
]]

function onWindowMessage(msg, wparam, lparam)
    if msg == WM_KEYDOWN and wparam == VK_ESCAPE and c.legacy.useLegacyPauseMenu then
        evalanon(FIX_JS)
    end
end

function pauseMenuThread()
	while c.legacy.useLegacyPauseMenu do
        wait(10000)
        evalanon(FIX_JS)
    end
 	evalanon(UNFIX_JS)
end

------------------- Nametags setting -- by quesada ----

function quesada_ntags_load()
    local hChat = kernel32.LoadLibraryA('_chat.asi')
    if hChat == nil or hChat == ffi.cast('void*', 0) then
        print('[CustomNametags] error: _chat.asi не найдена')
        return false
    end
    local fnPtr = kernel32.GetProcAddress(hChat, 'toggle_nametags')
    if fnPtr == nil or fnPtr == ffi.cast('void*', 0) then
        print('error: toggle_nametags не найдена')
        return false
    end
    -- +0: 55        push ebp
    -- +1: 8B EC     mov ebp, esp
    -- +3: 8A 45 08  mov al, [ebp+8]
    -- +6: A2        mov [quesada_ntags_flag_addr]
    -- +7: XX XX XX XX (4)
    local fn_va = tonumber(ffi.cast('uint32_t', fnPtr))
    local ok, opcode = pcall(readMemory, fn_va + 6, 1, false)
    if not ok or opcode ~= 0xA2 then
        print(string.format('error: 0x%02X > +6', opcode or 0))
        return false
    end
    local ok2, addr = pcall(readMemory, fn_va + 7, 4, false)
    if not ok2 then
        print('error: unknown flag')
        return false
    end
    quesada_ntags_flag_addr    = addr
    quesada_ntags_toggle_ntags = ffi.cast('void(__cdecl*)(bool)', fnPtr)
    print(string.format('toggle_nametags @ 0x%08X', fn_va))
    print(string.format('quesada_ntags_flag_addr = 0x%08X', quesada_ntags_flag_addr))
    return true
end

function quesada_nametags_toggle_fn()
    local ok, v = pcall(readMemory, quesada_ntags_flag_addr, 1, false)
    local enabled = ok and v == 1
    pcall(function() quesada_ntags_toggle_ntags(not enabled) end)
end

function quesada_nametags_force_state(enable)
    pcall(function() quesada_ntags_toggle_ntags(enable) end)
end