-- hikari-update: tells you when a new hikari release is out. It only tells you:
-- it never downloads or installs anything.
--
-- When there is a newer release than the installed one, the first file opened
-- shows "hikari X.Y.Z is out · Alt+u" for a few seconds, and a button
-- appears in uosc's controls bar (uosc.conf shows it while
-- user-data/hikari_update/available is true, mpv 0.36+). The button, or Alt+u,
-- opens a menu with: the release notes in the browser, copying the update
-- command (PowerShell on Windows, a terminal elsewhere) and "Don't remind me of
-- this version", which stops the notice for that version only. Texts follow
-- hikari's language (hikari-i18n).
--
-- mpv turns this file name into the script name `hikari_update`, so:
--   input.conf:  Alt+u script-binding hikari_update/open-menu
--   options:     script-opts/hikari-update.conf, or
--                script-opts-append=hikari-update-enabled=no in mpv.conf
--                (enabled=yes|no, interval_hours=<hours, at least 1>)
--
-- Decisions:
-- - Installed version: the `hikari_version=X.Y.Z` line of ~~/hikari-installed.txt,
--   the record both installers write (the last such line wins, as in the
--   installers). No record, or a version that is not X.Y.Z (a copy of the
--   repository says `dev`): nothing is checked and nothing is shown.
-- - Latest version: no GitHub API (60 requests an hour per address). curl asks
--   for the headers of https://github.com/SCEPTICG/hikari-mpv/releases/latest
--   without following redirects, and the version is the tag of the
--   `Location: https://github.com/SCEPTICG/hikari-mpv/releases/tag/vX.Y.Z` header.
--   The answer is not trusted: the whole URL must be exactly that, and the tag
--   exactly v<digits>.<digits>.<digits> (at most 9 digits each); versions are
--   compared as numbers (0.10.0 > 0.9.9). curl ships with Windows 10/11 and
--   macOS and almost every Linux; without it, or without network, nothing is
--   shown (only a verbose log line; curl is looked for first, so mpv does not
--   log a failed subprocess either). `-q` keeps curl from reading a .curlrc.
-- - Programs on Windows: always by absolute path under %SystemRoot%\System32
--   (curl.exe, cmd.exe, clip.exe, WindowsPowerShell\v1.0\powershell.exe).
--   mpv starts them with CreateProcessW, which looks for a bare name in mpv's
--   folder and in the current folder (the video's, after a double click)
--   before System32: a curl.exe next to a video would run. A SystemRoot that
--   is not a plain drive path (C:\Windows) means no program is started at all.
-- - When: on the first file-loaded after start-up, never at start-up itself,
--   and at most once every interval_hours (24 by default). The time of the
--   last attempt is saved, failed or not, so there is at most one request per
--   interval even offline; the next interval tries again. Inside the interval
--   the version found last time is used, without network.
-- - The request runs as an asynchronous subprocess (playback_only=false, so a
--   change of file does not kill it), with --max-time 10: playback never waits.
-- - State: ~~/hikari-update.txt, `last_check=<unix time>`, `latest=X.Y.Z`,
--   `dismissed=X.Y.Z`, written through a temporary file and a rename. Unknown,
--   broken or invalid lines are ignored (a corrupt file just means "never
--   checked"). mpv.conf must not include it: it is not an mpv config file.
--   If it cannot be written, there is still only one request per mpv session
--   (only the first file-loaded checks), but each new session asks again.
-- - Opening the release page: `cmd.exe /c start "" <url>` on Windows, `open` on
--   macOS, `xdg-open` elsewhere, detached. The URL is built here from a
--   validated version, so it only ever has [A-Za-z0-9:/._-] in it: nothing cmd
--   could read as an operator.
-- - Copying the command: mpv's `clipboard/text` property (mpv 0.40+) when
--   setting it works; otherwise clip.exe, then PowerShell's Set-Clipboard on
--   Windows, pbcopy on macOS, and wl-copy (Wayland), xclip or xsel elsewhere,
--   the text going in through stdin. If all fail, the OSD shows the command so
--   it can be typed by hand. xclip, wl-copy and xsel leave a process in the
--   background holding the text, and mpv waits until every copy of the
--   subprocess's stdout and stderr is closed, captured or not: they run
--   through `sh -c 'exec "$0" "$@" >/dev/null 2>&1'` so that process holds none.
-- - Platform: the `platform` property (mpv 0.36+); on older mpv, `\` as path
--   separator means Windows and /System/Library/CoreServices means macOS.

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

local OPTIONS_ID = 'hikari-update'
local RECORD_PATH = '~~/hikari-installed.txt'
local STATE_PATH = '~~/hikari-update.txt'
local MENU_TYPE = 'hikari-update'
-- uosc shows the controls-bar button only while this is true (see uosc.conf).
local AVAILABLE_PROP = 'user-data/hikari_update/available'

local LATEST_URL = 'https://github.com/SCEPTICG/hikari-mpv/releases/latest'
local TAG_URL_PREFIX = 'https://github.com/SCEPTICG/hikari-mpv/releases/tag/'
local UPDATE_COMMANDS = {
	windows = 'irm https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.ps1 | iex',
	unix = 'curl -fsSL https://github.com/SCEPTICG/hikari-mpv/releases/latest/download/hikari.sh | bash',
}
local CURL_TIMEOUT = 10        -- seconds, --max-time
local MAX_HEADERS = 65536      -- bytes of curl output looked at
local MAX_STATE = 4096         -- bytes of the state file and record read
local NOTICE_SECONDS = 5
-- The notice waits this long after the file loads: players such as AnimeJaNai
-- show the media title on the OSD as a file starts, and mpv shows one OSD
-- message at a time, so an earlier notice would be replaced straight away.
local NOTICE_DELAY = 4
local DEFAULT_INTERVAL = 24
local MIN_INTERVAL, MAX_INTERVAL = 1, 24 * 365

local opts = {enabled = true, interval_hours = DEFAULT_INTERVAL}
options.read_options(opts, OPTIONS_ID)

-- Unix time; tests replace it.
local now = os.time

-- ---------------------------------------------------------------------------
-- Versions
-- ---------------------------------------------------------------------------

-- {major, minor, patch} of a strict "X.Y.Z" (1 to 9 digits each), nil otherwise.
local function parse_version(text)
	if type(text) ~= 'string' then return nil end
	local a, b, c = text:match('^(%d+)%.(%d+)%.(%d+)$')
	if not a or #a > 9 or #b > 9 or #c > 9 then return nil end
	return {tonumber(a), tonumber(b), tonumber(c)}
end

-- "X.Y.Z" without leading zeros, nil when not a version.
local function normalize(text)
	local v = parse_version(text)
	if not v then return nil end
	return string.format('%d.%d.%d', v[1], v[2], v[3])
end

-- -1, 0 or 1; nil when either is not a version.
local function compare_versions(a, b)
	local va, vb = parse_version(a), parse_version(b)
	if not va or not vb then return nil end
	for i = 1, 3 do
		if va[i] ~= vb[i] then return va[i] < vb[i] and -1 or 1 end
	end
	return 0
end

local function is_newer(candidate, than) return compare_versions(candidate, than) == 1 end

-- The version in curl's header output: the first Location header (any case,
-- LF or CRLF) must be exactly TAG_URL_PREFIX .. 'vX.Y.Z'. Anything else: nil.
local function parse_location(headers)
	if type(headers) ~= 'string' then return nil end
	headers = headers:sub(1, MAX_HEADERS)
	for line in (headers .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', '')
		local name, value = line:match('^([%w-]+):[ \t]*(.-)[ \t]*$')
		if name and name:lower() == 'location' then
			if value:sub(1, #TAG_URL_PREFIX) ~= TAG_URL_PREFIX then return nil end
			local tag = value:sub(#TAG_URL_PREFIX + 1)
			local a, b, c = tag:match('^v(%d+)%.(%d+)%.(%d+)$')
			if not a then return nil end
			return normalize(a .. '.' .. b .. '.' .. c)
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Files
-- ---------------------------------------------------------------------------

local function expand(path)
	local expanded = mp.command_native({'expand-path', path})
	if type(expanded) ~= 'string' or expanded == '' then return nil end
	return expanded
end

-- At most MAX_STATE bytes of a file, nil when it cannot be read.
local function read_small(path)
	if not path then return nil end
	local file = io.open(path, 'rb')
	if not file then return nil end
	local content = file:read(MAX_STATE)
	file:close()
	return content or ''
end

-- key=value lines (spaces around both trimmed, CR dropped, # comments and
-- lines without '=' skipped); a later line wins.
local function parse_key_values(content)
	local values = {}
	if type(content) ~= 'string' then return values end
	for line in (content .. '\n'):gmatch('([^\n]*)\n') do
		line = line:gsub('\r$', '')
		local key, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
		if key and not line:match('^%s*#') then values[key] = value end
	end
	return values
end

-- The installed hikari version ("X.Y.Z"), nil without a record or for `dev`.
local function installed_version()
	local values = parse_key_values(read_small(expand(RECORD_PATH)))
	return normalize(values.hikari_version)
end

-- Saved state; every field is checked and dropped when invalid.
local function read_state()
	local values = parse_key_values(read_small(expand(STATE_PATH)))
	local state = {latest = normalize(values.latest), dismissed = normalize(values.dismissed)}
	local t = values.last_check
	if type(t) == 'string' and t:match('^%d+$') and #t <= 12 then state.last_check = tonumber(t) end
	return state
end

local function state_content(state)
	local lines = {'# Written by hikari-update.lua: when hikari last looked for a new version. Safe to delete.'}
	if state.last_check then lines[#lines + 1] = 'last_check=' .. string.format('%d', state.last_check) end
	if normalize(state.latest) then lines[#lines + 1] = 'latest=' .. normalize(state.latest) end
	if normalize(state.dismissed) then lines[#lines + 1] = 'dismissed=' .. normalize(state.dismissed) end
	return table.concat(lines, '\n') .. '\n'
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

local function save_state(state)
	local path = expand(STATE_PATH)
	local ok, err = false, 'no config folder'
	if path then ok, err = write_file_atomic(path, state_content(state)) end
	if not ok then msg.warn('Could not save ' .. STATE_PATH .. ': ' .. tostring(err)) end
	return ok
end

-- ---------------------------------------------------------------------------
-- Platform
-- ---------------------------------------------------------------------------

-- 'windows', 'darwin' or another name (Linux, BSD...), from mpv when it says.
local function platform()
	local p = mp.get_property('platform')
	if type(p) == 'string' and p ~= '' then return p end
	if package.config:sub(1, 1) == '\\' then return 'windows' end
	local f = io.open('/System/Library/CoreServices/SystemVersion.plist', 'rb')
	if f then f:close(); return 'darwin' end
	return 'linux'
end

-- Windows: the System32 folder from SystemRoot, nil unless SystemRoot is a
-- plain drive path such as C:\Windows (one trailing backslash is dropped).
local function system32()
	local root = os.getenv('SystemRoot')
	if type(root) ~= 'string' then return nil end
	root = root:gsub('\\$', '')
	if not root:match('^%a:\\[^%c"/:*?<>|%%]+$') or root:match('\\\\') or root:match('\\$') then return nil end
	return root .. '\\System32'
end

-- Windows: the absolute path of a program in System32, nil when SystemRoot
-- is not usable.
local function windows_program(relative)
	local dir = system32()
	if not dir then return nil end
	return dir .. '\\' .. relative
end

local function update_command(p)
	return (p or platform()) == 'windows' and UPDATE_COMMANDS.windows or UPDATE_COMMANDS.unix
end


-- The release page of a version, nil when it is not one.
local function release_url(version)
	version = normalize(version)
	if not version then return nil end
	return TAG_URL_PREFIX .. 'v' .. version
end

-- The command line that opens `url` in the browser. `url` must already be
-- one of ours (release_url): only [A-Za-z0-9:/._-].
local function open_url_args(url, p)
	if type(url) ~= 'string' or not url:match('^https://[%w:/._-]+$') then return nil end
	p = p or platform()
	if p == 'windows' then
		local cmd = windows_program('cmd.exe')
		if not cmd then return nil end
		return {cmd, '/c', 'start', '', url}
	end
	if p == 'darwin' then return {'open', url} end
	return {'xdg-open', url}
end

-- A Linux clipboard program with stdout and stderr sent to /dev/null, so the
-- copy it leaves in the background does not keep mpv's pipes open.
local QUIET = 'exec "$0" "$@" >/dev/null 2>&1'
local function quiet(...) return {'sh', '-c', QUIET, ...} end

-- The program a clipboard command runs, for the log.
local function tool_name(tool)
	if tool[1] == 'sh' and tool[3] == QUIET then return tool[4] end
	return tool[1]
end

-- The programs that can take text on stdin into the clipboard, in order.
-- On Windows none when SystemRoot is not usable.
local function clipboard_tools(p)
	p = p or platform()
	if p == 'windows' then
		local clip = windows_program('clip.exe')
		local powershell = windows_program('WindowsPowerShell\\v1.0\\powershell.exe')
		if not clip or not powershell then return {} end
		return {
			{clip},
			{powershell, '-NoProfile', '-NonInteractive', '-Command',
				'Set-Clipboard -Value ([Console]::In.ReadToEnd())'},
		}
	end
	if p == 'darwin' then return {{'pbcopy'}} end
	local tools = {}
	local wayland = os.getenv('WAYLAND_DISPLAY')
	if wayland and wayland ~= '' then tools[#tools + 1] = quiet('wl-copy') end
	tools[#tools + 1] = quiet('xclip', '-selection', 'clipboard')
	tools[#tools + 1] = quiet('xsel', '--clipboard', '--input')
	return tools
end

-- ---------------------------------------------------------------------------
-- State of this session
-- ---------------------------------------------------------------------------

local installed = nil   -- installed version, read on the first file
local state = {}        -- what read_state returned, kept up to date
local checked = false   -- the first file-loaded has been handled
local notified = nil    -- version the notice was shown for this session
local loaded_at = nil   -- mp.get_time() of the first file-loaded
local notice_timer = nil -- pending delayed notice

-- The newer version there is, dismissed or not; nil when none is known.
local function pending_version()
	if installed and is_newer(state.latest, installed) then return state.latest end
	return nil
end

-- The newer version the user still wants to hear about.
local function notice_version()
	local v = pending_version()
	if v and v ~= state.dismissed then return v end
	return nil
end

local function set_button(on)
	mp.set_property_native(AVAILABLE_PROP, on and true or false)
end

local function show_notice()
	notice_timer = nil
	local v = notice_version()
	if v and notified ~= v then
		notified = v
		mp.osd_message(i18n.t('update_notice', {version = v}), NOTICE_SECONDS)
	end
end

-- Button on or off at once; the notice once per session and version, no
-- sooner than NOTICE_DELAY seconds after the file loaded.
local function announce()
	local v = notice_version()
	set_button(v ~= nil)
	if not v or notified == v or notice_timer then return end
	local wait = (loaded_at or mp.get_time()) + NOTICE_DELAY - mp.get_time()
	if wait > 0 then notice_timer = mp.add_timeout(wait, show_notice) else show_notice() end
end

-- ---------------------------------------------------------------------------
-- Checking
-- ---------------------------------------------------------------------------

local function interval_seconds()
	local hours = tonumber(opts.interval_hours)
	if not hours or hours ~= hours then hours = DEFAULT_INTERVAL end
	hours = math.max(MIN_INTERVAL, math.min(MAX_INTERVAL, hours))
	return hours * 3600
end

-- Is it time to ask GitHub again? A last check in the future (clock moved
-- back) counts as too old.
local function check_due(t)
	if not state.last_check then return true end
	if state.last_check > t then return true end
	return t - state.last_check >= interval_seconds()
end

-- Is there an executable `name` in PATH? Only asked outside Windows (where
-- curl.exe is taken from System32, never from PATH), so a missing curl means
-- no attempt at all instead of mpv logging "Subprocess failed" at every check.
local function in_path(name)
	local path = os.getenv('PATH')
	if type(path) ~= 'string' or path == '' then return false end
	for dir in path:gmatch('[^:]+') do
		local file = io.open(dir .. '/' .. name, 'rb')
		if file then file:close(); return true end
	end
	return false
end

-- The curl program to run: System32\curl.exe on Windows (only when it is
-- there), `curl` from PATH elsewhere. nil when there is none.
local function curl_program(p)
	p = p or platform()
	if p == 'windows' then
		local curl = windows_program('curl.exe')
		local info = curl and utils.file_info(curl)
		if not info or not info.is_file then return nil end
		return curl
	end
	if not in_path('curl') then return nil end
	return 'curl'
end

-- `-q` first: curl must not read the user's .curlrc.
local function curl_args(program)
	return {
		program or 'curl', '-q', '--silent', '--show-error', '--head', '--max-time', tostring(CURL_TIMEOUT),
		'--proto', '=https', '--max-redirs', '0', LATEST_URL,
	}
end

local function on_curl_done(success, result, err)
	local latest = nil
	if not success or type(result) ~= 'table' then
		msg.verbose('Update check failed: ' .. tostring(err))
	elseif result.status ~= 0 then
		msg.verbose('Update check failed: curl ' .. tostring(result.error_string) .. ' '
			.. tostring(result.status) .. ' ' .. tostring(result.stderr or ''))
	else
		latest = parse_location(result.stdout)
		if not latest then msg.verbose('Update check: no release version in the answer') end
	end
	-- Re-read: another mpv may have saved a dismissal in the meantime.
	local fresh = read_state()
	state.dismissed = fresh.dismissed or state.dismissed
	if latest then state.latest = latest end
	save_state(state)
	announce()
end

local function start_check()
	local curl = curl_program()
	if not curl then
		msg.verbose('curl not found: not checking for updates')
		announce()
		return
	end
	-- Saved before asking: two files opened at once, or mpv closed mid-way,
	-- never mean a second request in the same interval.
	state.last_check = now()
	save_state(state)
	mp.command_native_async({
		name = 'subprocess',
		args = curl_args(curl),
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
	}, on_curl_done)
end

-- The first file opened: check (or use the saved answer) and tell.
local function on_file_loaded()
	if checked then return end
	checked = true
	loaded_at = mp.get_time()
	if not opts.enabled then return end
	installed = installed_version()
	if not installed then
		msg.verbose('No released hikari version in ' .. RECORD_PATH .. ': not checking for updates')
		return
	end
	state = read_state()
	if check_due(now()) then
		start_check()
	else
		announce()
	end
end

-- ---------------------------------------------------------------------------
-- Menu and actions
-- ---------------------------------------------------------------------------

local function menu_data()
	local v = pending_version()
	local p = platform()
	local dismissed = v ~= nil and v == state.dismissed
	return {
		type = MENU_TYPE,
		title = i18n.t('update_title', {version = tostring(v)}),
		items = {
			{
				title = i18n.t('update_notes', {version = tostring(v)}),
				hint = i18n.t('update_notes_hint'),
				value = {'script-message-to', script_name, 'open-notes'},
			},
			{
				title = i18n.t('update_copy'),
				hint = p == 'windows' and 'PowerShell' or i18n.t('update_copy_hint_terminal'),
				value = {'script-message-to', script_name, 'copy-command'},
			},
			{
				title = i18n.t('update_dismiss'),
				hint = dismissed and i18n.t('update_dismissed_hint') or nil,
				selectable = not dismissed,
				muted = dismissed or nil,
				value = {'script-message-to', script_name, 'dismiss'},
			},
		},
	}
end

local function send_menu(message)
	local json, err = utils.format_json(menu_data())
	if not json then
		msg.error('Could not build the update menu: ' .. tostring(err))
		return
	end
	mp.commandv('script-message-to', 'uosc', message, json)
end

local function open_menu()
	if not opts.enabled then
		mp.osd_message(i18n.t('update_disabled'), 3)
		return
	end
	if not installed then installed = installed_version() end
	if not installed then
		mp.osd_message(i18n.t('update_unknown'), 3)
		return
	end
	if not checked then state = read_state() end
	if not pending_version() then
		mp.osd_message(i18n.t('update_none', {version = installed}), 3)
		return
	end
	send_menu('open-menu')
end

local function open_notes()
	local v = pending_version()
	local url = release_url(v)
	if not url then return end
	local args = open_url_args(url)
	if not args then
		msg.warn('Could not open ' .. url .. ': no usable SystemRoot')
		mp.osd_message(i18n.t('update_browser_failed', {url = url}), 10)
		return
	end
	mp.command_native_async({
		name = 'subprocess', args = args, playback_only = false, detach = true,
	}, function(success, result)
		if success and type(result) == 'table' and result.error_string ~= 'init' then
			mp.osd_message(i18n.t('update_opening', {version = v}), 3)
		else
			msg.warn('Could not open ' .. url)
			mp.osd_message(i18n.t('update_browser_failed', {url = url}), 10)
		end
	end)
end

-- Tries each clipboard program in turn; `done(ok)` at the end.
local function copy_with_tools(text, tools, i, done)
	local tool = tools[i]
	if not tool then return done(false) end
	mp.command_native_async({
		name = 'subprocess', args = tool, playback_only = false, stdin_data = text,
		-- Nothing to read from them. This alone does not keep mpv from waiting
		-- for xclip, wl-copy or xsel: they leave a process in the background
		-- and mpv waits for every copy of stdout and stderr to close, captured
		-- or not. clipboard_tools runs them through `sh -c 'exec ... >/dev/null
		-- 2>&1'` for that.
		capture_stdout = false, capture_stderr = false,
	}, function(success, result)
		if success and type(result) == 'table' and result.status == 0 and result.error_string ~= 'init' then
			return done(true)
		end
		msg.verbose('Clipboard: ' .. tool_name(tool) .. ' failed')
		copy_with_tools(text, tools, i + 1, done)
	end)
