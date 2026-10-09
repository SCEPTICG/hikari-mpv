-- hikari-subs: subtitle style, size and height picker for uosc.
--
-- Opens a uosc menu with three groups (style, size, height). Picking an option
-- applies it on the fly with `set`, keeps the menu open and refreshes it, and
-- saves the whole combination to `~~/hikari-subs.conf`, which mpv.conf includes on
-- the next start.
--
-- mpv turns this file name into the script name `hikari_subs`, so:
--   input.conf:  Alt+t script-binding hikari_subs/open-menu
--   options:     script-opts=hikari_subs-style=<id>,hikari_subs-size=<id>,hikari_subs-height=<id>
--
-- Colours use mpv's `#AARRGGBB` format. Careful: mpv's alpha is the OPACITY
-- (FF = opaque, 00 = invisible), the opposite of ASS's `&HAABBGGRR`, where 00 is
-- opaque. `#C0000000` is black at 75 % opacity.
--
-- Only text subtitles (SRT, WebVTT...) take the style: mpv's default
-- `sub-ass-override=scale` keeps ASS styling but still applies `sub-scale`, and
-- `sub-pos` moves ASS dialogue as well. This script never touches
-- `sub-ass-override`.

local msg = require('mp.msg')
local utils = require('mp.utils')
local options = require('mp.options')

local script_name = mp.get_script_name()

local PERSIST_PATH = '~~/hikari-subs.conf'
local MENU_TYPE = 'hikari-subs'

-- Style keys, in the order they are applied and written. Each key maps to the
-- mpv options that can hold it, newest name first. mpv 0.39 changed the model:
--   - mpv <= 0.38: sub-border-color/size, sub-shadow-color is its own option
--     (shadow colour), there is no sub-border-style, and a sub-back-color with
--     any opacity turns on a background box in that colour (libass BorderStyle 4).
--   - mpv >= 0.39: sub-outline-color/size (sub-border-color/size are aliases),
--     sub-border-style exists, and sub-shadow-color is an ALIAS of sub-back-color,
--     which is the shadow colour (or the box with background-box).
-- The first name this mpv knows is used, resolved to its canonical name through
-- option-info/<name>/name, so aliases collapse onto the real option (in 0.39+
-- shadow_color and box_color are both sub-back-color). Keys with no known option
-- are skipped.
local STYLE_KEYS = {
	{key = 'text_color', props = {'sub-color'}, kind = 'color'},
	{key = 'outline_color', props = {'sub-outline-color', 'sub-border-color'}, kind = 'color'},
	{key = 'outline_size', props = {'sub-outline-size', 'sub-border-size'}, kind = 'number'},
	{key = 'shadow_offset', props = {'sub-shadow-offset'}, kind = 'number'},
	{key = 'shadow_color', props = {'sub-shadow-color'}, kind = 'color'},
	{key = 'box_color', props = {'sub-back-color'}, kind = 'color'},
	{key = 'bold', props = {'sub-bold'}, kind = 'bool'},
	{key = 'border_style', props = {'sub-border-style'}, kind = 'border_style'},
}

-- Values are strings, as `set` receives them, so the decimal separator never
-- depends on the C locale. A key left out keeps what mpv had before hikari touched
-- it (see `baseline`) and is not written to the .conf.
-- Styles must not set both shadow_color and box_color: on mpv 0.39+ they are the
-- same option (sub-back-color). The tests check this. Only "Caja oscura" may give
-- sub-back-color opacity: on mpv <= 0.38 that alone turns on the background box.
local STYLES = {
	-- Sets nothing: mpv's defaults or whatever mpv.conf says.
	{id = 'original', name = 'Original'},
	-- Netflix-like: white text on a translucent black box, no shadow.
	-- mpv 0.39+: opaque-box (libass BorderStyle 3), drawn with the outline colour
	-- and padded by the outline size; sub-back-color only colours the shadow,
	-- which is off. mpv <= 0.38: no sub-border-style; the translucent
	-- sub-back-color itself turns on the background box (BorderStyle 4).
	{
		id = 'dark_box', name = 'Caja oscura',
		text_color = '#FFFFFFFF', outline_color = '#C0000000', outline_size = '2.5',
		shadow_offset = '0', box_color = '#C0000000', bold = 'no', border_style = 'opaque-box',
	},
	-- Crunchyroll-like: white bold text, thick black outline, soft shadow.
	{
		id = 'thick_outline', name = 'Borde grueso',
		text_color = '#FFFFFFFF', outline_color = '#FF000000', outline_size = '4',
		shadow_offset = '1.5', shadow_color = '#80000000', bold = 'yes', border_style = 'outline-and-shadow',
	},
	-- Classic DVD yellow with black outline and shadow.
	{
		id = 'yellow', name = 'Amarillo clásico',
		text_color = '#FFFFE600', outline_color = '#FF000000', outline_size = '3',
		shadow_offset = '1.5', shadow_color = '#A0000000', bold = 'no', border_style = 'outline-and-shadow',
	},
}

