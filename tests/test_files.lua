-- Run from the repository root: lua tests/test_files.lua
local files = assert(loadfile('portable_config/script-modules/hikari-files.lua'))()

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. '\n     ' .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error((what or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
	end
end

local function read(path)
	local file = io.open(path, 'rb')
	if not file then return nil end
	local content = file:read('*a')
	file:close()
	return content
end

local DIR = os.tmpname()
os.remove(DIR)
assert(os.execute('mkdir -p "' .. DIR .. '"'))
local PATH = DIR .. '/hikari-palette.conf'

test('writes a new file and replaces an old one, with no .tmp left', function()
	eq(files.write_file_atomic(PATH, 'palette=nord\n'), true)
	eq(read(PATH), 'palette=nord\n')
	eq(files.write_file_atomic(PATH, 'palette=dracula\n'), true)
	eq(read(PATH), 'palette=dracula\n')
	eq(read(PATH .. '.tmp'), nil, 'no .tmp left')
end)

test('a link planted at the .tmp name is not written through', function()
	local outside = DIR .. '/outside.txt'
	local f = assert(io.open(outside, 'wb'))
	f:write('mine')
	f:close()
	assert(os.execute('ln -s "' .. outside .. '" "' .. PATH .. '.tmp"'))
	eq(files.write_file_atomic(PATH, 'palette=nord\n'), true)
	eq(read(outside), 'mine', 'the link target is untouched')
	eq(read(PATH), 'palette=nord\n')
end)

test('a folder that cannot be written: false and the error, nothing left', function()
	local ok, err = files.write_file_atomic(DIR .. '/missing/x.conf', 'x')
	eq(ok, false)
	assert(type(err) == 'string' and err ~= '', 'an error')
end)

os.execute('rm -rf "' .. DIR .. '"')
print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