end

local function copy_command()
	local p = platform()
	local command = update_command(p)
	-- Where the command is pasted: PowerShell on Windows, a terminal elsewhere.
	local shell = p == 'windows' and 'powershell' or 'terminal'
	local function done(ok)
		if ok then
			mp.osd_message(i18n.t('update_copied_' .. shell), 4)
		else
			mp.osd_message(i18n.t('update_copy_failed_' .. shell, {command = command}), 15)
		end
	end
	if mp.set_property('clipboard/text', command) then return done(true) end
	copy_with_tools(command, clipboard_tools(p), 1, done)
end

local function dismiss()
	local v = pending_version()
	if not v then return end
	local fresh = read_state()
	state.last_check = fresh.last_check or state.last_check
	state.dismissed = v
	save_state(state)
	set_button(false)
	mp.commandv('script-message-to', 'uosc', 'close-menu', MENU_TYPE)
	mp.osd_message(i18n.t('update_dismissed', {version = v}), 3)
end

set_button(false)
mp.add_key_binding(nil, 'open-menu', open_menu)
mp.register_script_message('open-notes', open_notes)
mp.register_script_message('copy-command', copy_command)
mp.register_script_message('dismiss', dismiss)
mp.register_event('file-loaded', on_file_loaded)
-- Another language: an open update menu is redrawn in it.
i18n.on_change(function()
	if mp.get_property('user-data/uosc/menu/type') == MENU_TYPE and pending_version() then send_menu('update-menu') end
end)

if HIKARI_UPDATE_TEST then
	return {
		opts = opts, parse_version = parse_version, normalize = normalize, compare_versions = compare_versions,
		is_newer = is_newer, parse_location = parse_location, parse_key_values = parse_key_values,
		installed_version = installed_version, read_state = read_state, state_content = state_content,
		write_file_atomic = write_file_atomic, platform = platform, update_command = update_command,
		release_url = release_url, open_url_args = open_url_args, clipboard_tools = clipboard_tools,
		interval_seconds = interval_seconds, curl_args = curl_args, curl_program = curl_program, in_path = in_path,
		system32 = system32, menu_data = menu_data,
		on_file_loaded = on_file_loaded, open_menu = open_menu, open_notes = open_notes,
		copy_command = copy_command, dismiss = dismiss,
		set_now = function(fn) now = fn end,
		get_state = function() return state end,
		UPDATE_COMMANDS = UPDATE_COMMANDS, AVAILABLE_PROP = AVAILABLE_PROP,
	}
end
