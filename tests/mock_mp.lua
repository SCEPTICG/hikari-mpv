-- Minimal stand-in for mpv's Lua API, enough to load sosc-palettes.lua outside mpv.
local M = {}

M.commands = {}      -- every mp.commandv call, as an array of arguments
M.osd = {}           -- mp.osd_message texts
M.logs = {warn = {}, error = {}, info = {}}
M.bindings = {}      -- name -> function
M.messages = {}      -- script-message name -> function
M.script_opts = {}   -- what mp.options.read_options will see
M.expand = {}        -- path -> expanded path

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
	}
	package.loaded['mp'] = mp
	package.loaded['mp.msg'] = {warn = logger('warn'), error = logger('error'), info = logger('info'),
		verbose = logger('info'), debug = logger('info')}
	package.loaded['mp.utils'] = {format_json = function(v) return format_json(v) end}
	package.loaded['mp.options'] = {
		read_options = function(tbl, identifier)
			for k in pairs(tbl) do
				local v = M.script_opts[identifier .. '-' .. k]
				if v ~= nil then tbl[k] = v end
			end
		end,
	}
end

M.format_json = format_json
return M
