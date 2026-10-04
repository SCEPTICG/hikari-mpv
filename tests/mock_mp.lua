-- Minimal stand-in for mpv's Lua API, enough to load the sosc scripts outside mpv.
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

	local function logger(level) return function(...) table.insert(M.logs[level], table.concat({...}, ' ')) end end

	mp = {
		get_script_name = function() return script_name end,
		commandv = function(...) table.insert(M.commands, {...}) end,
		command_native = function(cmd)
			if cmd[1] == 'expand-path' then return M.expand[cmd[2]] or cmd[2] end
		end,
		osd_message = function(text) table.insert(M.osd, text) end,
		add_key_binding = function(key, name, fn) M.bindings[name] = fn end,
		register_script_message = function(name, fn) M.messages[name] = fn end,
		register_event = function(name, fn) M.events[name] = fn end,
		get_property = function(name, def)
			local v = M.props[name]
			if v == nil then return def end
			return tostring(v)
		end,
		get_property_native = function(name, def)
			local v = M.props[name]
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
			local option = name:match('^file%-local%-options/(.+)$')
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
	package.loaded['mp.utils'] = {format_json = function(v) return format_json(v) end}
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

-- Simulates the end of the current file: file-local options go back.
function M.end_file()
	for option, value in pairs(M.backups) do M.props[option] = value end
	M.backups = {}
end

M.format_json = format_json
return M
