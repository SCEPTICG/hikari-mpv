-- hikari-media-language: audio and subtitles in the language of hikari.
--
-- The language picked in hikari's language menu (Alt+l, or the system's when
-- none is picked) also decides which audio and subtitle tracks mpv selects on
-- its own, with this recipe for anime:
--   alang=<language>,ja                 the dub in your language, else Japanese
--   slang=<language>                    subtitles in your language...
--   subs-with-matching-audio=forced     ...except when the audio already is:
--                                       then only forced subtitles (signs
--                                       and songs), not the dialogue
-- <language> is a list of codes per language (MEDIA_LANGUAGES in
-- script-modules/hikari-i18n.lua, where the matching rules of mpv are
-- explained). There is no option to turn it on or off: your own lines are.
--
-- mpv turns this file name into the script name `hikari_media_language`. It
-- has no key binding and no menu.
--
-- Decisions:
-- - Your settings win. `alang` is decided on its own: when you set it,
--   hikari leaves it alone and still sets the subtitles. The subtitles go
--   together, all or nothing: `subs-with-matching-audio` only makes sense
--   with hikari's `slang`, so when you set `slang` hikari leaves both alone
--   (even if you did not set `subs-with-matching-audio`), and when you set
--   only `subs-with-matching-audio`, hikari still sets `slang`. An option
--   counts as yours when, at the moment this script starts:
--     1. mpv says it came from the command line
--        (option-info/<name>/set-from-commandline), or
--     2. its value is not mpv's default (option-info/<name>/default-value).
--        This catches mpv.conf, the files it includes, /etc/mpv/mpv.conf,
--        profiles applied at start (`profile=`), mpv.net's settings and any
--        script that ran earlier: whatever set it, it was not hikari, or
--     3. ~~/mpv.conf (that file only, as expand-path gives it: never
--        /etc/mpv/mpv.conf) has a line for it outside the hikari block and
--        outside any [profile] section: `alang=...`,
--        `--slang = ... # comment`, `alang-append=...`,
--        `no-subs-with-matching-audio`... This is for
--        lines that write mpv's default value (`subs-with-matching-audio=yes`,
--        `slang=`), which 2 cannot tell apart from no line at all.
--   Why not option-info alone: mpv 0.40 and 0.41 only mark options from the
--   command line there (M_SETOPT_FROM_CMDLINE); mpv.conf sets another flag
--   that is not exposed, and set-locally only means "per file". The one case
--   left out is a line that writes the default value in a file other than
--   ~~/mpv.conf (an include, /etc/mpv/mpv.conf) or in a profile applied at
--   start: there hikari's value is used. Profiles that apply later (auto
--   profiles) set their values over hikari's while they are active, as they
--   would over any other value. To hand an option to hikari, delete its line.
-- - When: once when the script starts, which mpv waits for before it opens
--   the first file (it waits until every script has finished loading), so the
--   first file already gets the recipe. Nothing is written to any file: the
--   options only live while mpv runs, and uninstalling hikari leaves nothing
--   behind. And again after every language switch (Alt+l).
-- - Never over someone else's change: before setting an option again, hikari
--   checks that it still holds the value hikari set. If it does not (`set
--   alang ...` in the console, another script, an auto profile that is
--   active), that option is skipped this time.
-- - Switching language with a file open picks its tracks again with the new
--   languages, but only the ones mpv chose on its own: when you picked the
--   audio or subtitle track yourself (menu, keys, --aid/--sid, a resumed
--   position that saved them), mpv's `aid`/`sid` option holds that track
--   instead of `auto`, and hikari leaves it. Audio goes first, since the
--   choice of subtitles depends on it. mpv only picks again when `aid`/`sid`
--   changes, and setting `auto` over `auto` changes nothing, so hikari sets
--   the track already playing first (no switch at all, mpv returns at once
--   for the same track) and then `auto`. Skipped with `lavfi-complex`, where
--   tracks are wired into filters. The next files use the new languages in
--   any case.

local msg = require('mp.msg')
local utils = require('mp.utils')

