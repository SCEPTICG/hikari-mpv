-- Minimal stand-in for mpv's Lua API, enough to load the hikari scripts outside mpv.
local M = {}

M.commands = {}      -- every mp.commandv call, as an array of arguments
M.osd = {}           -- mp.osd_message texts
M.logs = {warn = {}, error = {}, info = {}}
M.bindings = {}      -- name -> function
M.messages = {}      -- script-message name -> function
M.script_opts = {}   -- what mp.options.read_options will see
M.expand = {}        -- path -> expanded path
M.props = {}         -- property name -> value
M.events = {}        -- event name -> function
M.backups = {}       -- option name -> value saved by file-local-options/<name>
M.observers = {}     -- property name -> array of callbacks (mp.observe_property)
M.overlays = {}      -- every mp.create_osd_overlay object, in creation order
M.sections = {}      -- input section name -> {bindings, flags, enabled, enable_flags}
M.clock = 0          -- what mp.get_time returns; move it with M.advance
M.timers = {}        -- pending mp.add_timeout timers
M.native_sets = {}   -- every mp.set_property_native call, as {name, value}
M.async = {}         -- pending mp.command_native_async calls, as {cmd, cb}; see M.finish_async
M.set_fails = {}     -- property name -> true: mp.set_property fails for it
M.files = {}        -- path -> mp.utils.file_info answer (nil: the file does not exist)
M.config_files = {} -- name -> path that mp.find_config_file returns (nil: not found)
M.sets = {}         -- every mp.set_property call, as {name, value}
-- Tracks, for the tests that need mpv's track selection: when M.tracks is a
-- list (the track-list entries, as get_property_native gives them), the
-- `aid`/`sid` properties and options behave as in mpv: setting `aid` (or
-- `file-local-options/aid`) to a track id sets the option `options/aid` to
-- it and plays that track, `no` plays none, and `auto` lets M.pick(property)
-- choose (mpv's own choice; false for none). The file-local form is put back
-- by M.end_file().
M.tracks = nil
M.pick = nil
-- Choice options whose choices include yes and no: like mpv, set_property
-- stores those two as flags, so get_property_native gives true/false.
M.flag_choices = {['subs-with-matching-audio'] = true}

local function json_string(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r'}
		return map[c] or string.format('\\u%04x', c:byte())
	end) .. '"'
end

-- Tiny JSON encoder: sequential tables become arrays, others objects with sorted keys.
local function format_json(value)
	local t = type(value)
	if t == 'string' then return json_string(value)
	elseif t == 'number' or t == 'boolean' then return tostring(value)
	elseif t == 'nil' then return 'null'
	elseif t == 'table' then
		local out = {}
		if #value > 0 then
			for _, v in ipairs(value) do out[#out + 1] = format_json(v) end
			return '[' .. table.concat(out, ',') .. ']'
		end
		local keys = {}
		for k in pairs(value) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do out[#out + 1] = json_string(k) .. ':' .. format_json(value[k]) end
		return '{' .. table.concat(out, ',') .. '}'
	end
	error('cannot encode ' .. t)
end

function M.install(script_name)
	M.commands, M.osd = {}, {}
	M.logs = {warn = {}, error = {}, info = {}}
	M.bindings, M.messages = {}, {}
	M.props, M.events, M.backups = {}, {}, {}
	M.observers, M.overlays, M.sections = {}, {}, {}
	M.clock, M.timers = 0, {}
	M.native_sets = {}
	M.async, M.set_fails, M.files = {}, {}, {}
	M.config_files = {}
	M.sets = {}
	M.tracks, M.pick = nil, nil
	-- The shared texts module is per script in mpv (one Lua state each): load it
	-- again for every script the tests load, from the repository.
	package.loaded['hikari-i18n'] = nil
	M.expand['~~/script-modules'] = M.expand['~~/script-modules'] or 'portable_config/script-modules'

	local function logger(level) return function(...) table.insert(M.logs[level], table.concat({...}, ' ')) end end

	mp = {
		get_script_name = function() return script_name end,
		commandv = function(...) table.insert(M.commands, {...}) end,
		command_native = function(cmd)
			if cmd[1] == 'expand-path' then return M.expand[cmd[2]] or cmd[2] end
		end,
		-- Kept until the test answers it with M.finish_async.
		command_native_async = function(cmd, cb)
			table.insert(M.async, {cmd = cmd, cb = cb or function() end})
			return #M.async
		end,
		osd_message = function(text) table.insert(M.osd, text) end,
		add_key_binding = function(key, name, fn) M.bindings[name] = fn end,
		register_script_message = function(name, fn) M.messages[name] = fn end,
		register_event = function(name, fn) M.events[name] = fn end,
		-- Like mpv: user-data/ holds nodes, and get_property formats a string node
		-- as JSON, quotes included ("hikari-language"). Only get_property_native
		-- gives the bare string back. Flags read as yes/no, string lists as the
		-- items joined with commas.
		get_property = function(name, def)
			local v = M.props[name]
			if v == nil then return def end
			if type(v) == 'string' and name:sub(1, 10) == 'user-data/' then return '"' .. v .. '"' end
			if type(v) == 'boolean' then return v and 'yes' or 'no' end
			if type(v) == 'table' then return table.concat(v, ',') end
			return tostring(v)
		end,
		get_time = function() return M.clock end,
		find_config_file = function(name) return M.config_files[name] end,
		add_timeout = function(seconds, fn)
			local timer = {due = M.clock + seconds, fn = fn, active = true}
			function timer:kill() self.active = false end
			table.insert(M.timers, timer)
			return timer
		end,
		set_property_native = function(name, value)
			table.insert(M.native_sets, {name, value})
			M.props[name] = value
			return true
		end,
		get_property_native = function(name, def)
			if name == 'track-list' and M.tracks then return M.tracks end
			local v = M.props[name]
			-- What the scripts' options come from: M.script_opts unless a test set it.
			if v == nil and name == 'options/script-opts' then v = M.script_opts end
			if v == nil then return def end
			return v
		end,
		observe_property = function(name, kind, fn)
			M.observers[name] = M.observers[name] or {}
			table.insert(M.observers[name], fn)
		end,
		unobserve_property = function(fn)
			for _, list in pairs(M.observers) do
				for i = #list, 1, -1 do
					if list[i] == fn then table.remove(list, i) end
				end
			end
		end,
		-- Overlays keep what the script sent: `updates` counts update() calls,
		-- `visible` is false after remove().
		create_osd_overlay = function(format)
			local overlay = {format = format, data = '', res_x = 0, res_y = 0, updates = 0, removes = 0, visible = false}
			function overlay:update() self.updates = self.updates + 1; self.visible = true end
			function overlay:remove() self.removes = self.removes + 1; self.visible = false end
			table.insert(M.overlays, overlay)
			return overlay
		end,
		-- Input sections as in mpv's defaults.lua: entries are {key, cb_up, cb_down}
		-- or {key, 'command'}.
		set_key_bindings = function(list, section, flags)
			M.sections[section] = {bindings = list, flags = flags, enabled = false}
		end,
		enable_key_bindings = function(section, flags)
			local s = M.sections[section]
			s.enabled, s.enable_flags = true, flags
			s.enables = (s.enables or 0) + 1
		end,
		disable_key_bindings = function(section)
			M.sections[section].enabled = false
		end,
		get_property_number = function(name, def)
			local v = tonumber(M.props[name])
			if v == nil then return def end
			return v
		end,
		-- Like mpv: file-local-options/<name> sets <name> and remembers the old
		-- value, which end_file() puts back.
		set_property = function(name, value)
			table.insert(M.sets, {name, value})
			if M.set_fails[name] then return nil, 'property unavailable' end
			if M.flag_choices[name] and (value == 'yes' or value == 'no') then value = value == 'yes' end
			local option = name:match('^file%-local%-options/(.+)$')
			local track_property = option or name
			if M.tracks and (track_property == 'aid' or track_property == 'sid') then
				local key = 'options/' .. track_property
				if option and M.backups[key] == nil then M.backups[key] = M.props[key] end
				if value == 'auto' then
					M.props[key] = 'auto'
					M.props[track_property] = M.pick and M.pick(track_property) or false
				elseif value == 'no' then
					M.props[key], M.props[track_property] = false, false
				else
					M.props[key] = tonumber(value)
					M.props[track_property] = tonumber(value)
				end
				return true
			end
			if option then
				if M.backups[option] == nil then M.backups[option] = M.props[option] or '' end
				name = option
			end
			M.props[name] = value
			return true
		end,
	}
	package.loaded['mp'] = mp
	package.loaded['mp.msg'] = {warn = logger('warn'), error = logger('error'), info = logger('info'),
		verbose = logger('info'), debug = logger('info')}
	package.loaded['mp.utils'] = {
		format_json = function(v) return format_json(v) end,
		file_info = function(path) return M.files[path] end,
	}
	package.loaded['mp.options'] = {
		read_options = function(tbl, identifier)
			for k, default in pairs(tbl) do
				local v = M.script_opts[identifier .. '-' .. k]
				if v ~= nil and type(default) == 'boolean' then v = v == 'yes' end
				if v ~= nil then tbl[k] = v end
			end
		end,
	}
end

-- Sets a property and notifies its observers, like mpv does on a change.
function M.set(name, value)
	M.props[name] = value
	local list = M.observers[name]
	if not list then return end
	local copy = {}
	for i, fn in ipairs(list) do copy[i] = fn end
	for _, fn in ipairs(copy) do fn(name, value) end
end

-- Changes one script option at run time (as `change-list script-opts append`
-- does) and notifies the observers of options/script-opts.
function M.set_script_opt(key, value)
	local copy = {}
	for k, v in pairs(M.script_opts) do copy[k] = v end
	copy[key] = value
	M.script_opts = copy
	M.props['options/script-opts'] = nil
	local list = M.observers['options/script-opts']
	if not list then return end
	local fns = {}
	for i, fn in ipairs(list) do fns[i] = fn end
	for _, fn in ipairs(fns) do fn('options/script-opts', copy) end
end

-- Moves the clock forward and fires the timers that fall due, in order.
function M.advance(seconds)
	M.clock = M.clock + seconds
	table.sort(M.timers, function(a, b) return a.due < b.due end)
	local pending = {}
	for _, timer in ipairs(M.timers) do
		if timer.active and timer.due <= M.clock then
			timer.active = false
			timer.fn()
		elseif timer.active then
			pending[#pending + 1] = timer
		end
	end
	M.timers = pending
end

-- Answers the oldest pending mp.command_native_async call as mpv would:
-- finish_async(true, {status = 0, stdout = '...'}) or finish_async(false, nil, 'error').
-- Returns the command it answered.
function M.finish_async(success, result, err)
	local call = table.remove(M.async, 1)
	assert(call, 'no pending async command')
	call.cb(success, result, err)
	return call.cmd
end

-- Simulates the end of the current file: file-local options go back.
function M.end_file()
	for option, value in pairs(M.backups) do M.props[option] = value end
	M.backups = {}
end

M.format_json = format_json
return M