-- `sub-scale`: font size factor (ASS too, with sub-ass-override=scale).
-- "Normal" has no value: it sets nothing and keeps mpv.conf's (or mpv's) value.
local SIZES = {
	{id = 'small', name = 'Pequeño', value = '0.85'},
	{id = 'normal', name = 'Normal'},
	{id = 'large', name = 'Grande', value = '1.2'},
	{id = 'xlarge', name = 'Muy grande', value = '1.4'},
}

-- `sub-pos`: 100 is mpv's default (bottom), lower numbers move subtitles up.
-- "Normal" has no value, like the size one.
local HEIGHTS = {
	{id = 'normal', name = 'Normal'},
	{id = 'raised', name = 'Un poco más arriba', value = '95'},
	{id = 'high', name = 'Más arriba', value = '90'},
}

local DEFAULTS = {style = 'original', size = 'normal', height = 'normal'}
local BORDER_STYLES = {['outline-and-shadow'] = true, ['opaque-box'] = true, ['background-box'] = true}

local function index_by_id(list)
	local t = {}
	for _, item in ipairs(list) do t[item.id] = item end
	return t
end
local style_by_id, size_by_id, height_by_id = index_by_id(STYLES), index_by_id(SIZES), index_by_id(HEIGHTS)

local function is_valid_id(id) return type(id) == 'string' and id:match('^[a-z0-9_-]+$') ~= nil end
local function is_number(v) return type(v) == 'string' and (v:match('^%d+$') ~= nil or v:match('^%d+%.%d+$') ~= nil) end

-- Checks a value from the tables above against its kind, with anchored patterns.
local VALIDATORS = {
	color = function(v) return v:match('^#%x%x%x%x%x%x%x%x$') ~= nil end,
	number = is_number,
	bool = function(v) return v == 'yes' or v == 'no' end,
	border_style = function(v) return BORDER_STYLES[v] == true end,
}
local function is_valid_value(kind, value)
	local check = VALIDATORS[kind]
	return type(value) == 'string' and check ~= nil and check(value)
end

-- Values read back from mpv (only used to restore "Original"/"Normal", never
-- written to the .conf): a short token such as `#FFFFFFFF`, `3.000000`, `no`, `opaque-box`.
local function is_safe_mpv_value(value)
	return type(value) == 'string' and #value <= 32 and value:match('^[%w#%.%-]+$') ~= nil
end

-- Canonical name of an option (aliases resolve to the real option), or nil if
-- this mpv doesn't know it.
local function canonical_name(prop)
	local name = mp.get_property('option-info/' .. prop .. '/name')
	if type(name) == 'string' and name:match('^sub%-[a-z-]+$') then return name end
	return nil
end