-- Texts and languages of hikari: ~~/script-modules/hikari-i18n.lua. Single-file
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

-- The options hikari may set, in the order it sets them.
local OPTIONS = {'alang', 'slang', 'subs-with-matching-audio'}
-- How mpv.conf may name each of them: the option itself, the actions of a
-- list option (`alang-append`...), and `no-` for the choice that has `no`.
local CONF_NAMES = {
	['subs-with-matching-audio'] = 'subs-with-matching-audio',
	['no-subs-with-matching-audio'] = 'subs-with-matching-audio',
}
for _, name in ipairs({'alang', 'slang'}) do
	CONF_NAMES[name] = name
	for _, action in ipairs({'set', 'add', 'append', 'pre', 'clr', 'del', 'remove', 'toggle'}) do
		CONF_NAMES[name .. '-' .. action] = name
	end
end
-- The hikari block of mpv.conf, as the installers write it.
local BLOCK_BEGIN = '# >>> hikari'
local BLOCK_END = '# <<< hikari'
-- Bound on what is read from mpv.conf (mpv itself reads up to 1 GB).
local MAX_CONF_BYTES = 1024 * 1024

-- The recipe for a language of hikari: option name -> value.
local function recipe(lang)
	local codes = i18n.MEDIA_LANGUAGES[lang] or i18n.MEDIA_LANGUAGES[i18n.DEFAULT]
	local alang = {}
	for _, code in ipairs(codes) do alang[#alang + 1] = code end
	for _, code in ipairs(i18n.ORIGINAL_AUDIO) do alang[#alang + 1] = code end
	local slang = {}
	for _, code in ipairs(codes) do slang[#slang + 1] = code end
	return {alang = alang, slang = slang, ['subs-with-matching-audio'] = 'forced'}
end

-- One form for any value of the three options, to compare them: a string
-- list as written in mpv.conf, and `subs-with-matching-audio`, which mpv
-- gives as a flag for yes/no but as a string for `forced`, as its name.
local function value_text(value)
	if type(value) == 'table' then return table.concat(value, ',') end
	if value == true then return 'yes' end
	if value == false then return 'no' end
	return tostring(value)
end

local function same_value(a, b)
	if type(a) == 'table' and type(b) == 'table' and #a ~= #b then return false end
	return value_text(a) == value_text(b)
end

-- mpv.conf -----------------------------------------------------------------

-- The options of OPTIONS that `text` (an mpv.conf) sets outside the hikari
-- block and outside any [profile] section, as a set. The lines are read the
-- way mpv reads them (options/parse_configfile.c): blanks before the name, an
-- optional `--`, the name made of letters, digits, `_` and `-`, then `=`, a
-- blank or the end; `#` starts a comment; `[name]` starts a profile, and
-- `[default]` goes back to the top level.
local function conf_options(text)
	local found = {}
	if type(text) ~= 'string' then return found end
	text = text:gsub('^\239\187\191', '')
	local top, in_block = true, false
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', ''):gsub('^%s+', '')
		if line:sub(1, #BLOCK_BEGIN) == BLOCK_BEGIN then
			in_block = true
		elseif line:sub(1, #BLOCK_END) == BLOCK_END then
			in_block = false
		elseif line ~= '' and line:sub(1, 1) ~= '#' then
			local section = line:match('^%[([^%]]*)%]')
			if section then
				top = section == 'default'
			elseif top and not in_block then
				local name = line:gsub('^%-%-', ''):match('^([%w_%-]+)')
				local option = name and CONF_NAMES[name]
				if option then found[option] = true end
			end
		end
	end
	return found
end

-- The options ~~/mpv.conf sets (see conf_options); an empty set when there is
-- no such file or it cannot be read. Only that file: not /etc/mpv/mpv.conf,
-- which mp.find_config_file would fall back to (see the header).
local function user_conf_options()
	local path = mp.command_native({'expand-path', '~~/mpv.conf'})
	if type(path) ~= 'string' or path == '' then return {} end
	local info = utils.file_info(path)
	if not info or not info.is_file then return {} end
	local file = io.open(path, 'rb')
	if not file then return {} end
	local text = file:read(MAX_CONF_BYTES)
	file:close()
	return conf_options(text)
end

-- Whether the user set `name` (see the header), and why, for the log.
-- Unknown answers count as "yes": better to leave an option alone than to
-- overwrite a choice.
local function set_by_user(name, in_conf)
	if mp.get_property_native('option-info/' .. name .. '/set-from-commandline') ~= false then
		return true, 'set on the command line, or unknown to this mpv'
	end
	local default = mp.get_property_native('option-info/' .. name .. '/default-value')
	local current = mp.get_property_native(name)
	if default == nil or current == nil then return true, 'its value cannot be read' end
	if not same_value(current, default) then
		return true, 'already set (' .. (value_text(current):sub(1, 80):gsub('%c', '?')) .. ')'
	end
	if in_conf[name] then return true, 'set in mpv.conf' end
	return false
end

-- State ----------------------------------------------------------------------

-- name -> true for the options hikari takes care of (decided once, at start).
local managed = {}
-- name -> the value hikari last set (or found already right).
local applied = {}
-- A file is loaded and its tracks were selected.
local playing = false

local function set_option(name, value)
	local ok, err
	if type(value) == 'table' then
		ok, err = mp.set_property_native(name, value)
	else
		ok, err = mp.set_property(name, value)
	end
	if not ok then msg.warn('Could not set ' .. name .. ': ' .. tostring(err)) end
	return ok
end

-- Sets the recipe for `lang` on the options hikari takes care of. Returns a
-- set of the options whose value changed.
local function apply(lang)
	local want = recipe(lang)
	local changed = {}
	for _, name in ipairs(OPTIONS) do
		if managed[name] then
			local current = mp.get_property_native(name)
			if applied[name] ~= nil and not same_value(current, applied[name]) then
				msg.verbose(name .. ' was changed by someone else: left as it is')
			elseif same_value(current, want[name]) then
				applied[name] = want[name]
			elseif set_option(name, want[name]) then
				applied[name] = want[name]
				changed[name] = true
			end
		end
	end
	return changed
end

-- Lets mpv pick the `property` track (aid, sid) again, when mpv picked it on
-- its own. Returns true when it asked mpv to.
local function reselect(property)
	if mp.get_property_native('options/' .. property) ~= 'auto' then return false end
	local current = mp.get_property(property)
	if not current or current == '' then return false end
	mp.set_property(property, current)
	mp.set_property(property, 'auto')
	return true
end

-- After a language switch: the tracks of the file playing, see the header.
local function reselect_tracks(changed)
	if not playing or not next(changed) then return end
	local complex = mp.get_property_native('lavfi-complex')
	if type(complex) == 'string' and complex ~= '' then return end
	if changed.alang then reselect('aid') end
	reselect('sid')
end

local function on_language(lang)
	reselect_tracks(apply(lang))
end

-- Start ------------------------------------------------------------------------

local in_conf = user_conf_options()
for _, name in ipairs(OPTIONS) do
	local mine, why = set_by_user(name, in_conf)
	-- All or nothing for the subtitles: see the header.
	if not mine and name == 'subs-with-matching-audio' and not managed.slang then
		mine, why = true, 'slang is yours, so the subtitles are'
	end
	managed[name] = not mine
	if mine then msg.verbose(name .. ' left to you: ' .. why) end
end
apply(i18n.language())

mp.register_event('start-file', function() playing = false end)
mp.register_event('file-loaded', function() playing = true end)
mp.register_event('end-file', function() playing = false end)
i18n.on_change(on_language)

if HIKARI_MEDIA_LANGUAGE_TEST then
	return {
		i18n = i18n, OPTIONS = OPTIONS, recipe = recipe, value_text = value_text, same_value = same_value,
		conf_options = conf_options, user_conf_options = user_conf_options, set_by_user = set_by_user,
		apply = apply, reselect = reselect, reselect_tracks = reselect_tracks,
		managed = managed, applied = applied,
		is_playing = function() return playing end,
	}
end
