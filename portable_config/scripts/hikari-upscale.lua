-- hikari-upscale: Anime4K mode and quality picker for uosc.
--
-- Opens a uosc menu with two groups (mode, quality). Picking an option applies
-- it on the fly, keeps the menu open and refreshes it, and saves the choice to
-- `~~/hikari-upscale.conf`, which mpv.conf includes on the next start.
--
-- Anime4K (https://github.com/bloc97/Anime4K, MIT) is not bundled: the hikari
-- installer downloads release v4.0.1 and puts its Anime4K_*.glsl files in
-- `~~/shaders/`. Without them the menu says so and no mode can be picked.
--
-- mpv turns this file name into the script name `hikari_upscale`, so:
--   input.conf:  Ctrl+1 script-message-to hikari_upscale set-mode a
--                Ctrl+7 script-message-to hikari_upscale set-mode auto
--                Ctrl+0 script-message-to hikari_upscale set-mode off
--                (script-binding hikari_upscale/open-menu opens the menu)
--   options:     script-opts=hikari_upscale-mode=<id>,hikari_upscale-quality=<id>
--
-- How shaders are set. `glsl-shaders` is a path list, whose separator is `;` on
-- Windows and `:` elsewhere, so a joined string (`change-list glsl-shaders set
-- "a;b"`, as Anime4K's own input.conf templates do) would only work on one
-- platform. Instead:
--   - at run time the whole list is set at once with set_property_native and a
--     Lua array: no separator at all, and a single change for the renderer;
--   - the .conf uses `glsl-shaders-clr` followed by one `glsl-shaders-append`
--     per file (`-append` takes a single item and never splits it), so the
--     shaders are there from the first frame on any platform.
-- "Apagado" writes no glsl-shaders line at all: whatever mpv.conf says applies.
--
-- "Automático" (mode `auto`) picks a mode from the height of the video:
--   0 < h <= 576 -> C,  576 < h <= 810 -> B,  810 < h <= 1100 -> A+A,
--   h > 1100, no video, a still image or cover art, or a height not known
--   yet -> no Anime4K shaders,
-- at the saved quality. The height is only known once a file is open, so the
-- .conf cannot hold the shaders: for `auto` it writes no glsl-shaders line at
-- all (like "Apagado") and only saves `mode=auto`, never the mode it picked.
-- The script sets the list at run time instead: on every file-loaded and
-- whenever `height` or `video-params/h` changes, it works out the mode again
-- and sets that list with set_property_native (nothing is set when the list is
-- already the right one). "No shaders" puts back mpv.conf's own list, as
-- "Apagado" does. This is the robust way round: a stale or hand-edited
-- hikari-upscale.conf can never leave the wrong chain on for a file, and an
-- unknown height (audio, images still loading) simply waits for the next change.
--
-- The shader lists are the ones of Anime4K's official mpv templates
-- (md/Template/GLSL_*_High-end and _Low-end, input.conf, Ctrl+1..6), in the
-- same order: Alta = High-end (HQ), Rápida = Low-end (Fast).

local msg = require('mp.msg')
local utils = require('mp.utils')
local options = require('mp.options')

-- Texts in the chosen language: ~~/script-modules/hikari-i18n.lua. Single-file
-- scripts get no mpv folder in package.path, so the folder is added for this
-- one require and taken out again (see the header of hikari-i18n.lua).
local i18n = (function()
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, 'hikari-i18n')
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/hikari-i18n.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end)()

local script_name = mp.get_script_name()

local PERSIST_PATH = '~~/hikari-upscale.conf'
local SHADER_DIR = '~~/shaders'
local MENU_TYPE = 'hikari-upscale'
-- uosc shows the controls-bar button only while this is true (see uosc.conf).
local AVAILABLE_PROP = 'user-data/hikari_upscale/available'

-- `short` is how Anime4K names the mode (and how "Automático" names the mode
-- it picked); `like`, for the doubled modes, the mode they sharpen. Names and
-- hints come from hikari-i18n (upscale_mode_*, upscale_hint_*), short
-- descriptions after Anime4K's GLSL_Instructions_Advanced.md ("Modes").
local MODES = {
	{id = 'off'},
	{id = 'auto'},
	{id = 'a', short = 'A'},
	{id = 'b', short = 'B'},
	{id = 'c', short = 'C'},
	{id = 'aa', short = 'A+A', like = 'A'},
	{id = 'bb', short = 'B+B', like = 'B'},
	{id = 'ca', short = 'C+A', like = 'C'},
}

-- What "Automático" picks: the first rule whose `max` the height does not
-- exceed. Taller videos get no shaders.
local AUTO_RULES = {
	{max = 576, mode = 'c'},
	{max = 810, mode = 'b'},
	{max = 1100, mode = 'aa'},
}

-- Texts: upscale_quality_<id>, its _hint and its _osd in hikari-i18n.
local QUALITIES = {
	{id = 'hq'},
	{id = 'fast'},
}

local DEFAULTS = {mode = 'off', quality = 'fast'}

-- Shader file names (in ~~/shaders/) per quality and mode, in the order mpv runs them.
local CHAINS = {
	hq = {
		a = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl'},
		b = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl'},
		c = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl'},
		aa = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
			'Anime4K_Restore_CNN_M.glsl', 'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl',
			'Anime4K_Upscale_CNN_x2_M.glsl'},
		bb = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl',
			'Anime4K_Upscale_CNN_x2_M.glsl'},
		ca = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Restore_CNN_M.glsl',
			'Anime4K_Upscale_CNN_x2_M.glsl'},
	},
	fast = {
		a = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl'},
		b = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl'},
		c = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Upscale_CNN_x2_S.glsl'},
		aa = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl',
			'Anime4K_Restore_CNN_S.glsl', 'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl',
			'Anime4K_Upscale_CNN_x2_S.glsl'},
		bb = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Restore_CNN_Soft_S.glsl',
			'Anime4K_Upscale_CNN_x2_S.glsl'},
		ca = {'Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
			'Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl', 'Anime4K_Restore_CNN_S.glsl',
			'Anime4K_Upscale_CNN_x2_S.glsl'},
	},
}

