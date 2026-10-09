-- Run from the repository root: lua tests/test_upscale.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-upscale.lua'
local SCRIPT_NAME = 'hikari_upscale'
local CONF = '~~/hikari-upscale.conf'
local AVAILABLE = 'user-data/hikari_upscale/available'

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. '\n     ' .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error((what or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
end

-- The shader lists of Anime4K v4.0.1's official mpv templates
-- (md/Template/GLSL_Windows_High-end and _Low-end, input.conf, Ctrl+1..6), with
-- `~~/shaders/` taken out. Mode order: A, B, C, A+A, B+B, C+A.
local OFFICIAL = {
	hq = {
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_VL.glsl;Anime4K_Upscale_CNN_x2_VL.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_Soft_VL.glsl;Anime4K_Upscale_CNN_x2_VL.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Upscale_Denoise_CNN_x2_VL.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_VL.glsl;Anime4K_Upscale_CNN_x2_VL.glsl;Anime4K_Restore_CNN_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_Soft_VL.glsl;Anime4K_Upscale_CNN_x2_VL.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Restore_CNN_Soft_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Upscale_Denoise_CNN_x2_VL.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Restore_CNN_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl',
	},
	fast = {
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_Soft_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Upscale_Denoise_CNN_x2_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl;Anime4K_Restore_CNN_S.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Restore_CNN_Soft_M.glsl;Anime4K_Upscale_CNN_x2_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Restore_CNN_Soft_S.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
		'Anime4K_Clamp_Highlights.glsl;Anime4K_Upscale_Denoise_CNN_x2_M.glsl;Anime4K_AutoDownscalePre_x2.glsl;Anime4K_AutoDownscalePre_x4.glsl;Anime4K_Restore_CNN_S.glsl;Anime4K_Upscale_CNN_x2_S.glsl',
	},
}
local MODE_ORDER = {'a', 'b', 'c', 'aa', 'bb', 'ca'}

-- What install/hikari.ps1 checks the downloaded zip for ($script:Anime4KRequired).
local REQUIRED = {
	'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Clamp_Highlights.glsl',
	'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Restore_CNN_S.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl',
	'Anime4K_Restore_CNN_Soft_S.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Restore_CNN_VL.glsl',
	'Anime4K_Upscale_CNN_x2_M.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
	'Anime4K_Upscale_Denoise_CNN_x2_M.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
}

local function tmp_path()
	local path = os.tmpname()
	os.remove(path)
	return path
end

local function read(path)
	local f = assert(io.open(path, 'rb')); local content = f:read('*a'); f:close()
	return content
end

local function write(path, content)
	local f = assert(io.open(path, 'wb')); f:write(content); f:close()
end

-- A shaders folder with every required file (or `missing` left out).
local function make_shader_dir(missing)
	local dir = tmp_path()
	assert(os.execute('mkdir -p "' .. dir .. '"'))
	for _, name in ipairs(REQUIRED) do
		if name ~= missing then write(dir .. '/' .. name, '// shader') end
	end
	return dir
end
local SHADERS = make_shader_dir()
local EMPTY_SHADERS = make_shader_dir('Anime4K_Restore_CNN_VL.glsl')

-- Loads the script with fresh mocks. `shaders`: the folder ~~/shaders expands to.
-- `current`: glsl-shaders at start-up (what mpv.conf and the .conf set).
local function load(script_opts, shaders, current)
	mock.install(SCRIPT_NAME)
	mock.script_opts = script_opts or {}
	mock.expand['~~/shaders'] = shaders or SHADERS
	mock.props['glsl-shaders'] = current or {}
	HIKARI_UPSCALE_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function opt(mode, quality)
	return {[SCRIPT_NAME .. '-mode'] = mode, [SCRIPT_NAME .. '-quality'] = quality}
end

-- glsl-shaders writes since the last reset.
local function shader_sets()
	local list = {}
	for _, s in ipairs(mock.native_sets) do
		if s[1] == 'glsl-shaders' then list[#list + 1] = s[2] end
	end
	return list
end

local function joined(paths)
	local names = {}
	for i, p in ipairs(paths) do
		eq(p:sub(1, 11), '~~/shaders/', 'path prefix')
		names[i] = p:sub(12)
	end
	return table.concat(names, ';')
end

local function last_menu(message)
	for i = #mock.commands, 1, -1 do
		local c = mock.commands[i]
		if c[1] == 'script-message-to' and c[2] == 'uosc' and c[3] == message then return c[4] end
	end
end

test('chains are the official Anime4K ones, HQ and Fast, for every mode', function()
	local s = load()
	for quality, list in pairs(OFFICIAL) do
		for i, mode in ipairs(MODE_ORDER) do
			local paths = assert(s.chain_paths(s.mode_by_id[mode], s.quality_by_id[quality]))
			eq(joined(paths), list[i], quality .. ' ' .. mode)
		end
	end
	eq(#s.chain_paths(s.mode_by_id.off, s.quality_by_id.hq), 0, 'off is empty')
	eq(#s.chain_paths(s.mode_by_id.auto, s.quality_by_id.hq), 0, 'auto has no fixed list')
	eq(#s.MODES, 8, 'modes')
	eq(#s.QUALITIES, 2, 'qualities')
end)

test('required shaders match the installer list; names are safe', function()
	local s = load()
	local req = s.required_shaders()
	eq(table.concat(req, ','), table.concat(REQUIRED, ','), 'required list')
	for _, name in ipairs(req) do assert(s.is_shader_name(name), name) end
	for _, bad in ipairs({'../x.glsl', 'Anime4K_x.glsl;rm', 'Anime4K_a/b.glsl', 'other.glsl', 'Anime4K_.lua'}) do
		assert(not s.is_shader_name(bad), bad)
	end
	-- The installers keep the same list: compare with install/hikari.ps1 and install/hikari.sh.
	local sh = read('install/hikari.sh')
	local sh_block = assert(sh:match('ANIME4K_REQUIRED=%((.-)%)'), 'ANIME4K_REQUIRED in hikari.sh')
	local sh_names = {}
	for name in sh_block:gmatch("'(Anime4K_[%w_]+%.glsl)'") do sh_names[#sh_names + 1] = name end
	table.sort(sh_names)
	eq(table.concat(sh_names, ','), table.concat(REQUIRED, ','), 'hikari.sh list')
	local ps1 = read('install/hikari.ps1')
	local block = assert(ps1:match('%$script:Anime4KRequired = @%((.-)%)'), 'Anime4KRequired in hikari.ps1')
	local names = {}
	for name in block:gmatch("'(Anime4K_[%w_]+%.glsl)'") do names[#names + 1] = name end
	table.sort(names)
	eq(table.concat(names, ','), table.concat(REQUIRED, ','), 'installer list')
end)

test('start-up with the default (off): nothing set, baseline kept, button shown', function()
	local s = load(nil, SHADERS, {'~~/shaders/mine.glsl'})
	eq(#shader_sets(), 0, 'no glsl-shaders write')
	eq(s.get_active().mode.id, 'off', 'mode')
	eq(s.get_active().quality.id, 'fast', 'quality')
	eq(s.get_baseline()[1], '~~/shaders/mine.glsl', 'baseline from mpv.conf')
	eq(mock.props[AVAILABLE], true, 'available')
end)

test('start-up with a saved mode re-applies only when the list differs', function()
	local s = load(opt('a', 'hq'), SHADERS, {})
	local sets = shader_sets()
	eq(#sets, 1, 'one write')
	eq(joined(sets[1]), OFFICIAL.hq[1], 'mode A HQ')
	eq(#s.get_baseline(), 0, 'baseline empty: mpv.conf list was cleared by the .conf')
	-- Same list already there (the .conf set it): no write.
	local same = {}
	for i, p in ipairs(sets[1]) do same[i] = p end
	load(opt('a', 'hq'), SHADERS, same)
	eq(#shader_sets(), 0, 'no write when equal')
end)

test('start-up without the shaders: saved mode dropped for the session, button hidden', function()
	local s = load(opt('b', 'fast'), EMPTY_SHADERS, {'~~/shaders/Anime4K_Clamp_Highlights.glsl'})
	eq(mock.props[AVAILABLE], false, 'not available')
	assert(not s.is_installed(), 'not installed')
	local sets = shader_sets()
	eq(#sets, 1, 'cleared')
	eq(#sets[1], 0, 'empty list')
	eq(s.get_active().mode.id, 'b', 'choice kept for later')
	assert(#mock.logs.warn >= 1, 'warned')
end)

test('set-mode applies, saves atomically and shows the OSD', function()
	local path = tmp_path()
	local s = load()
	mock.expand[CONF] = path
	mock.messages['set-mode']('c')
	local sets = shader_sets()
	eq(#sets, 1, 'one write')
	eq(joined(sets[1]), OFFICIAL.fast[3], 'mode C fast')
	eq(mock.osd[#mock.osd], 'Anime4K: Modo C (Rápido)', 'osd')
	local content = read(path)
	local expected = '# Generated by hikari-upscale.lua. Mode: c, quality: fast\nglsl-shaders-clr\n'
	for name in OFFICIAL.fast[3]:gmatch('[^;]+') do expected = expected .. 'glsl-shaders-append="~~/shaders/' .. name .. '"\n' end
	expected = expected .. 'script-opts-append=hikari_upscale-mode=c\nscript-opts-append=hikari_upscale-quality=fast\n'
	eq(content, expected, 'conf')
	assert(not io.open(path .. '.tmp', 'rb'), 'no tmp left')
	assert(last_menu('update-menu'), 'menu refreshed')
	os.remove(path)
end)

test('set-quality re-applies the current mode; off only saves', function()
	local path = tmp_path()
	local s = load(opt('aa', 'fast'), SHADERS, {})
	mock.expand[CONF] = path
	mock.native_sets = {}
	mock.messages['set-quality']('hq')
	eq(joined(shader_sets()[1]), OFFICIAL.hq[4], 'A+A HQ')
	eq(mock.osd[#mock.osd], 'Anime4K: Modo A+A (Alta calidad)', 'osd')
	assert(read(path):find('quality: hq', 1, true), 'saved')
	mock.messages['set-mode']('off')
	local sets = shader_sets()
	eq(#sets[#sets], 0, 'off: back to the (empty) baseline')
	eq(mock.osd[#mock.osd], 'Anime4K: apagado', 'osd off')
	eq(read(path), '# Generated by hikari-upscale.lua. Mode: off, quality: hq\nscript-opts-append=hikari_upscale-mode=off\nscript-opts-append=hikari_upscale-quality=hq\n', 'off conf has no glsl lines')
	mock.native_sets = {}
	local osd_count = #mock.osd
	mock.messages['set-quality']('fast')
	eq(#shader_sets(), 0, 'off: quality change sets nothing')
	eq(#mock.osd, osd_count, 'no OSD while off')
	os.remove(path)
end)

test('off puts back the start-up list from mpv.conf', function()
	local path = tmp_path()
	load(nil, SHADERS, {'~~/shaders/mine.glsl'})
	mock.expand[CONF] = path
	mock.messages['set-mode']('a')
	mock.messages['set-mode']('off')
	local sets = shader_sets()
	eq(#sets, 2, 'two writes')
	eq(sets[2][1], '~~/shaders/mine.glsl', 'user list back')
	os.remove(path)
end)

test('unknown or hostile ids are ignored', function()
	local path = tmp_path()
	local s = load()
	mock.expand[CONF] = path
	for _, id in ipairs({'d', 'A', '', 'a;rm', '../a', 'off ', nil}) do mock.messages['set-mode'](id) end
	for _, id in ipairs({'ultra', 'HQ', ''}) do mock.messages['set-quality'](id) end
	eq(#shader_sets(), 0, 'nothing set')
	assert(not io.open(path, 'rb'), 'nothing saved')
	eq(s.get_active().mode.id, 'off', 'mode unchanged')
	-- Unknown saved values fall back to the defaults.
	s = load(opt('zzz', 'ultra'))
	eq(s.get_active().mode.id, 'off', 'mode default')
	eq(s.get_active().quality.id, 'fast', 'quality default')
end)

test('without the shaders: modes refused with a message, Apagado still works', function()
	local path = tmp_path()
	local s = load(nil, EMPTY_SHADERS)
	mock.expand[CONF] = path
	mock.messages['set-mode']('a')
	eq(#shader_sets(), 0, 'nothing set')
	assert(mock.osd[#mock.osd]:find('no está instalado', 1, true), 'osd says why')
	assert(not io.open(path, 'rb'), 'nothing saved')
	mock.messages['set-quality']('hq')
	eq(s.get_active().quality.id, 'fast', 'quality refused too')
	mock.messages['set-mode']('off')
	assert(io.open(path, 'rb'), 'off saved')
	os.remove(path)
end)

test('menu: groups, marks, values and the not-installed line', function()
	local s = load(opt('bb', 'hq'))
	mock.bindings['open-menu']()
	local json = assert(last_menu('open-menu'), 'menu sent')
	local menu = s.menu_data()
	eq(menu.type, 'hikari-upscale', 'type')
	eq(menu.keep_open, true, 'keep_open')
	eq(menu.title, 'Escalado (Anime4K)', 'title')
	eq(#menu.items, 1 + 8 + 1 + 2, 'items')
	eq(menu.items[1].title, 'Modo', 'mode header')
	eq(menu.items[2].title, 'Apagado', 'off first')
	eq(menu.items[3].title, 'Automático', 'then Automático')
	eq(menu.items[3].value[4], 'auto', 'auto id')
	eq(menu.items[10].title, 'Calidad', 'quality header')
	local active = {}
	for _, item in ipairs(menu.items) do
		if item.active then active[#active + 1] = item.title end
		if item.value then
			eq(item.value[1], 'script-message-to', 'value cmd')
			eq(item.value[2], SCRIPT_NAME, 'value target')
			assert(item.selectable, item.title .. ' selectable')
			assert(item.hint and #item.hint > 0, item.title .. ' has a description')
		end
	end
	eq(table.concat(active, ','), 'Modo B+B,Alta', 'active marks')
	eq(menu.items[8].value[3], 'set-mode', 'mode message')
	eq(menu.items[8].value[4], 'bb', 'mode id')
	eq(menu.items[11].value[4], 'hq', 'quality id')
	assert(json:find('"keep_open":true', 1, true), 'json keep_open')
	assert(not json:find('no está instalado', 1, true), 'no install line')

	s = load(nil, EMPTY_SHADERS)
	menu = s.menu_data()
	eq(menu.items[1].title, 'Anime4K no está instalado: ejecuta el instalador', 'install line first')
	eq(menu.items[1].selectable, false, 'info not selectable')
	for _, item in ipairs(menu.items) do
		if item.value then
			eq(item.selectable, item.value[4] == 'off', item.title .. ' selectable only if Apagado')
		end
	end
end)

test('the shipped hikari-upscale.conf is what the script writes for the defaults', function()
	local s = load()
	eq(read('portable_config/hikari-upscale.conf'), s.persist_content(s.mode_by_id.off, s.quality_by_id.fast), 'default conf')
	eq(s.DEFAULTS.mode, 'off', 'default mode')
	eq(s.DEFAULTS.quality, 'fast', 'default quality')
end)

test('mpv.conf includes hikari-upscale.conf; uosc.conf has the button for videos with Anime4K', function()
	assert(read('portable_config/mpv.conf'):find('\ninclude="~~/hikari-upscale.conf"\n', 1, true), 'include')
	local uosc = read('portable_config/script-opts/uosc.conf')
	assert(uosc:find('<video+' .. AVAILABLE .. '>command:auto_awesome:script-binding hikari_upscale/open-menu?Escalado', 1, true), 'button')
end)

-- Automático -------------------------------------------------------------------

local function auto_conf(quality)
	return '# Generated by hikari-upscale.lua. Mode: auto, quality: ' .. quality ..
		'\nscript-opts-append=hikari_upscale-mode=auto\nscript-opts-append=hikari_upscale-quality=' .. quality .. '\n'
end

local function last_set()
	local sets = shader_sets()
	return sets[#sets]
end

test('auto: exact cuts at 576/577, 810/811, 1100/1101; 0, negative and nil mean none', function()
	local s = load()
	local cases = {{1, 'c'}, {480, 'c'}, {576, 'c'}, {577, 'b'}, {720, 'b'}, {810, 'b'}, {811, 'aa'},
		{1080, 'aa'}, {1100, 'aa'}, {1101, nil}, {2160, nil}, {0, nil}, {-1, nil}}
	for _, c in ipairs(cases) do
		local m = s.auto_mode_for(c[1])
		eq(m and m.id, c[2], 'height ' .. c[1])
	end
	eq(s.auto_mode_for(nil), nil, 'nil')
	eq(s.auto_mode_for('720'), nil, 'not a number')
end)

test('auto: set-mode picks from the height, OSD names it, saves only mode=auto', function()
	local path = tmp_path()
	local s = load(nil, SHADERS, {})
	mock.expand[CONF] = path
	mock.props['height'] = 720
	mock.messages['set-mode']('auto')
	eq(joined(last_set()), OFFICIAL.fast[2], 'B fast for 720p')
	eq(mock.osd[#mock.osd], 'Anime4K: Automático (B, 720p)', 'osd')
	eq(read(path), auto_conf('fast'), 'conf has no shader lines')
	eq(s.persist_content(s.mode_by_id.auto, s.quality_by_id.hq), auto_conf('hq'), 'persist hq')
	eq(s.get_active().mode.id, 'auto', 'mode stays auto')
	eq(s.get_active().target.id, 'b', 'target b')
	os.remove(path)
end)

test('auto: each new file or height picks again; tall or no video puts mpv.conf back', function()
	local path = tmp_path()
	load(nil, SHADERS, {'~~/shaders/mine.glsl'})
	mock.expand[CONF] = path
	mock.messages['set-mode']('auto')
	eq(mock.osd[#mock.osd], 'Anime4K: Automático (sin vídeo)', 'no video yet')
	eq(#shader_sets(), 0, 'nothing set without a height')
	mock.set('height', 1080)
	eq(joined(last_set()), OFFICIAL.fast[4], 'A+A for 1080p')
	local count = #shader_sets()
	mock.set('height', 1080)
	eq(#shader_sets(), count, 'same height: no rebuild')
	mock.set('height', 2160)
	eq(last_set()[1], '~~/shaders/mine.glsl', '4K: mpv.conf list back')
	eq(#last_set(), 1, 'only that one')
	mock.set('height', nil)
	eq(last_set()[1], '~~/shaders/mine.glsl', 'between files: mpv.conf list')
	-- file-loaded with only video-params/h known.
	mock.props['video-params/h'] = 480
	mock.events['file-loaded']()
	eq(joined(last_set()), OFFICIAL.fast[3], 'C from video-params/h')
	mock.props['video-params/h'] = nil
	mock.set('height', 577)
	eq(joined(last_set()), OFFICIAL.fast[2], 'B for 577')
	eq(read(path), auto_conf('fast'), 'the picked mode is never saved')
	os.remove(path)
end)

test('auto: a still image or cover art gets no shaders', function()
	local path = tmp_path()
	load(nil, SHADERS, {'~~/shaders/mine.glsl'})
	mock.expand[CONF] = path
	mock.props['height'] = 720
	mock.messages['set-mode']('auto')
	eq(joined(last_set()), OFFICIAL.fast[2], 'a 720p video: B')
	-- An image (720 px tall) opened next.
	mock.props['current-tracks/video/image'] = true
	mock.events['file-loaded']()
	eq(last_set()[1], '~~/shaders/mine.glsl', 'image: mpv.conf list back')
	eq(#last_set(), 1, 'only that one')
	eq(mock.osd[#mock.osd], 'Anime4K: Automático (B, 720p)', 'no new OSD on file change')
	-- An audio file with its cover art (480 px tall).
	mock.props['current-tracks/video/image'] = nil
	mock.props['current-tracks/video/albumart'] = true
	mock.set('height', 480)
	eq(last_set()[1], '~~/shaders/mine.glsl', 'cover art: still no Anime4K')
	-- Back to a real video.
	mock.props['current-tracks/video/albumart'] = false
	mock.set('height', 480)
	eq(joined(last_set()), OFFICIAL.fast[3], 'a 480p video: C')
	local s = load()
	mock.props['current-tracks/video/image'] = true
	mock.props['height'] = 1080
	eq(s.video_height(), nil, 'video_height is nil for an image')
	os.remove(path)
end)

test('auto: quality hq vs fast', function()
	local path = tmp_path()
	load(opt('auto', 'fast'), SHADERS, {})
	mock.expand[CONF] = path
	mock.set('height', 576)
	eq(joined(last_set()), OFFICIAL.fast[3], 'C fast')
	mock.messages['set-quality']('hq')
	eq(joined(last_set()), OFFICIAL.hq[3], 'C hq')
	eq(mock.osd[#mock.osd], 'Anime4K: Automático (Alta calidad)', 'osd quality')
	eq(read(path), auto_conf('hq'), 'saved: auto, hq')
	mock.set('height', 1000)
	eq(joined(last_set()), OFFICIAL.hq[4], 'A+A hq')
	os.remove(path)
end)

test('auto: start-up with mode=auto keeps mpv.conf list until a video comes', function()
	local s = load(opt('auto', 'hq'), SHADERS, {'~~/shaders/mine.glsl'})
	eq(#shader_sets(), 0, 'no write at start-up')
	eq(s.get_baseline()[1], '~~/shaders/mine.glsl', 'baseline captured')
	eq(s.get_active().mode.id, 'auto', 'mode')
	mock.set('height', 720)
	eq(joined(last_set()), OFFICIAL.hq[2], 'B hq')
	-- Without the shaders: nothing happens on height changes.
	load(opt('auto', 'fast'), EMPTY_SHADERS, {})
	mock.set('height', 720)
	mock.events['file-loaded']()
	eq(#shader_sets(), 0, 'not installed: nothing set')
end)

test('auto: fixed modes ignore the height; switching away from auto stops it', function()
	local path = tmp_path()
	load(nil, SHADERS, {})
	mock.expand[CONF] = path
	mock.props['height'] = 480
	mock.messages['set-mode']('auto')
	mock.messages['set-mode']('a')
	local count = #shader_sets()
	eq(joined(last_set()), OFFICIAL.fast[1], 'mode A')
	mock.set('height', 2160)
	mock.events['file-loaded']()
	eq(#shader_sets(), count, 'no change with a fixed mode')
	mock.messages['set-mode']('off')
	mock.set('height', 480)
	eq(#last_set(), 0, 'off stays off')
	os.remove(path)
end)

test('auto: OSD for a tall video and the menu hint say what it does', function()
	local path = tmp_path()
	local s = load(nil, SHADERS, {})
	mock.expand[CONF] = path
	mock.props['height'] = 2160
	mock.messages['set-mode']('auto')
	eq(mock.osd[#mock.osd], 'Anime4K: Automático (sin shaders, 2160p)', 'osd 4K')
	local menu = s.menu_data()
	eq(menu.items[3].hint, 'ahora: sin shaders, 2160p', 'hint')
	eq(menu.items[3].active, true, 'auto marked')
	os.remove(path)
end)

test('input.conf binds Ctrl+7 to auto', function()
	assert(read('portable_config/input.conf'):find('\nCtrl+7  script-message-to hikari_upscale set-mode auto\n', 1, true), 'Ctrl+7')
	local ps1 = read('install/hikari.ps1')
	assert(ps1:find("Key = 'Ctrl+7'; Command = 'script-message-to hikari_upscale set-mode auto'", 1, true), 'installer Ctrl+7')
	local sh = read('install/hikari.sh')
	assert(sh:find("'Ctrl+7|script-message-to hikari_upscale set-mode auto'", 1, true), 'hikari.sh Ctrl+7')
end)

test('the installers write the same hikari-upscale.conf as the script for auto', function()
	local s = load()
	local ps1 = read('install/hikari.ps1')
	assert(ps1:find("'# Generated by hikari-upscale.lua. Mode: ' + $Mode + ', quality: ' + $Quality", 1, true), 'ps1 header')
	local sh = read('install/hikari.sh')
	assert(sh:find("UPSCALE_CONF_FORMAT='# Generated by hikari-upscale.lua. Mode: %s, quality: %s\\nscript-opts-append=hikari_upscale-mode=%s\\nscript-opts-append=hikari_upscale-quality=%s\\n'", 1, true), 'hikari.sh format')
	eq(s.persist_content(s.mode_by_id.auto, s.quality_by_id.fast), auto_conf('fast'), 'script')
end)

os.remove(SHADERS); os.execute('rm -rf "' .. SHADERS .. '" "' .. EMPTY_SHADERS .. '"')
print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
