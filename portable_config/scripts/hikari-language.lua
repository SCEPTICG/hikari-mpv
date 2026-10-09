-- hikari-language: the language of hikari's texts, and of uosc's.
--
-- Opens a uosc menu with the 13 languages of uosc 5.13, each by its own name.
-- Picking one switches every hikari text at once (open menus are refreshed,
-- the skip button is redrawn, the tooltips of hikari's buttons change), saves
-- the choice to `~~/hikari-language.conf`, which mpv.conf includes on the next
-- start, and says (in the new language) that mpv must be restarted for uosc's
-- own menus.
--
-- mpv turns this file name into the script name `hikari_language`, so:
--   input.conf:  Alt+l script-binding hikari_language/open-menu
--   options:     script-opts=hikari-language=<code>   (shared by every hikari
--                script, see script-modules/hikari-i18n.lua)
--
-- Decisions:
-- - The saved file sets two script options:
--     script-opts-append=hikari-language=es
--     script-opts-append=uosc-languages=es,en
--   The first one is what every hikari script reads. The second one is uosc's
--   own `languages` option (default `slang,en`, src/uosc/lib/intl.lua), so uosc
--   speaks the same language as hikari instead of following the subtitle
--   language. uosc reads its translations only once, when it starts: a switch
--   at run time cannot reach its texts, hence the "restart mpv" notice, shown
--   only when the language differs from the one uosc started with.
-- - zh-HK: uosc 5.13 looks for `intl/<code lower-cased>.json`, but the file is
--   `intl/zh-HK.json`, so on a case-sensitive file system (Linux) `zh-HK`
--   alone finds nothing. uosc also takes paths ending in `.json`, so the value
--   is `~~/scripts/uosc/intl/zh-HK.json,zh-HK,en`: uosc goes through the list
--   from the end, `en` first, then `zh-HK` (enough on Windows and macOS), then
--   the file by its real name; a path that does not exist is skipped quietly.
-- - Tooltips of hikari's buttons. uosc 5.13 passes the tooltips of its own
--   buttons through its t(), but for a `command:<icon>:<command>?<tooltip>`
--   button it uses the text after `?` as it is (elements/Controls.lua). A
--   translation file in `languages` therefore cannot reach them. Instead, this
--   script rewrites `controls` at run time through the `uosc-controls` script
--   option, as hikari-palettes does with `uosc-color`: it takes the controls
--   in effect (`uosc-controls` from script-opts when set, otherwise the
--   `controls=` line of script-opts/uosc.conf, read the way mp.options reads
--   it), gives every button whose command opens one of hikari's menus the
--   tooltip in the current language, and leaves everything else as written
--   (order, conditions, your own buttons). uosc rebuilds its controls on any
--   option change (Controls:on_options), so the new tooltips show at once.
--   Nothing is set when no tooltip changes (English with the shipped uosc.conf).
-- - No entry in uosc's main menu: uosc builds that menu from the `#!`
--   comments of input.conf, but a single `#!` line replaces uosc's whole
--   default menu (lib/menus.lua, get_menu_items), and its title would be fixed
--   text. Alt+l is listed in uosc's "Key bindings" menu like any other key.

local msg = require('mp.msg')
local utils = require('mp.utils')

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

local PERSIST_PATH = '~~/hikari-language.conf'
local MENU_TYPE = 'hikari-language'
-- Where the installers put uosc (a folder script), for the zh-HK file.
local UOSC_INTL_DIR = '~~/scripts/uosc/intl/'
-- Bounds on what is read from uosc.conf and on the controls string.
local MAX_CONF_BYTES = 256 * 1024
local MAX_CONTROLS = 8192

-- hikari's buttons in uosc's `controls`, by the command they run, and the key
-- of their tooltip text.
local BUTTONS = {
	['script-binding hikari_subs/open-menu'] = 'tooltip_subs',
	['script-binding hikari_upscale/open-menu'] = 'tooltip_upscale',
	['script-binding hikari_speed/open-menu'] = 'tooltip_speed',
	['script-binding hikari_palettes/open-menu'] = 'tooltip_palettes',
	['script-binding hikari_update/open-menu'] = 'tooltip_update',
}

-- The value of uosc's `languages` option for a language code.
local function uosc_languages(code)
	if code == 'en' then return 'en' end
	if code == 'zh-HK' then return UOSC_INTL_DIR .. 'zh-HK.json,zh-HK,en' end
	return code .. ',en'
end

-- The hikari language code uosc started with, from `uosc-languages`: its
-- first entry (a code, or a path whose file name is the code). nil when the
-- option is not set (uosc then follows the subtitle language).
local function uosc_language_of(value)
	if type(value) ~= 'string' or value == '' then return nil end
	local first = value:match('^([^,]*)')
	local from_path = first:match('([%w%-]+)%.json$')
	return i18n.normalize(from_path or first)
end

-- Content of the saved file, or nil for an unknown code. The installers write
-- the same bytes for the language they detect (their tests compare them).
local function persist_content(code)
	if not i18n.is_language(code) then return nil end
	return '# Generated by hikari-language.lua. Language: ' .. code .. '\n'
		.. 'script-opts-append=' .. i18n.OPTION .. '=' .. code .. '\n'
		.. 'script-opts-append=uosc-languages=' .. uosc_languages(code) .. '\n'
end

-- Writes through a temporary file and a rename so a crash never leaves half a file.
local function write_file_atomic(path, content)
	local tmp = path .. '.tmp'
	-- A leftover .tmp (or a link planted there) goes first, so io.open creates
	-- a new file instead of writing through whatever was there.
	os.remove(tmp)
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

-- uosc's controls ------------------------------------------------------------

-- Splits a `controls` value into items as uosc 5.13 does (Controls:init_options):
-- `,` ends an item except inside the `<...>` conditions at its start. Each item
-- keeps its conditions as written (`prefix`) apart from the rest (`config`).
-- `trailing` is true when the value ends with a `,`.
local function split_controls(text)
	local items, item, in_disposition = {}, nil, false
	for c in text:gmatch('.') do
		if not item then item = {prefix = {}, config = {}} end
		if c == '<' and #item.config == 0 then
			in_disposition = true
			item.prefix[#item.prefix + 1] = c
		elseif c == '>' and #item.config == 0 then
			in_disposition = false
			item.prefix[#item.prefix + 1] = c
		elseif c == ',' and not in_disposition then
			items[#items + 1] = item
			item = nil
		elseif in_disposition then
			item.prefix[#item.prefix + 1] = c
		else
			item.config[#item.config + 1] = c
		end
	end
	local trailing = item == nil and #items > 0
	if item then items[#items + 1] = item end
	for i, it in ipairs(items) do
		items[i] = {prefix = table.concat(it.prefix), config = table.concat(it.config)}
	end
	return items, trailing
end

-- The tooltip text for a button key, without the characters uosc would read
-- as separators.
local function tooltip_text(key, lang)
	return (i18n.t(key, nil, lang):gsub('[,?]', ''))
end

-- One item's config with hikari's tooltip in `lang`, or as it was when it is
-- not one of hikari's buttons. As in uosc: the tooltip is what follows the
-- first `?`, and a `#badge` may follow the command.
local function localize_config(config, lang)
	local q = config:find('?', 1, true)
	local head = q and config:sub(1, q - 1) or config
	local command = head:match('^%s*command%s*:%s*[^:]-%s*:%s*(.-)%s*$')
	if not command then return config end
	local key = BUTTONS[(command:gsub('%s*#.*$', ''))]
	if not key then return config end
	return head:gsub('%s+$', '') .. '?' .. tooltip_text(key, lang)
end

-- `controls` with the tooltips of hikari's buttons in `lang`.
local function localize_controls(controls, lang)
	local items, trailing = split_controls(controls)
	local parts = {}
	for i, item in ipairs(items) do parts[i] = item.prefix .. localize_config(item.config, lang) end
	return table.concat(parts, ',') .. (trailing and ',' or '')
end

-- The `controls=` value of script-opts/uosc.conf (the last one wins), read as
-- mp.options reads it: lines starting with `#` are comments, the key is
-- everything before the first `=`. nil when there is none.
local function conf_controls()
	local path = mp.find_config_file('script-opts/uosc.conf')
	if not path then return nil end
	local file = io.open(path, 'rb')
	if not file then return nil end
	local content = file:read(MAX_CONF_BYTES) or ''
	file:close()
	local value
	for line in (content .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', '')
		if line:sub(1, 1) ~= '#' then
			local eq = line:find('=', 1, true)
			if eq and line:sub(1, eq - 1) == 'controls' then value = line:sub(eq + 1) end
		end
	end
	return value
end

-- The controls uosc uses now: script-opts first, as in mp.options.
local function current_controls()
	local script_opts = mp.get_property_native('options/script-opts')
	local value = type(script_opts) == 'table' and script_opts['uosc-controls'] or nil
	if type(value) ~= 'string' then value = conf_controls() end
	if type(value) ~= 'string' or value == '' or #value > MAX_CONTROLS then return nil end
	return value
end

-- Gives hikari's buttons their tooltips in the current language. Returns true
-- when it changed the controls.
local function apply_tooltips()
	local controls = current_controls()
	if not controls then return false end
	local localized = localize_controls(controls, i18n.language())
	if localized == controls then return false end
	mp.commandv('change-list', 'script-opts', 'append', 'uosc-controls=' .. localized)
	return true
end

-- Menu -------------------------------------------------------------------------

local function menu_data()
	local lang = i18n.language()
	local items = {}
	for _, language in ipairs(i18n.LANGUAGES) do
		local is_current = language.code == lang
		items[#items + 1] = {
			title = language.name,
			hint = is_current and i18n.t('current') or nil,
			active = is_current,
			value = {'script-message-to', script_name, 'select-language', language.code},
		}
	end
	-- keep_open: the menu stays and is redrawn in the new language.
	return {type = MENU_TYPE, title = i18n.t('language_title'), keep_open = true, items = items}
end

local function send_menu(message)
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the language menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

local function open_menu() send_menu('open-menu') end

-- The language uosc started with (it does not change until mpv restarts).
local uosc_language = (function()
	local script_opts = mp.get_property_native('options/script-opts')
	return uosc_language_of(type(script_opts) == 'table' and script_opts['uosc-languages'] or nil)
end)()

local function save(code)
	local content = persist_content(code)
	local path = mp.command_native({'expand-path', PERSIST_PATH})
	local ok, err = false, 'invalid language'
	if content and type(path) == 'string' and path ~= '' then ok, err = write_file_atomic(path, content) end
	if not ok then
		msg.warn('Could not save the language to ' .. tostring(path) .. ': ' .. tostring(err))
		mp.osd_message(i18n.t('language_save_failed', nil, code), 3)
	end
	return ok
end

-- Handler for menu selections. The code comes from outside, so it must be one
-- of the languages. Every script (this one too) follows through the option.
local function select_language(code)
	if not i18n.is_language(code) then
		msg.warn('Ignoring unknown language: ' .. (tostring(code):sub(1, 64):gsub('%c', '?')))
		return
	end
	if code ~= i18n.language() then
		mp.commandv('change-list', 'script-opts', 'append', i18n.OPTION .. '=' .. code)
	end
	if save(code) and code ~= uosc_language then
		mp.osd_message(i18n.t('language_restart', nil, code), 4)
	end
end

mp.register_script_message('select-language', select_language)
mp.add_key_binding(nil, 'open-menu', open_menu)
i18n.on_change(function()
	apply_tooltips()
	if mp.get_property_native('user-data/uosc/menu/type') == MENU_TYPE then send_menu('update-menu') end
end)
apply_tooltips()

if HIKARI_LANGUAGE_TEST then
	return {
		BUTTONS = BUTTONS, i18n = i18n, uosc_languages = uosc_languages, uosc_language_of = uosc_language_of,
		persist_content = persist_content, write_file_atomic = write_file_atomic,
		split_controls = split_controls, localize_config = localize_config, localize_controls = localize_controls,
		conf_controls = conf_controls, current_controls = current_controls, apply_tooltips = apply_tooltips,
		menu_data = menu_data, open_menu = open_menu, select_language = select_language,
		get_uosc_language = function() return uosc_language end,
	}
end