-- Menu and OSD texts of a mode or a quality, in the current language.
local function mode_name(mode)
	if mode.short then return i18n.t('upscale_mode_named', {name = mode.short}) end
	return i18n.t('upscale_mode_' .. mode.id)
end
local function mode_hint(mode)
	if mode.like then return i18n.t('upscale_hint_double', {mode = mode.like}) end
	return i18n.t('upscale_hint_' .. mode.id)
end
local function quality_name(quality) return i18n.t('upscale_quality_' .. quality.id) end
local function quality_hint(quality) return i18n.t('upscale_quality_' .. quality.id .. '_hint') end
local function quality_osd(quality) return i18n.t('upscale_quality_' .. quality.id .. '_osd') end

local function index_by_id(list)
	local t = {}
	for _, item in ipairs(list) do t[item.id] = item end
	return t
end
local mode_by_id, quality_by_id = index_by_id(MODES), index_by_id(QUALITIES)

local function is_valid_id(id) return type(id) == 'string' and id:match('^[a-z0-9_-]+$') ~= nil end
local function is_shader_name(name) return type(name) == 'string' and name:match('^Anime4K_[%w_]+%.glsl$') ~= nil end

-- Every file any mode uses, once each, sorted: what "installed" means.
local function required_shaders()
	local seen, list = {}, {}
	for _, quality in ipairs(QUALITIES) do
		for _, mode in ipairs(MODES) do
			for _, name in ipairs(CHAINS[quality.id][mode.id] or {}) do
				if not seen[name] then seen[name] = true; list[#list + 1] = name end
			end
		end
	end
	table.sort(list)
	return list
end

-- The mode "Automático" picks for a video of that height, nil for none.
local function auto_mode_for(height)
	if type(height) ~= 'number' or height <= 0 then return nil end
	for _, rule in ipairs(AUTO_RULES) do
		if height <= rule.max then return mode_by_id[rule.mode] end
	end
	return nil
end

-- Height of the current video, nil when there is none or it is not known yet.
-- A still image or cover art (an audio file's album art) is not a video:
-- "Automático" leaves it without shaders.
local function video_height()
	if mp.get_property_native('current-tracks/video/image') == true
		or mp.get_property_native('current-tracks/video/albumart') == true then
		return nil
	end
	for _, prop in ipairs({'height', 'video-params/h'}) do
		local h = mp.get_property_native(prop)
		if type(h) == 'number' and h > 0 then return h end
	end
	return nil
end

-- The `~~/shaders/...` paths of a mode at a quality: an empty list for "Apagado"
-- and "Automático" (neither has a fixed list), nil when the table is broken
-- (unknown ids or a bad file name).
local function chain_paths(mode, quality)
	if not mode or not quality then return nil end
	if mode.id == 'off' or mode.id == 'auto' then return {} end
	local names = CHAINS[quality.id] and CHAINS[quality.id][mode.id]
	if not names or #names == 0 then return nil end
	local paths = {}
	for _, name in ipairs(names) do
		if not is_shader_name(name) then
			msg.error('Bad shader name in mode ' .. tostring(mode.id) .. ': ' .. tostring(name))
			return nil
		end
		paths[#paths + 1] = SHADER_DIR .. '/' .. name
	end
	return paths
end

-- True when every shader the modes use is in ~~/shaders/.
local function shaders_installed()
	local dir = mp.command_native({'expand-path', SHADER_DIR})
	if type(dir) ~= 'string' or dir == '' then return false end
	for _, name in ipairs(required_shaders()) do
		local file = io.open(dir .. '/' .. name, 'rb')
		if not file then return false end
		file:close()
	end
	return true
end

local function persist_content(mode, quality)
	if not mode or not quality or not is_valid_id(script_name) or not is_valid_id(mode.id)
		or not is_valid_id(quality.id) then
		return nil
	end
	local paths = chain_paths(mode, quality)
	if not paths then return nil end
	local lines = {'# Generated by hikari-upscale.lua. Mode: ' .. mode.id .. ', quality: ' .. quality.id}
	if #paths > 0 then
		lines[#lines + 1] = 'glsl-shaders-clr'
		for _, path in ipairs(paths) do lines[#lines + 1] = 'glsl-shaders-append="' .. path .. '"' end
	end
	lines[#lines + 1] = 'script-opts-append=' .. script_name .. '-mode=' .. mode.id
	lines[#lines + 1] = 'script-opts-append=' .. script_name .. '-quality=' .. quality.id
	return table.concat(lines, '\n') .. '\n'
end

-- Writes through a temporary file and a rename so a crash never leaves half a file.
local function write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	local file, err = io.open(tmp, 'wb')
	if not file then return false, err end
	local ok, write_err = file:write(content)
	local closed, close_err = file:close()
	if not ok or not closed then
		os.remove(tmp)
		return false, write_err or close_err
	end
	local renamed, rename_err = os.rename(tmp, path)
	if not renamed then
		-- On Windows rename() won't replace an existing file: remove it and retry.
		os.remove(path)
		renamed, rename_err = os.rename(tmp, path)
	end
	if not renamed then
		os.remove(tmp)
		return false, rename_err
	end
	return true
end

local function pick(by_id, id, what)
	if by_id[id] then return by_id[id] end
	msg.warn('Unknown upscale ' .. what .. ' "' .. tostring(id) .. '", using ' .. DEFAULTS[what])
	return by_id[DEFAULTS[what]]
end

local opts = {mode = DEFAULTS.mode, quality = DEFAULTS.quality}
options.read_options(opts, script_name)
-- `target`: the mode whose shaders are on (the one "Automático" picked, or the
-- fixed mode), nil when none are.
local active = {mode = pick(mode_by_id, opts.mode, 'mode'), quality = pick(quality_by_id, opts.quality, 'quality')}
local installed = false

-- What "Apagado" (and "Automático" without a mode) puts back: the list mpv
-- had at start-up when the saved mode was "Apagado" or "Automático" (so the
-- .conf set nothing and this is mpv.conf's list), an empty list otherwise
-- (mpv.conf's list was cleared by the .conf).
local baseline = {}
local function capture_baseline()
	baseline = {}
	local current = mp.get_property_native('glsl-shaders')
	if type(current) ~= 'table' then return end
	for _, path in ipairs(current) do
		if type(path) ~= 'string' then baseline = {}; return end
		baseline[#baseline + 1] = path
	end
end

local function same_list(a, b)
	if type(a) ~= 'table' or type(b) ~= 'table' or #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

-- Sets glsl-shaders to the list, unless it already is exactly that list (a
-- change makes mpv rebuild its shaders).
local function set_shaders(list)
	if same_list(mp.get_property_native('glsl-shaders'), list) then return end
	mp.set_property_native('glsl-shaders', list)
end

-- The mode whose shaders a choice turns on now: itself for a fixed mode, the
-- one picked from the height for "Automático", nil for none.
local function target_of(mode)
	if mode.id == 'off' then return nil end
	if mode.id == 'auto' then return auto_mode_for(video_height()) end
	return mode
end

local function apply(mode, quality)
	local paths = chain_paths(mode, quality)
	if not paths then return false end
	local target = target_of(mode)
	if target then
		local target_paths = chain_paths(target, quality)
		if not target_paths then return false end
		set_shaders(target_paths)
	else
		set_shaders(baseline)
	end
	active.mode, active.quality, active.target = mode, quality, target
	return true
end

local function save()
	local content = persist_content(active.mode, active.quality)
	local path = mp.command_native({'expand-path', PERSIST_PATH})
	local ok, err = false, 'invalid upscale settings'
	if content and path then ok, err = write_file_atomic(path, content) end
	if not ok then
		msg.warn('Could not save upscale settings to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message(i18n.t('upscale_save_failed'), 3)
	end
	return ok
end

-- "Automático" says what it picked and for which height: "Anime4K:
-- Automático (B, 720p)".
local function auto_detail()
	local height = video_height()
	if not height then return i18n.t('upscale_no_video') end
	local target = auto_mode_for(height)
	return (target and target.short or i18n.t('upscale_no_shaders')) .. ', ' .. math.floor(height) .. 'p'
end

local function osd_text(mode, quality)
	if mode.id == 'off' then return i18n.t('upscale_osd_off') end
	if mode.id == 'auto' then return 'Anime4K: ' .. mode_name(mode) .. ' (' .. auto_detail() .. ')' end
	return 'Anime4K: ' .. mode_name(mode) .. ' (' .. quality_osd(quality) .. ')'
end

local function refresh_installed()
	installed = shaders_installed()
	mp.set_property_native(AVAILABLE_PROP, installed)
	return installed
end

local function menu_data()
	local items = {}
	if not installed then
		items[#items + 1] = {
			title = i18n.t('upscale_not_installed_menu'),
			selectable = false, muted = true, italic = true, align = 'center', separator = true,
		}
	end
	local function group(title, list, current, message, name_of, hint_of)
		if #items > 0 then items[#items].separator = true end
		items[#items + 1] = {title = title, selectable = false, muted = true, italic = true}
		for _, entry in ipairs(list) do
			local usable = installed or (message == 'set-mode' and entry.id == 'off')
			local hint = hint_of(entry)
			if entry.id == 'auto' and entry == current and installed then
				hint = i18n.t('upscale_auto_now', {detail = auto_detail()})
			end
			items[#items + 1] = {
				title = name_of(entry),
				hint = hint,
				active = entry == current,
				selectable = usable,
				muted = not usable or nil,
				value = {'script-message-to', script_name, message, entry.id},
			}
		end
	end
	group(i18n.t('upscale_group_mode'), MODES, active.mode, 'set-mode', mode_name, mode_hint)
	group(i18n.t('upscale_group_quality'), QUALITIES, active.quality, 'set-quality', quality_name, quality_hint)
	-- keep_open: picking an item doesn't close the menu; each pick sends
	-- update-menu to move the marks.
	return {type = MENU_TYPE, title = i18n.t('upscale_title'), keep_open = true, items = items}
end

local function send_menu(message)
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the upscale menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

local function open_menu()
	refresh_installed()
	send_menu('open-menu')
end

-- Ids come from outside (menu, input.conf), so they must match a table.
local function set_mode(id)
	local mode = mode_by_id[id]
	if not mode then
		msg.warn('Ignoring unknown upscale mode: ' .. tostring(id))
		return
	end
	if mode.id ~= 'off' and not refresh_installed() then
		mp.osd_message(i18n.t('upscale_not_installed_osd'), 3)
		return
	end
	if apply(mode, active.quality) then
		save()
		mp.osd_message(osd_text(mode, active.quality), 2)
		-- uosc only updates a menu of this type if it is still open.
		send_menu('update-menu')
	end
end

local function set_quality(id)
	local quality = quality_by_id[id]
	if not quality then
		msg.warn('Ignoring unknown upscale quality: ' .. tostring(id))
		return
	end
	if not refresh_installed() then
		mp.osd_message(i18n.t('upscale_not_installed_osd'), 3)
		return
	end
	if apply(active.mode, quality) then
		save()
		if active.mode.id == 'auto' then
			mp.osd_message('Anime4K: ' .. mode_name(active.mode) .. ' (' .. quality_osd(quality) .. ')', 2)
		elseif active.mode.id ~= 'off' then
			mp.osd_message(osd_text(active.mode, quality), 2)
		end
		send_menu('update-menu')
	end
end

-- "Automático": a new file, or a new height, may need another mode. Nothing
-- is saved: the .conf keeps `mode=auto`.
local function on_video_change()
	if active.mode.id ~= 'auto' or not installed then return end
	apply(active.mode, active.quality)
end

mp.register_script_message('set-mode', set_mode)
mp.register_script_message('set-quality', set_quality)
mp.add_key_binding(nil, 'open-menu', open_menu)
-- Another language: an open upscale menu is redrawn in it.
i18n.on_change(function()
	if mp.get_property_native('user-data/uosc/menu/type') == MENU_TYPE then send_menu('update-menu') end
end)
mp.register_event('file-loaded', on_video_change)
mp.observe_property('height', 'native', on_video_change)
mp.observe_property('video-params/h', 'native', on_video_change)
mp.observe_property('current-tracks/video/image', 'native', on_video_change)

-- Start-up: the included .conf already set the shaders for the first frame.
-- Setting them again from the table only happens when they differ (the table
-- was edited), and never for "Apagado", so mpv.conf's own list stays untouched.
-- "Automático" starts like "Apagado" and picks a mode once a video is open.
-- Without the shader files, a saved mode is dropped for this session (mpv would
-- fail to load every shader) but stays saved for when they are back.
if active.mode.id == 'off' or active.mode.id == 'auto' then capture_baseline() end
refresh_installed()
if active.mode.id == 'auto' then
	if installed then
		apply(active.mode, active.quality)
	else
		msg.warn('Anime4K shaders not found in ' .. SHADER_DIR .. ': upscaling is off')
	end
elseif active.mode.id ~= 'off' then
	if installed then
		apply(active.mode, active.quality)
	else
		msg.warn('Anime4K shaders not found in ' .. SHADER_DIR .. ': upscaling is off')
		set_shaders({})
	end
end

if HIKARI_UPSCALE_TEST then
	return {
		MODES = MODES, QUALITIES = QUALITIES, CHAINS = CHAINS, DEFAULTS = DEFAULTS, AUTO_RULES = AUTO_RULES,
		auto_mode_for = auto_mode_for, mode_name = mode_name, mode_hint = mode_hint, video_height = video_height, on_video_change = on_video_change,
		mode_by_id = mode_by_id, quality_by_id = quality_by_id,
		required_shaders = required_shaders, chain_paths = chain_paths,
		shaders_installed = shaders_installed, persist_content = persist_content,
		write_file_atomic = write_file_atomic, apply = apply, osd_text = osd_text,
		set_mode = set_mode, set_quality = set_quality, menu_data = menu_data, open_menu = open_menu,
		is_valid_id = is_valid_id, is_shader_name = is_shader_name,
		get_active = function() return active end,
		get_baseline = function() return baseline end,
		is_installed = function() return installed end,
	}
end
