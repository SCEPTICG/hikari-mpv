-- hikari-resume: continue watching where you left off, for files.
--
-- While a file plays, its position is remembered. Opening it again pauses mpv
-- and asks, in a uosc menu, whether to continue from there (the default) or
-- start from the beginning. The `open-menu` binding, and a button in uosc's
-- controls bar (uosc.conf shows it while user-data/hikari_resume/available is
-- true, mpv 0.36+), list the files left half-watched, newest first; picking
-- one opens it, and the question comes up. Texts follow hikari's language
-- (hikari-i18n).
--
-- mpv turns this file name into the script name `hikari_resume`, so:
--   input.conf:  <key> script-binding hikari_resume/open-menu
--
-- Decisions:
-- - Files only, never streams. Anything with a scheme (`https://`, `ytdl://`,
--   `edl://`, `memory://`, any `name://`) is left alone: nothing saved,
--   nothing asked. Seanime and players like it keep their own position (two
--   of them jumping would fight), and their URLs carry tokens that must never
--   be written down. A `file://` URL is a file (turned into its path). A
--   scheme has two characters at least, so a drive letter (`C:\`) is not one.
-- - Paths are compared once absolute (relative ones against
--   `working-directory`), with separators normalised and `.` and `..`
--   resolved; on Windows without case (ASCII letters). mpv's `normalize-path`
--   command does the same, but only from mpv 0.38.
-- - What is saved: under MIN_POSITION seconds, nothing (an entry already there
--   stays as it was). Watched, so removed from the list (next time it starts
--   from zero without asking): at WATCHED_SHARE of the duration, or once the
--   ending has started. The ending is the last chapter that
--   script-modules/hikari-chapters.lua (shared with hikari-skip.lua) calls an
--   ending (ED, Ending, Credits, エンディング...): the last one, so a file with
--   several episodes is not over at the first ending, and only one that
--   starts in the second half of the file (ENDING_SHARE), so "Opening
--   Credits" at 0:00 is no ending. The user's extra_endings of
--   hikari-skip.conf are not read. No known duration: nothing is saved.
-- - When: every SAVE_INTERVAL seconds if mpv is not paused and the position
--   moved by MOVED seconds or more since the last save, and at end-file
--   (closing, next file of the playlist, quit) and shutdown, with the last
--   time-pos, duration and chapters seen (mpv may have cleared them by then).
--   After Clear history the file playing is only saved again when it ends,
--   not by the timer, so it does not come straight back into the list.
--   mpv.conf and save-position-on-quit are not touched.
-- - The question: only with ask=yes, when mpv is still at the start
--   (time-pos under START_TOLERANCE at file-loaded: with resume-playback or
--   --start mpv has already moved) and the saved position is more than
--   END_MARGIN seconds before the end of the file as it is now (otherwise it
--   just starts from zero). mpv is paused only if it was playing, and set
--   back once answered. Closing the menu without choosing (Esc, a click
--   outside, another menu) is "from the beginning". uosc may send the answer
--   and close the menu in either order: closing only puts the pause back, and
--   a "continue" that arrives after it still seeks (same file only). When the
--   menu never shows (no uosc), the pause goes back after PROMPT_TIMEOUT.
--   With ask=no it seeks without asking.
-- - The list: ~~/hikari-resume.json, {"version":1,"entries":[...]}, each entry
--   {path, title, position, duration, updated (unix time)}, newest first, at
--   most history_size. One list per computer, never synchronised; this script
--   makes no network connection at all. Read with a size cap and every field
--   checked; a path must be an absolute file path (no URL), as it goes to
--   loadfile. Only the newest history_size entries are used, however many
--   the file holds. A broken or unreadable file is an empty list and a warning,
--   never an error, and it is only written again when there is something to
--   save. Before each write the file is read again and only the entry of the
--   file playing changes, so two mpv windows keep each other's entries.
-- - Writing: a temporary file of this mpv next to the list (named after the
--   pid, as script-modules/hikari-aniskip.lua does) renamed over it, so a link
--   or junction with the list's name is replaced, never written through. On
--   Windows rename() does not replace: the old file is moved aside first and
--   put back if the second rename fails. Temporary files over a day old (an
--   mpv that died half-way) go on the first write of each mpv.
-- - Rows: the title is the file name without folder or extension (the
--   metadata's media-title is too often empty or junk), then `12:34 / 24:00 ·
--   date` (today, yesterday or `12 oct`, the year only when it is not this
--   year's). A file that cannot be found now (NAS not mounted, deleted) is a
--   grey row "Not available" that stays in the list. Asking for a file on a
--   share that is off can take tens of seconds on Windows, and mpv waits: so,
--   once per opening of the menu, each root is checked first (\\host\share,
--   the drive, /Volumes/<x>, /mnt/<x>, /media/<user>/<x>,
--   /run/media/<user>/<x>, otherwise the file's folder), and only when it is
--   there are its files checked, each once.
--
-- Options (script-opts/hikari-resume.conf): see that file.

local msg = require('mp.msg')
local options = require('mp.options')
local utils = require('mp.utils')

-- hikari's modules in ~~/script-modules: the texts (hikari-i18n.lua) and the
-- chapter kinds (hikari-chapters.lua). Single-file scripts get no mpv folder
-- in package.path, so the folder is added for each require and taken out
-- again (see the header of hikari-i18n.lua).
local function load_module(name)
	local dir = mp.command_native({'expand-path', '~~/script-modules'})
	if type(dir) ~= 'string' or dir == '' or dir:find('[;?]') then
		error('hikari: unusable script-modules folder: ' .. tostring(dir))
	end
	local saved = package.path
	package.path = dir .. '/?.lua;' .. saved
	local ok, module = pcall(require, name)
	package.path = saved
	if not ok then error('hikari: cannot load script-modules/' .. name .. '.lua (reinstall hikari): ' .. tostring(module)) end
	return module
end
local i18n = load_module('hikari-i18n')
local chapter_kinds = load_module('hikari-chapters')

local script_name = mp.get_script_name()
local OPTIONS_ID = 'hikari-resume'
local LIST_PATH = '~~/hikari-resume.json'
local AVAILABLE_PROP = 'user-data/hikari_resume/available'
local MENU_TYPE = 'hikari-resume'
local PROMPT_TYPE = 'hikari-resume-prompt'

local SAVE_INTERVAL = 10
local MOVED = 1
local MIN_POSITION = 30
local WATCHED_SHARE = 0.95
-- An ending chapter only counts when it starts at this share of the file or later.
local ENDING_SHARE = 0.5
local END_MARGIN = 10
local START_TOLERANCE = 1
local PROMPT_TIMEOUT = 3
local MAX_HISTORY = 100
-- Bounds on what is read: the whole list, a path, a title.
local MAX_LIST_BYTES = 1024 * 1024
local MAX_PATH = 4096
local MAX_TITLE = 512
local STALE_TMP_AGE = 24 * 3600

local opts = {
	enabled = true,
	ask = true,
	history_size = 30,
}
options.read_options(opts, OPTIONS_ID)
do
	local size = tonumber(opts.history_size)
	if not size or size ~= size then size = 30 end
	opts.history_size = math.floor(math.min(MAX_HISTORY, math.max(1, size)))
end

-- Replaceable in tests.
local clock = {now = os.time}

local function finite(value)
	return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

-- 'windows' or not, from mpv when it says (as hikari-update.lua).
local function is_windows()
	local p = mp.get_property_native('platform')
	if type(p) == 'string' and p ~= '' then return p == 'windows' end
	return package.config:sub(1, 1) == '\\'
end

-- Paths -------------------------------------------------------------------------

local function percent_decode(text)
	return (text:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))
end

-- The path of a file:// URL, or nil. A host other than localhost is a network
-- share (\\host\share on Windows; elsewhere there is no such path).
local function from_file_url(url, windows)
	local host, path = url:sub(8):match('^([^/]*)(/.*)$')
	if not host then return nil end
	host, path = percent_decode(host), percent_decode(path)
	if host ~= '' and host:lower() ~= 'localhost' then
		if not windows or host:find('[/\\]') then return nil end
		return '//' .. host .. path
	end
	if windows and path:match('^/%a:') then path = path:sub(2) end
	return path
end

-- `path` absolute, with `.` and `..` resolved and one kind of separator; nil
-- when it is not an absolute file path. Windows: `C:\...` or `\\server\share\...`.
local function normalize(path, windows)
	local sep = windows and '\\' or '/'
	local root, rest
	if windows then
		path = path:gsub('/', '\\')
		if path:sub(1, 2) == '\\\\' then
			local host, share, tail = path:match('^\\\\([^\\]+)\\([^\\]+)(.*)$')
			if not host then return nil end
			root, rest = '\\\\' .. host .. '\\' .. share, tail
		else
			local drive, tail = path:match('^(%a:)(\\.*)$')
			if not drive then return nil end
			root, rest = drive, tail
		end
	else
		if path:sub(1, 1) ~= '/' then return nil end
		root, rest = '', path
	end
	local parts = {}
	for part in rest:gmatch(windows and '[^\\]+' or '[^/]+') do
		if part == '..' then
			parts[#parts] = nil
		elseif part ~= '.' then
			parts[#parts + 1] = part
		end
	end
	if #parts == 0 then return nil end
	return root .. sep .. table.concat(parts, sep)
end

-- The absolute path of what mpv plays when it is a file, nil for anything
-- else (a URL, stdin, an empty path). `wd` resolves a relative path; without
-- it a relative path is nil.
local function file_path(path, wd, windows)
	if type(path) ~= 'string' or path == '' or path == '-' or #path > MAX_PATH or path:find('%z') then return nil end
	if path:sub(1, 7):lower() == 'file://' then
		path = from_file_url(path, windows)
		if not path or path == '' or path:find('%z') then return nil end
	elseif path:match('^%a[%w+.%-]+://') then
		return nil
	end
	local absolute
	if windows then
		absolute = path:match('^%a:[\\/]') or path:match('^[\\/][\\/]')
		if not absolute and path:match('^%a:') then return nil end -- C:file, relative to a drive
		if not absolute and path:match('^[\\/]') then
			-- \file: the root of the working directory's drive.
			local drive = type(wd) == 'string' and wd:match('^(%a:)')
			if not drive then return nil end
			path, absolute = drive .. path, true
		end
	else
		absolute = path:sub(1, 1) == '/'
	end
	if not absolute then
		if type(wd) ~= 'string' or wd == '' then return nil end
		path = wd .. (windows and '\\' or '/') .. path
	end
	return normalize(path, windows)
end

-- What two paths are compared by.
local function path_key(path, windows)
	return windows and path:lower() or path
end

-- The file name without folder or extension.
local function title_of(path)
	local name = path:match('[^/\\]+$') or path
	return name:match('^(.+)%.[^.]+$') or name
end

-- Text from the list for a menu row: no control characters, bounded.
local function clean(text)
	return (text:sub(1, MAX_TITLE):gsub('%c', ' '))
end

-- The list on disk ----------------------------------------------------------------

local function list_path()
	local path = mp.command_native({'expand-path', LIST_PATH})
	if type(path) ~= 'string' or path == '' or path == LIST_PATH then return nil end
	return path
end

-- An entry read from the list, checked and in its normalised form, or nil.
local function check_entry(entry, windows)
	if type(entry) ~= 'table' then return nil end
	local path = file_path(entry.path, nil, windows)
	if not path then return nil end
	if not finite(entry.position) or entry.position < 0 then return nil end
	if not finite(entry.duration) or entry.duration <= 0 then return nil end
	if not finite(entry.updated) or entry.updated < 0 or entry.updated > 1e11 then return nil end
	local title = entry.title
	if type(title) ~= 'string' or title == '' or #title > MAX_TITLE then title = title_of(path) end
	return {path = path, title = title, position = entry.position, duration = entry.duration,
		updated = math.floor(entry.updated)}
end

-- Newest first; the same time, by path, so the order never depends on Lua.
local function sort_entries(entries)
	table.sort(entries, function(a, b)
		if a.updated ~= b.updated then return a.updated > b.updated end
		return a.path < b.path
	end)
end

-- Warned once until the list can be read again, not on every save.
local warned_broken = false

local function warn_broken(why)
	if warned_broken then return end
	warned_broken = true
	msg.warn('Ignoring ' .. LIST_PATH .. ' (' .. why .. '): continue watching starts empty, '
		.. 'and the file is only written again when there is something to save')
end

-- The entries of the list, checked, newest first, one per file. Missing file:
-- empty. Broken or unreadable: empty, and a warning.
local function read_list()
	local path = list_path()
	if not path then return {} end
	local file = io.open(path, 'rb')
	if not file then
		if utils.file_info(path) then warn_broken('cannot be read') end
		return {}
	end
	local content = file:read(MAX_LIST_BYTES + 1)
	file:close()
	if type(content) ~= 'string' then
		warn_broken('cannot be read')
		return {}
	end
	if #content > MAX_LIST_BYTES then
		warn_broken('too big')
		return {}
	end
	local ok, value = pcall(utils.parse_json, content)
	if not ok or type(value) ~= 'table' or value.version ~= 1 or type(value.entries) ~= 'table' then
		warn_broken('damaged')
		return {}
	end
	warned_broken = false
	local windows = is_windows()
	local by_key, entries = {}, {}
	-- pairs, not ipairs: a null in the array leaves a hole.
	for _, raw in pairs(value.entries) do
		local entry = check_entry(raw, windows)
		if entry then
			local key = path_key(entry.path, windows)
			local seen = by_key[key]
			if not seen or entry.updated > seen.updated then by_key[key] = entry end
		end
	end
	for _, entry in pairs(by_key) do entries[#entries + 1] = entry end
	sort_entries(entries)
	-- A list made by hand with thousands of entries: only the newest count.
	for i = #entries, opts.history_size + 1, -1 do entries[i] = nil end
	return entries
end

-- A name for the temporary file of this mpv: two windows writing at once
-- must not share one. mpv's pid; a counter for writes within one mpv.
local tmp_count = 0
local function tmp_name(path)
	tmp_count = tmp_count + 1
	local pid = mp.get_property_number('pid')
	if not finite(pid) or pid < 1 or pid > 2 ^ 31 or pid % 1 ~= 0 then pid = math.random(1, 2 ^ 30) end
	return string.format('%s.%d-%d.tmp', path, pid, tmp_count)
end

-- Removes `<list>.<pid>-<n>.tmp` files (that exact pattern, next to the list)
-- last changed more than STALE_TMP_AGE ago. Younger ones may be another
-- window's write in progress and stay.
local swept = false
local function remove_stale_tmp(path)
	if swept then return end
	swept = true
	local dir, base = utils.split_path(path)
	local names = dir and base and utils.readdir(dir, 'files')
	if type(names) ~= 'table' then return end
	local prefix, now = base .. '.', clock.now()
	for _, name in ipairs(names) do
		if type(name) == 'string' and name:sub(1, #prefix) == prefix
			and name:sub(#prefix + 1):match('^%d+%-%d+%.tmp$') then
			local file = utils.join_path(dir, name)
			local info = utils.file_info(file)
			if info and info.is_file and finite(info.mtime) and now - info.mtime > STALE_TMP_AGE then
				os.remove(file)
			end
		end
	end
end

-- Puts `tmp` in place of `path`. rename() replaces a link at `path` itself,
-- never what it points to. On Windows it does not replace at all: the old
-- file goes aside first, and back if the second rename fails.
local function replace(tmp, path)
	local renamed, err = os.rename(tmp, path)
	if renamed or not is_windows() then return renamed, err end
	local old = tmp_name(path)
	if not os.rename(path, old) then return false, err end
	renamed, err = os.rename(tmp, path)
	if not renamed then
		os.rename(old, path)
		return false, err
	end
	os.remove(old)
	return true
end

local function write_list(entries)
	local path = list_path()
	if not path then return false end
	remove_stale_tmp(path)
	local json, err = utils.format_json({version = 1, entries = entries})
	local ok = false
	if json then
		local tmp = tmp_name(path)
		-- A leftover (or a link planted there) goes first, so io.open creates the file.
		os.remove(tmp)
		local file
		file, err = io.open(tmp, 'wb')
		if file then
			local written, write_err = file:write(json .. '\n')
			local closed, close_err = file:close()
			if written and closed then
				ok, err = replace(tmp, path)
			else
				err = write_err or close_err
			end
			if not ok then os.remove(tmp) end
		end
	end
	if not ok then msg.warn('Could not save ' .. LIST_PATH .. ': ' .. tostring(err)) end
	return ok
end

-- State ---------------------------------------------------------------------------

local state = {
	-- The file playing when it is one: {path, key, title}; nil otherwise.
	file = nil,
	serial = 0, -- counts the files loaded, so an answer for an older one is dropped
	time = nil, duration = nil, chapters = nil, -- last values seen for this file
	saved_at = nil, -- position of the last save (or attempt)
	-- The question on screen: {token, position, title, paused_by_us, shown,
	-- closed, restored, timer}; nil when none.
	prompt = nil,
	-- For the list menu while it is open: key -> the file exists, root -> it
	-- answers (see root_of).
	exists = nil, roots = nil,
	cleared = false, -- Clear history while this file plays: only end-file saves it
}

local function publish(entries)
	mp.set_property_native(AVAILABLE_PROP, opts.enabled and #entries > 0)
end

-- `12:34`, `1:02:03`.
local function format_clock(seconds)
	local s = math.floor(math.max(0, seconds))
	local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
	if h > 0 then return string.format('%d:%02d:%02d', h, m, s % 60) end
	return string.format('%d:%02d', m, s % 60)
end

-- Seconds as `12.345` for seek, built from integers so the decimal separator
-- never depends on the C locale.
local function format_seconds(seconds)
	local ms = math.max(0, math.floor(seconds * 1000 + 0.5))
	return string.format('%d.%03d', math.floor(ms / 1000), ms % 1000)
end

local function same_day(a, b)
	return a.year == b.year and a.month == b.month and a.day == b.day
end

-- `today`, `yesterday`, `Oct 12` or `Oct 12, 2025`, in hikari's language.
local function format_date(t, now)
	local date, today = os.date('*t', t), os.date('*t', now)
	if same_day(date, today) then return i18n.t('resume_today') end
	local yesterday = os.date('*t', os.time({year = today.year, month = today.month, day = today.day - 1, hour = 12}))
	if same_day(date, yesterday) then return i18n.t('resume_yesterday') end
	local vars = {day = date.day, month = i18n.t('resume_month_' .. date.month), year = date.year}
	return i18n.t(date.year == today.year and 'resume_date' or 'resume_date_year', vars)
end

-- Start of the last ending chapter in the second half of a file of
-- `duration` seconds, or nil.
local KINDS = chapter_kinds.kinds()
local function ending_start(chapters, duration)
	if type(chapters) ~= 'table' or not finite(duration) then return nil end
	local start = nil
	for _, chapter in ipairs(chapters) do
		if type(chapter) == 'table' and finite(chapter.time) and chapter.time >= duration * ENDING_SHARE then
			local kind = chapter_kinds.classify(KINDS, chapter.title)
			if kind and kind.name == 'endings' and (not start or chapter.time > start) then start = chapter.time end
		end
	end
	return start
end

local function is_watched(position, duration, chapters)
	if position >= duration * WATCHED_SHARE then return true end
	local ending = ending_start(chapters, duration)
	return ending ~= nil and position >= ending
end

-- Menus ---------------------------------------------------------------------------

-- Where a file lives, to ask once whether it answers: \\host\share\ or the
-- drive on Windows; a mount point (/Volumes/<x>, /mnt/<x>, /media/<user>/<x>,
-- /run/media/<user>/<x>) or else the file's folder elsewhere.
local MOUNT_PATTERNS = {'^(/Volumes/[^/]+)/', '^(/mnt/[^/]+)/', '^(/media/[^/]+/[^/]+)/', '^(/run/media/[^/]+/[^/]+)/'}
local function root_of(path, windows)
	if windows then
		local unc = path:match('^(\\\\[^\\]+\\[^\\]+)\\')
		if unc then return unc .. '\\' end
		local drive = path:match('^(%a:)\\')
		return drive and drive .. '\\' or nil
	end
	for _, pattern in ipairs(MOUNT_PATTERNS) do
		local root = path:match(pattern)
		if root then return root end
	end
	local parent = path:match('^(.*)/[^/]*$')
	if parent == '' then return '/' end
	return parent
end

-- Does the file of `entry` exist? Its root first, once per opening of the
-- menu: a root that is not there makes all its files unavailable without
-- asking for each (a share that is off answers each question slowly).
local function file_exists(entry, windows)
	local key = path_key(entry.path, windows)
	if state.exists[key] == nil then
		local root = root_of(entry.path, windows)
		local root_key = root and path_key(root, windows)
		if root_key and state.roots[root_key] == nil then
			local info = utils.file_info(root)
			state.roots[root_key] = info ~= nil and info.is_dir == true
		end
		if root_key and not state.roots[root_key] then
			state.exists[key] = false
		else
			local info = utils.file_info(entry.path)
			state.exists[key] = info ~= nil and info.is_file == true
		end
	end
	return state.exists[key]
end

-- The list menu for `entries` (read now when not given).
local function list_menu_data(entries)
	entries = entries or read_list()
	local windows, now = is_windows(), clock.now()
	state.exists, state.roots = state.exists or {}, state.roots or {}
	local items = {}
	for _, entry in ipairs(entries) do
		local item = {title = clean(entry.title)}
		if file_exists(entry, windows) then
			item.hint = format_clock(entry.position) .. ' / ' .. format_clock(entry.duration)
				.. ' · ' .. format_date(entry.updated, now)
			item.value = {'script-message-to', script_name, 'open-file', entry.path}
		else
			item.hint = i18n.t('resume_unavailable')
			item.selectable, item.muted = false, true
		end
		items[#items + 1] = item
	end
	if #items == 0 then
		items[1] = {title = i18n.t('resume_empty'), selectable = false, muted = true, italic = true}
	else
		items[#items].separator = true
		items[#items + 1] = {title = i18n.t('resume_clear'), value = {'script-message-to', script_name, 'clear-history'}}
	end
	return {type = MENU_TYPE, title = i18n.t('resume_title'), items = items}
end

local function prompt_data()
	local p = state.prompt
	local function answer(choice) return {'script-message-to', script_name, 'prompt-answer', choice, p.token} end
	return {
		type = PROMPT_TYPE, title = clean(p.title), selected_index = 1,
		items = {
			{title = i18n.t('resume_continue', {time = format_clock(p.position)}), value = answer('continue')},
			{title = i18n.t('resume_start_over'), value = answer('start')},
		},
	}
end

local function send_menu(message, data)
	local json, err = utils.format_json(data)
	if not json then
		msg.error('Could not build the continue watching menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

-- Redraws whichever of our menus is open.
local function update_open_menu()
	local open = mp.get_property_native('user-data/uosc/menu/type')
	if open == MENU_TYPE then
		send_menu('update-menu', list_menu_data())
	elseif open == PROMPT_TYPE and state.prompt and not state.prompt.closed then
		send_menu('update-menu', prompt_data())
	end
end

local function open_menu()
	if not opts.enabled then
		mp.osd_message(i18n.t('resume_disabled'), 3)
		return
	end
	state.exists, state.roots = {}, {}
	local entries = read_list()
	-- Keeps the button in step with a list another mpv window changed.
	publish(entries)
	send_menu('open-menu', list_menu_data(entries))
end

-- Saving --------------------------------------------------------------------------

-- Reads the list again, lets `change` modify it (it returns true when it did)
-- and writes it back, newest first and within history_size.
local function update_list(change)
	local entries = read_list()
	if not change(entries) then return end
	sort_entries(entries)
	for i = #entries, opts.history_size + 1, -1 do entries[i] = nil end
	write_list(entries)
	publish(entries)
	if mp.get_property_native('user-data/uosc/menu/type') == MENU_TYPE then send_menu('update-menu', list_menu_data(entries)) end
end

-- Records `position` for the file playing: removed when watched, nothing
-- under MIN_POSITION, the entry updated otherwise.
local function save_position(position)
	local file, duration = state.file, state.duration
	if not file or not finite(position) or not finite(duration) or duration <= 0 then return end
	state.saved_at = position
	local windows = is_windows()
	if is_watched(position, duration, state.chapters) then
		update_list(function(entries)
			for i, entry in ipairs(entries) do
				if path_key(entry.path, windows) == file.key then
					table.remove(entries, i)
					return true
				end
			end
			return false
		end)
	elseif position >= MIN_POSITION then
		update_list(function(entries)
			for i = #entries, 1, -1 do
				if path_key(entries[i].path, windows) == file.key then table.remove(entries, i) end
			end
			table.insert(entries, 1, {path = file.path, title = file.title, position = position,
				duration = duration, updated = clock.now()})
			return true
		end)
	end
end

local function tick()
	if not state.file or state.cleared or (state.prompt and not state.prompt.closed) then return end
	if mp.get_property_native('pause') ~= false then return end
	local position = state.time
	if not finite(position) then return end
	if state.saved_at and math.abs(position - state.saved_at) < MOVED then return end
	save_position(position)
end

-- The question --------------------------------------------------------------------

local function restore_pause(p)
	if p.paused_by_us and not p.restored then mp.set_property_native('pause', false) end
	p.restored = true
	if p.timer then p.timer:kill() end
	p.timer = nil
end

local function seek_to(position)
	mp.commandv('seek', format_seconds(position), 'absolute+exact')
end

-- The menu answered: 'continue' or 'start', for the file of `token`.
local function prompt_answer(choice, token)
	local p = state.prompt
	if not p or token ~= p.token or (choice ~= 'continue' and choice ~= 'start') then
		msg.verbose('Ignoring an answer for a question no longer open')
		return
	end
	state.prompt = nil
	if choice == 'continue' then seek_to(p.position) end
	restore_pause(p)
end

-- The menu closed (or never showed): from the beginning, unless an answer
-- still comes for it.
local function prompt_closed(p)
	if p.closed then return end
	p.closed = true
	restore_pause(p)
end

local function ask(entry)
	local paused = mp.get_property_native('pause')
	state.prompt = {
		token = tostring(state.serial), position = entry.position, title = state.file.title,
		paused_by_us = paused == false,
	}
	local p = state.prompt
	if p.paused_by_us then mp.set_property_native('pause', true) end
	send_menu('open-menu', prompt_data())
	p.timer = mp.add_timeout(PROMPT_TIMEOUT, function()
		p.timer = nil
		if not p.shown and state.prompt == p then
			msg.warn('The continue watching question did not show (is uosc installed?): starting from the beginning')
			prompt_closed(p)
		end
	end)
end

-- Ends the question of a file that is no longer playing.
local function drop_prompt()
	local p = state.prompt
	if not p then return end
	state.prompt = nil
	if not p.closed and mp.get_property_native('user-data/uosc/menu/type') == PROMPT_TYPE then
		mp.commandv('script-message-to', 'uosc', 'close-menu', PROMPT_TYPE)
	end
	restore_pause(p)
end

-- Events --------------------------------------------------------------------------

local function on_file_loaded()
	state.serial = state.serial + 1
	drop_prompt()
	state.file, state.saved_at, state.cleared = nil, nil, false
	state.time = mp.get_property_number('time-pos')
	state.duration = mp.get_property_number('duration')
	state.chapters = mp.get_property_native('chapter-list')
	local windows = is_windows()
	local path = file_path(mp.get_property_native('path'), mp.get_property_native('working-directory'), windows)
	if not path then return end
	state.file = {path = path, key = path_key(path, windows), title = title_of(path)}
	local entry
	for _, e in ipairs(read_list()) do
		if path_key(e.path, windows) == state.file.key then entry = e break end
	end
	if not entry then return end
	if finite(state.time) and state.time >= START_TOLERANCE then
		msg.verbose('Already past the start (resume-playback or --start): not asking')
		return
	end
	if finite(state.duration) and entry.position >= state.duration - END_MARGIN then
		msg.verbose('The saved position is at the end of the file: starting from the beginning')
		return
	end
	if opts.ask then
		ask(entry)
	else
		seek_to(entry.position)
	end
end

local function on_end_file()
	drop_prompt()
	if state.file then save_position(state.time) end
	state.file = nil
end

local function on_menu_type(_, value)
	local p = state.prompt
	if not p then return end
	if value == PROMPT_TYPE then
		p.shown = true
	elseif p.shown then
		prompt_closed(p)
	end
end

-- Keeps the last value seen: mpv may clear a property before end-file comes.
local function keep(field)
	return function(_, value)
		if value ~= nil and state.file then state[field] = value end
	end
end

local function open_file(path)
	local windows = is_windows()
	local key = type(path) == 'string' and path_key(path, windows)
	for _, entry in ipairs(read_list()) do
		if path_key(entry.path, windows) == key then
			mp.commandv('loadfile', entry.path, 'replace')
			return
		end
	end
	msg.warn('Ignoring a file that is not in the continue watching list')
end

local function clear_history()
	if write_list({}) then
		msg.info('Continue watching: history cleared')
	end
	publish({})
	-- The file playing comes back when it ends, not at the next tick.
	state.saved_at, state.cleared = nil, true
end

mp.add_key_binding(nil, 'open-menu', open_menu)
if opts.enabled then
	mp.register_script_message('open-file', open_file)
	mp.register_script_message('clear-history', clear_history)
	mp.register_script_message('prompt-answer', prompt_answer)
	mp.register_event('file-loaded', on_file_loaded)
	mp.register_event('end-file', on_end_file)
	mp.register_event('shutdown', on_end_file)
	mp.observe_property('time-pos', 'number', keep('time'))
	mp.observe_property('duration', 'number', keep('duration'))
	mp.observe_property('chapter-list', 'native', keep('chapters'))
	mp.observe_property('user-data/uosc/menu/type', 'native', on_menu_type)
	mp.add_periodic_timer(SAVE_INTERVAL, tick)
	-- Another language: an open menu or question is redrawn in it.
	i18n.on_change(update_open_menu)
	publish(read_list())
else
	publish({})
end

if HIKARI_RESUME_TEST then
	return {
		opts = opts, state = state, clock = clock,
		file_path = file_path, normalize = normalize, path_key = path_key, title_of = title_of, root_of = root_of,
		read_list = read_list, write_list = write_list, list_menu_data = list_menu_data, prompt_data = prompt_data,
		format_clock = format_clock, format_date = format_date, is_watched = is_watched, ending_start = ending_start,
		tick = tick, save_position = save_position, open_menu = open_menu,
		SAVE_INTERVAL = SAVE_INTERVAL, MIN_POSITION = MIN_POSITION, PROMPT_TIMEOUT = PROMPT_TIMEOUT,
	}
end
