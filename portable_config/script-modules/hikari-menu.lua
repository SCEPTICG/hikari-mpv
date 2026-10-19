-- hikari-menu: hikari's menus, in uosc when it is loaded and in mpv's own
-- selector (mp.input.select, mpv 0.39+) when it is not. A module, not a
-- script: the seven scripts with a menu (hikari-palettes, -language, -subs,
-- -resume, -speed, -update and -upscale) load it and describe each menu once,
-- as uosc takes it.
--
-- Usage:
--   menu.open(data)                    -- uosc's open-menu
--   menu.open(data, {note = 'text'})   -- `note`: a first line, selector only
--   menu.open(data, {silent = true})   -- no OSD message when it cannot open
--   menu.update(data)                  -- uosc's update-menu
--   menu.close('hikari-update')        -- uosc's close-menu
--   menu.is_open('hikari-speed')       -- a menu of that type is open
--   menu.observe(fn)                   -- fn(type or nil) when the open menu changes
--   menu.uosc()                        -- uosc is loaded
--   menu.on_uosc(fn)                   -- fn() when uosc says it has started
--
-- Decisions:
-- - With uosc nothing changes from hikari 0.9.0: the same `script-message-to
--   uosc open-menu / update-menu / close-menu` with the same JSON, and
--   user-data/uosc/menu/type read as before.
-- - Whether uosc is there: uosc 5.13 publishes no property for as long as it
--   runs (user-data/uosc/menu/type only while one of its menus is open, and
--   mpv's own osc.lua writes user-data/osc/margins too). But mpv's
--   `script-message-to` fails when no script has that name (command.c,
--   cmd_script_message_to), and mp.commandv then returns nil. So every
--   open-menu goes to uosc first, and only when that fails does the selector
--   open. Nothing is decided at start-up: menus open on a key or on
--   file-loaded, and mpv creates every script before it plays anything
--   (mp_load_scripts, then mp_play_files waits for them), so a uosc loaded
--   after a hikari script is found all the same.
-- - menu.uosc(), for what is not a menu (uosc's options, in hikari-language):
--   true once a message reached uosc or uosc announced itself (it broadcasts
--   `uosc-version` as it starts, to every script created before it: hikari's,
--   which sort before uosc in scripts/; see on_uosc). Until then it asks
--   again each time with PROBE, a message uosc has no handler for (mpv's Lua
--   drops it).
-- - The selector: one line per item, `title  ·  hint`; the active item
--   marked `• ` and chosen by default, unless selected_index says another.
--   Items that cannot be chosen (selectable = false): headings and notes (no
--   value, no hint) as `— title —`, disabled entries as `(title  ·  hint)`;
--   choosing one does nothing (the menu comes back). Choosing any other item
--   runs its value (a command as a list of arguments, as uosc runs it; any
--   other value is ignored with a warning); with keep_open the menu
--   comes back, with the data of the latest update. uosc's separator, muted,
--   italic, bold and align have no equivalent and are left out. Control
--   characters become spaces (the console cuts a line at a newline).
-- - mpv's console shows one menu at a time and, in 0.39, ignores a request
--   while it is open. So another menu, or the menu on screen in another
--   language, first closes it (input.terminate) and asks again once `closed`
--   comes, never from inside that callback (input.lua drops the handlers right
--   after it). Any other update-menu (continue watching saves every few
--   seconds while the video plays) only keeps the new data for the next time
--   the menu opens: closing it would lose what was typed and the line the
--   cursor is on. The menu comes back after REOPEN_DELAY: the value of the
--   item chosen is usually a message to the script itself, which arrives after
--   `closed`, and the update-menu it causes should make it into the menu that
--   comes back, with the cursor on the line chosen if it can still be chosen.
--   A request with no `opened` (0.39 with the console busy, or the
--   console disabled) is given up after OPEN_TIMEOUT, so the next one is not
--   stuck behind it. mpv 0.40's keep_open is not used: 0.39 and 0.40 work the
--   same way.
-- - Without uosc and without mp.input (mpv before 0.39): a translated OSD
--   message (unless silent) and a warning in the log; open returns false.

local msg = require('mp.msg')
local utils = require('mp.utils')
-- The scripts load hikari-i18n first, with the same loader: this require finds
-- the texts the script already has (see the header of hikari-release.lua).
local i18n = require('hikari-i18n')

local M = {}

local UOSC = 'uosc'
local TYPE_PROP = 'user-data/uosc/menu/type'
local PROBE = 'hikari-probe'
local REOPEN_DELAY = 0.1
local OPEN_TIMEOUT = 2

local unpack = table.unpack or unpack

-- i18n.variant() only follows the option once someone listens: the selector
-- compares it to tell a language switch from any other update.
i18n.on_change(function() end)

local uosc_seen = false
local uosc_callbacks = {}
local observers = {}

-- The selector. `want` is the menu that should be on screen ({type, data,
-- opts}, plus `line`, the line last chosen), `session` the state of our
-- console: nil, 'requested' (no `opened` yet) or 'open'. `shown` is what the
-- last request put on screen: per line, the item it runs (false: nothing),
-- the menu and the language it is in.
local want, session, shown
-- Why the next `closed` comes: we asked for it, or an item was chosen.
local closing, submitted = false, false
local open_timer, reopen_timer
local sync

local function send(message, arg)
	if mp.commandv('script-message-to', UOSC, message, arg) then
		uosc_seen = true
		return true
	end
	return false
end

local function encode(data)
	local json, err = utils.format_json(data)
	if not json then msg.error('Could not build the menu ' .. tostring(data and data.type) .. ': ' .. tostring(err)) end
	return json
end

local function emit(menu_type)
	for _, fn in ipairs(observers) do fn(menu_type) end
end

local function input_api()
	local ok, input = pcall(require, 'mp.input')
	if ok and type(input) == 'table' and type(input.select) == 'function' then return input end
	return nil
end

local function plain(text)
	return (tostring(text or ''):gsub('%c', ' '))
end

local function label(item)
	local text = plain(item.title)
	if item.hint ~= nil and item.hint ~= '' then text = text .. '  ·  ' .. plain(item.hint) end
	return text
end

-- The lines of the selector for a menu, what each line runs (false: nothing)
-- and the line chosen by default.
local function lines_of(data, opts, line)
	local lines, actions = {}, {}
	local selected, active, first
	if opts and opts.note then
		lines[1], actions[1] = '— ' .. plain(opts.note) .. ' —', false
	end
	for i, item in ipairs(type(data.items) == 'table' and data.items or {}) do
		if type(item) == 'table' then
			local n = #lines + 1
			if item.selectable == false then
				if item.value == nil and (item.hint == nil or item.hint == '') then
					lines[n] = '— ' .. plain(item.title) .. ' —'
				else
					lines[n] = '(' .. label(item) .. ')'
				end
				actions[n] = false
			else
				lines[n] = (item.active and '• ' or '') .. label(item)
				actions[n] = item.value ~= nil and item
				if actions[n] then
					first = first or n
					if item.active and not active then active = n end
					if i == data.selected_index then selected = n end
				end
			end
		end
	end
	return lines, actions, (line and actions[line] and line) or selected or active or first or 1
end

local function run(value)
	if type(value) ~= 'table' then
		msg.warn('Ignoring a menu value that is not a command list')
		return
	end
	mp.commandv(unpack(value))
end

local function stop_open_timer()
	if open_timer then open_timer:kill() end
	open_timer = nil
end

-- The menu is no longer wanted: off the screen, and observers told.
local function drop()
	if not want then return end
	want = nil
	emit(nil)
	sync()
end

local function on_opened()
	stop_open_timer()
	session = 'open'
	sync()
end

local function on_submit(index)
	submitted = true
	local line = tonumber(index)
	local menu = shown and shown.menu
	if menu then menu.line = line end
	local item = shown and shown.actions[line]
	if not item then return end
	run(item.value)
	if want == menu and not menu.data.keep_open then drop() end
end

local function on_closed()
	stop_open_timer()
	local ours = closing or submitted
	session, closing, submitted = nil, false, false
	-- Esc, a click outside, or another script's input took the console.
	if not ours then drop() end
	if want and not reopen_timer then
		reopen_timer = mp.add_timeout(REOPEN_DELAY, function()
			reopen_timer = nil
			sync()
		end)
	end
end

local function on_open_timeout()
	open_timer = nil
	if session ~= 'requested' then return end
	session = nil
	msg.warn('The menu did not open: mpv\'s console is busy or disabled')
	drop()
end

local function request(input)
	local lines, actions, default = lines_of(want.data, want.opts, want.line)
	shown = {actions = actions, menu = want, variant = i18n.variant()}
	session = 'requested'
	open_timer = mp.add_timeout(OPEN_TIMEOUT, on_open_timeout)
	local title = plain(want.data.title)
	input.select({
		prompt = title ~= '' and title .. ':' or nil, items = lines, default_item = default,
		submit = on_submit, opened = on_opened, closed = on_closed,
	})
end

-- Brings the console in line with `want`: closes what is out of date, asks
-- for what is missing. A request waits for `opened`, a close for `closed`.
sync = function()
	local input = input_api()
	if not input then return end
	if session == 'open' then
		-- After a submit the console closes by itself.
		local stale = not want or want ~= shown.menu or i18n.variant() ~= shown.variant
		if stale and not closing and not submitted then
			closing = true
			input.terminate()
		end
	elseif session == nil and want and not reopen_timer then
		request(input)
	end
end

local function open_select(data, opts)
	local changed = not want or want.type ~= data.type
	want = {type = data.type, data = data, opts = opts}
	if changed then emit(data.type) end
	sync()
end

-- Opens a menu (`data` as uosc's open-menu takes it). Returns false when it
-- could not.
function M.open(data, opts)
	local json = encode(data)
	if not json then return false end
	if send('open-menu', json) then return true end
	if not input_api() then
		msg.warn('Menu ' .. plain(data.type) .. ': uosc is not loaded and mpv has no mp.input.select (0.39+)')
		if not (opts and opts.silent) then mp.osd_message(i18n.t('menu_needs_uosc'), 4) end
		return false
	end
	open_select(data, opts)
	return true
end

-- New data for a menu that may be open (uosc's update-menu). `opts` as for
-- open; the last ones stay when not given. The selector only shows it at
-- once after a language switch (see the header).
function M.update(data, opts)
	if want and want.type == data.type then
		want.data, want.opts = data, opts or want.opts
		sync()
		return
	end
	local json = encode(data)
	if json then send('update-menu', json) end
end

function M.close(menu_type)
	if want and want.type == menu_type then
		drop()
		return
	end
	send('close-menu', menu_type)
end

function M.is_open(menu_type)
	return mp.get_property_native(TYPE_PROP) == menu_type or (want ~= nil and want.type == menu_type)
end

-- fn(type or nil) whenever the open menu changes, uosc's or the selector's.
function M.observe(fn)
	observers[#observers + 1] = fn
	if #observers == 1 then
		mp.observe_property(TYPE_PROP, 'native', function(_, value) emit(value) end)
	end
end

function M.uosc()
	if not uosc_seen and mp.commandv('script-message-to', UOSC, PROBE) then uosc_seen = true end
	return uosc_seen
end

-- fn() when uosc broadcasts `uosc-version` as it starts.
function M.on_uosc(fn)
	uosc_callbacks[#uosc_callbacks + 1] = fn
	if #uosc_callbacks == 1 then
		mp.register_script_message('uosc-version', function()
			uosc_seen = true
			for _, callback in ipairs(uosc_callbacks) do callback() end
		end)
	end
end

M.REOPEN_DELAY, M.OPEN_TIMEOUT = REOPEN_DELAY, OPEN_TIMEOUT
M.lines_of = lines_of

return M