-- key -> mpv option for this mpv, and the list of distinct style options hikari manages.
local resolved, managed_props = {}, {}
local function resolve_props()
	resolved, managed_props = {}, {}
	local seen = {}
	for _, spec in ipairs(STYLE_KEYS) do
		for _, candidate in ipairs(spec.props) do
			local prop = canonical_name(candidate)
			if prop then
				resolved[spec.key] = prop
				if not seen[prop] then
					seen[prop] = true
					managed_props[#managed_props + 1] = prop
				end
				break
			end
		end
		if not resolved[spec.key] then msg.verbose('No mpv option for ' .. spec.key .. ', skipping it') end
	end
end

-- Ordered list of {prop, value} a style sets on this mpv, or nil if a value is
-- malformed or two keys of the style land on the same option.
local function style_settings(style)
	local list, used = {}, {}
	for _, spec in ipairs(STYLE_KEYS) do
		local value, prop = style[spec.key], resolved[spec.key]
		if value ~= nil then
			if not is_valid_value(spec.kind, value) then
				msg.error('Subtitle style "' .. tostring(style.id) .. '" has an invalid ' .. spec.key .. ': ' .. tostring(value))
				return nil
			end
			if prop then
				if used[prop] then
					msg.error('Subtitle style "' .. tostring(style.id) .. '" sets ' .. prop .. ' twice')
					return nil
				end
				used[prop] = true
				list[#list + 1] = {prop, value}
			end
		end
	end
	return list
end

-- What "Original" (style) and "Normal" (size, height) restore, per option. If
-- the saved choice at start-up is that one, the .conf set none of its options,
-- so the current values are mpv.conf's or mpv's own. Otherwise the current
-- values are the saved choice's, and mpv's defaults are used instead (until the
-- next start, when mpv.conf applies again).
local baseline = {}
local function capture_baseline(props, from_current)
	for _, prop in ipairs(props) do
		local value = from_current and mp.get_property(prop) or mp.get_property('option-info/' .. prop .. '/default-value')
		if is_safe_mpv_value(value) then
			baseline[prop] = value
		else
			msg.warn('Could not read the original value of ' .. prop .. ': ' .. tostring(value))
		end
	end
end

local function persist_content(style, size, height)
	local settings = style_settings(style)
	if not settings or not is_valid_id(script_name) or not is_valid_id(style.id) or not is_valid_id(size.id)
		or not is_valid_id(height.id) or (size.value ~= nil and not is_number(size.value))
		or (height.value ~= nil and not is_number(height.value)) then
		return nil
	end
	local lines = {'# Generated by hikari-subs.lua. Style: ' .. style.id .. ', size: ' .. size.id .. ', height: ' .. height.id}
	-- Quoted: mpv cuts unquoted config values at `#`.
	for _, setting in ipairs(settings) do lines[#lines + 1] = setting[1] .. '="' .. setting[2] .. '"' end
	if size.value then lines[#lines + 1] = 'sub-scale="' .. size.value .. '"' end
	if height.value then lines[#lines + 1] = 'sub-pos="' .. height.value .. '"' end
	lines[#lines + 1] = 'script-opts-append=' .. script_name .. '-style=' .. style.id
	lines[#lines + 1] = 'script-opts-append=' .. script_name .. '-size=' .. size.id
	lines[#lines + 1] = 'script-opts-append=' .. script_name .. '-height=' .. height.id
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
	msg.warn('Unknown subtitle ' .. what .. ' "' .. tostring(id) .. '", using ' .. DEFAULTS[what])
	return by_id[DEFAULTS[what]]
end

local opts = {style = DEFAULTS.style, size = DEFAULTS.size, height = DEFAULTS.height}
options.read_options(opts, script_name)
local active = {
	style = pick(style_by_id, opts.style, 'style'),
	size = pick(size_by_id, opts.size, 'size'),
	height = pick(height_by_id, opts.height, 'height'),
}

-- Sets every managed option: the style's value, or the baseline where the style
-- says nothing, so nothing from the previous style sticks.
local function apply_style(style)
	local settings = style_settings(style)
	if not settings then return false end
	local values = {}
	for _, setting in ipairs(settings) do values[setting[1]] = setting[2] end
	for _, prop in ipairs(managed_props) do
		local value = values[prop] or baseline[prop]
		if value then mp.commandv('set', prop, value) end
	end
	active.style = style
	return true
end

-- Sets `prop` to the entry's value, or back to the baseline for "Normal".
local function apply_value(prop, entry)
	if entry.value ~= nil and not is_number(entry.value) then return false end
	local value = entry.value or baseline[prop]
	if value then mp.commandv('set', prop, value) end
	return true
end

local function apply_size(size)
	if not apply_value('sub-scale', size) then return false end
	active.size = size
	return true
end

local function apply_height(height)
	if not apply_value('sub-pos', height) then return false end
	active.height = height
	return true
end

local function save()
	local content = persist_content(active.style, active.size, active.height)
	local path = mp.command_native({'expand-path', PERSIST_PATH})
	local ok, err = false, 'invalid subtitle settings'
	if content and path then ok, err = write_file_atomic(path, content) end
	if not ok then
		msg.warn('Could not save subtitle settings to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message('hikari: no se pudo guardar el estilo de subtítulos', 3)
	end
	return ok
end

local function menu_data()
	local items = {}
	local function group(title, list, current, message)
		if #items > 0 then items[#items].separator = true end
		items[#items + 1] = {title = title, selectable = false, muted = true, italic = true}
		for _, entry in ipairs(list) do
			local is_active = entry == current
			items[#items + 1] = {
				title = entry.name,
				hint = is_active and 'activa' or nil,
				active = is_active,
				value = {'script-message-to', script_name, message, entry.id},
			}
		end
	end
	group('Estilo', STYLES, active.style, 'select-style')
	group('Tamaño', SIZES, active.size, 'select-size')
	group('Altura', HEIGHTS, active.height, 'select-height')
	items[#items].separator = true
	items[#items + 1] = {
		title = 'Los estilos solo cambian SRT; los ASS conservan el suyo',
		selectable = false, muted = true, italic = true, align = 'center',
	}
	-- keep_open: picking an item doesn't close the menu, so several things can be
	-- adjusted in a row; each pick sends update-menu to move the marks.
	return {type = MENU_TYPE, title = 'Subtítulos', keep_open = true, items = items}
end

local function send_menu(message)
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the subtitle menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

local function open_menu() send_menu('open-menu') end

-- Handlers for menu selections. Ids come from outside, so they must match a table.
local function selector(by_id, what, apply)
	return function(id)
		local entry = by_id[id]
		if not entry then
			msg.warn('Ignoring unknown subtitle ' .. what .. ': ' .. tostring(id))
			return
		end
		if apply(entry) then
			save()
			-- uosc only updates a menu of this type if it is still open.
			send_menu('update-menu')
		end
	end
end
local select_style = selector(style_by_id, 'style', apply_style)
local select_size = selector(size_by_id, 'size', apply_size)
local select_height = selector(height_by_id, 'height', apply_height)

mp.register_script_message('select-style', select_style)
mp.register_script_message('select-size', select_size)
mp.register_script_message('select-height', select_height)
mp.add_key_binding(nil, 'open-menu', open_menu)

-- Start-up: the included .conf already set everything, but applying again from
-- the tables means edits to a style take effect without picking it again.
-- Choices that set nothing (Original, Normal) are not applied, so mpv.conf's
-- values stay untouched.
resolve_props()
capture_baseline(managed_props, active.style.id == DEFAULTS.style)
capture_baseline({'sub-scale'}, active.size.id == DEFAULTS.size)
capture_baseline({'sub-pos'}, active.height.id == DEFAULTS.height)
if active.style.id ~= DEFAULTS.style then apply_style(active.style) end
if active.size.id ~= DEFAULTS.size then apply_size(active.size) end
if active.height.id ~= DEFAULTS.height then apply_height(active.height) end

if HIKARI_SUBS_TEST then
	return {
		STYLES = STYLES, SIZES = SIZES, HEIGHTS = HEIGHTS, STYLE_KEYS = STYLE_KEYS,
		style_by_id = style_by_id, size_by_id = size_by_id, height_by_id = height_by_id,
		style_settings = style_settings, persist_content = persist_content,
		write_file_atomic = write_file_atomic, apply_style = apply_style,
		select_style = select_style, select_size = select_size, select_height = select_height,
		menu_data = menu_data, open_menu = open_menu, is_valid_id = is_valid_id,
		is_valid_value = is_valid_value, is_safe_mpv_value = is_safe_mpv_value,
		get_active = function() return active end,
		get_baseline = function() return baseline end,
		get_managed_props = function() return managed_props end,
	}
end
