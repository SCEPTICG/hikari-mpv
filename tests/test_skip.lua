-- Run from the repository root: lua tests/test_skip.lua
package.path = './tests/?.lua;' .. package.path
local mock = require('mock_mp')

local SCRIPT = 'portable_config/scripts/hikari-skip.lua'
local SCRIPT_NAME = 'hikari_skip'

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

-- Loads the script with fresh mocks; `opts` are the script-opts mpv would pass.
local function load(opts)
	mock.install(SCRIPT_NAME)
	mock.script_opts = opts or {}
	-- The assertions below are in Spanish: unless a test says otherwise, hikari speaks Spanish.
	if mock.script_opts['hikari-language'] == nil then mock.script_opts['hikari-language'] = 'es' end
	HIKARI_SKIP_TEST = true
	local chunk = assert(loadfile(SCRIPT))
	return chunk()
end

local function chapters(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = {time = c[1], title = c[2]} end
	return out
end

-- A typical episode: cold open, OP, part A, ED, preview.
local EPISODE = chapters({
	{0, 'Cold open'}, {90, 'Opening'}, {180, 'Part A'}, {1300, 'Ending'}, {1390, 'Preview'},
})

-- Loads the script with a 1280x720 OSD and an episode loaded at `time`.
local function play(time, list, opts)
	local s = load(opts)
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('duration', 1420)
	mock.set('chapter-list', list or EPISODE)
	mock.set('time-pos', time)
	return s
end

local function overlay(s) return s.overlay end
local function section(s) return mock.sections[s.MOUSE_SECTION] end
local function center(rect) return {x = (rect.x0 + rect.x1) / 2, y = (rect.y0 + rect.y1) / 2, hover = true} end

-- Classification ----------------------------------------------------------------

test('openings and endings are recognised like uosc (plus Japanese)', function()
	local s = load()
	for _, title in ipairs({'OP', 'op', 'Opening', '  OPENING  ', 'OP Theme', 'Episode 1 OP',
		'Main Opening', 'オープニング', 'オープニングテーマ'}) do
		local kind = s.classify(title)
		eq(kind and kind.name, 'openings', title)
	end
	for _, title in ipairs({'ED', 'ed', 'Ending', 'ENDING', 'Ending Theme', 'ED 1', 'Episode 1 ED',
		'Main Ending', 'エンディング', 'Credits', 'CREDITS', 'End Credits', 'Credits Roll'}) do
		local kind = s.classify(title)
		eq(kind and kind.name, 'endings', title)
	end
end)

test('lookalike titles are not openings or endings', function()
	local s = load()
	for _, title in ipairs({'Operation', 'Opening Night Part', 'Openings', 'OP1', 'Top', 'Edward',
		'Edge', 'Bed', 'Endings', 'Pending', 'The End', 'Part A', '', 'Chapter 1',
		'Credit', 'Discredits', 'Creditscene'}) do
		eq(s.classify(title), nil, title)
	end
	eq(s.classify(nil), nil, 'nil title')
	eq(s.classify(42), nil, 'number title')
end)

test('intros are on and outros off by default', function()
	local s = load()
	for _, title in ipairs({'Intro', 'Avant', 'Prologue'}) do
		eq(s.classify(title).name, 'intros', title)
	end
	for _, title in ipairs({'Outro', 'Closing', 'Preview', 'PV'}) do
		eq(s.classify(title), nil, title)
	end
	s = load({['hikari-skip-intros'] = 'no'})
	eq(s.classify('Intro'), nil, 'intros=no')
end)

test('intros and outros can be enabled, openings and endings disabled', function()
	local s = load({['hikari-skip-intros'] = 'yes', ['hikari-skip-outros'] = 'yes',
		['hikari-skip-openings'] = 'no', ['hikari-skip-endings'] = 'no'})
	for _, title in ipairs({'Intro', 'Cold intro', 'Avant', 'Prologue'}) do
		eq(s.classify(title).name, 'intros', title)
	end
	for _, title in ipairs({'Outro', 'Closing', 'Closing Credits', 'Preview', 'PV'}) do
		eq(s.classify(title).name, 'outros', title)
	end
	eq(s.classify('OP'), nil, 'openings disabled')
	eq(s.classify('Ending'), nil, 'endings disabled')
	local i18n = dofile('portable_config/script-modules/hikari-i18n.lua')
	eq(i18n.t(s.classify('Intro').label), 'Saltar intro ›')
	eq(i18n.t(s.classify('Preview').label), 'Saltar avance ›')
end)

test('extra patterns are added; malformed ones are ignored safely', function()
	local s = load({['hikari-skip-extra_openings'] = '^op%d+$|^opening %d+$|[',
		['hikari-skip-extra_endings'] = '^credits$'})
	eq(s.classify('OP1').name, 'openings')
	eq(s.classify('Opening 2').name, 'openings')
	eq(s.classify('Credits').name, 'endings')
	eq(s.classify('Part A'), nil, 'malformed pattern does not match or crash')
end)

test('very long titles are cut before matching', function()
	local s = load()
	eq(s.classify(string.rep('a', 500) .. ' op'), nil, 'match past the cut')
	eq(s.classify('OP ' .. string.rep('x', 500)).name, 'openings')
end)

-- Ranges ------------------------------------------------------------------------

test('ranges: opening to next chapter, ending to next chapter', function()
	local s = load()
	local ranges = s.build_ranges(EPISODE, 1420)
	eq(#ranges, 2)
	eq(ranges[1].kind.name, 'openings'); eq(ranges[1].start, 90); eq(ranges[1].finish, 180)
	eq(ranges[1].next_time, 180)
	eq(ranges[2].kind.name, 'endings'); eq(ranges[2].start, 1300); eq(ranges[2].finish, 1390)
end)

test('an opening as last chapter does not count; an ending does', function()
	local s = load()
	eq(#s.build_ranges(chapters({{0, 'Part A'}, {500, 'OP'}}), 600), 0, 'last opening')
	local ranges = s.build_ranges(chapters({{0, 'Part A'}, {500, 'ED'}}), 600)
	eq(#ranges, 1)
	eq(ranges[1].finish, 600, 'ends at duration'); eq(ranges[1].next_time, nil)
	eq(s.build_ranges(chapters({{0, 'Part A'}, {500, 'ED'}}), nil)[1].finish, math.huge, 'unknown duration')
end)

test('chapters out of order are sorted; junk entries are skipped', function()
	local s = load()
	local list = {{time = 180, title = 'Part A'}, {time = 90, title = 'OP'}, {title = 'no time'},
		'junk', {time = 0 / 0, title = 'NaN'}, {time = 0, title = 'Cold open'}}
	local ranges = s.build_ranges(list, 1000)
	eq(#ranges, 1); eq(ranges[1].start, 90); eq(ranges[1].finish, 180)
	eq(#s.build_ranges(nil, 100), 0); eq(#s.build_ranges('x', 100), 0)
end)

test('current range by time, with its edges', function()
	local s = load()
	local ranges = s.build_ranges(EPISODE, 1420)
	eq(s.range_at(ranges, 89.9), nil, 'before')
	eq(s.range_at(ranges, 90), 1, 'start edge')
	eq(s.range_at(ranges, 150), 1, 'inside')
	eq(s.range_at(ranges, 180 - s.END_MARGIN - 0.01), 1, 'just before the end margin')
	eq(s.range_at(ranges, 180 - s.END_MARGIN), nil, 'end margin')
	eq(s.range_at(ranges, 180), nil, 'next chapter')
	eq(s.range_at(ranges, 1350), 2, 'ending')
	eq(s.range_at(ranges, nil), nil, 'no time')
end)

-- Visibility and drawing --------------------------------------------------------

test('without chapters nothing is drawn and time-pos is not observed', function()
	local s = load()
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('chapter-list', {})
	eq(mock.observers['time-pos'] == nil or #mock.observers['time-pos'] == 0, true, 'no time-pos observer')
	mock.set('chapter-list', chapters({{0, 'A'}, {100, 'B'}}))
	eq(mock.observers['time-pos'] == nil or #mock.observers['time-pos'] == 0, true, 'none either')
	eq(overlay(s).updates, 0)
end)

test('the button is visible only inside the range', function()
	local s = play(10)
	eq(s.is_visible(), false, 'before'); eq(overlay(s).updates, 0)
	mock.set('time-pos', 95)
	eq(s.is_visible(), true, 'inside'); eq(overlay(s).visible, true)
	assert(overlay(s).data:find('Saltar opening ›', 1, true), 'opening label')
	eq(overlay(s).res_x, 1280); eq(overlay(s).res_y, 720)
	mock.set('time-pos', 200)
	eq(s.is_visible(), false, 'after'); eq(overlay(s).visible, false)
	mock.set('time-pos', 1310)
	assert(overlay(s).data:find('Saltar ending ›', 1, true), 'ending label')
end)

test('no redraw on every time-pos inside the range', function()
	local s = play(95)
	local updates = overlay(s).updates
	for t = 96, 170 do mock.set('time-pos', t) end
	eq(overlay(s).updates, updates, 'same range, no redraw')
	mock.set('time-pos', 300)
	mock.set('time-pos', 301)
	eq(overlay(s).removes, 1, 'removed once')
end)

test('stays visible when paused, hides when idle or a menu is open', function()
	local s = play(95)
	mock.set('pause', true)
	eq(s.is_visible(), true, 'paused')
	mock.set('user-data/uosc/menu/type', 'hikari-speed')
	eq(s.is_visible(), false, 'uosc menu'); eq(overlay(s).visible, false)
	mock.set('user-data/uosc/menu/type', nil)
	eq(s.is_visible(), true, 'menu closed'); eq(overlay(s).visible, true)
	mock.set('user-data/mpv/console/open', true)
	eq(s.is_visible(), false, 'console')
	mock.set('user-data/mpv/console/open', false)
	mock.set('idle-active', true)
	eq(s.is_visible(), false, 'idle')
end)

test('layout sits above uosc bar at the bottom right and scales', function()
	local s = play(95)
	local r = s.layout()
	eq(r.x1, 1280 - 16); eq(r.y1, 720 - 96)
	assert(r.x0 < r.x1 and r.y0 < r.y1, 'non-empty')
	assert(720 - r.y1 > 81, 'clears uosc default timeline + controls (81 px)')
	mock.set('fullscreen', true)
	local f = s.layout()
	eq(f.x1, 1280 - math.floor(16 * 1.3 + 0.5)); eq(f.y1, 720 - math.floor(96 * 1.3 + 0.5))
	assert(f.font_size > r.font_size, 'bigger in fullscreen')
	mock.set('fullscreen', false)
	mock.set('display-hidpi-scale', 2)
	eq(s.layout().y1, 720 - 192, 'hidpi')
	mock.set('osd-dimensions', {w = 1920, h = 1080})
	eq(overlay(s).res_x, 1920, 'redrawn for new size')
end)

test('margins are configurable', function()
	local s = play(95, nil, {['hikari-skip-margin_bottom'] = '150', ['hikari-skip-margin_right'] = '40'})
	local r = s.layout()
	eq(r.x1, 1280 - 40); eq(r.y1, 720 - 150)
end)

-- suji ----------------------------------------------------------------------------

test('hides while a menu of suji is open, as with uosc', function()
	local s = play(95)
	mock.set('user-data/suji/menu/type', 'hikari-speed')
	eq(s.is_visible(), false, 'suji menu'); eq(overlay(s).visible, false)
	mock.set('user-data/suji/menu/type', nil)
	eq(s.is_visible(), true, 'menu closed'); eq(overlay(s).visible, true)
	-- One of each: hidden until both close.
	mock.set('user-data/suji/menu/type', 'suji-more')
	mock.set('user-data/uosc/menu/type', 'hikari-speed')
	mock.set('user-data/uosc/menu/type', nil)
	eq(s.is_visible(), false, 'suji still has one')
	mock.set('user-data/suji/menu/type', nil)
	eq(s.is_visible(), true)
end)

test('with suji: above the height it publishes plus a 15 px gap times the scale; margin_bottom does not count', function()
	local s = play(95, nil, {['hikari-skip-margin_bottom'] = '150'})
	mock.set('user-data/suji/margins', {bottom = 62})
	local r = s.layout()
	eq(r.y1, 720 - 62 - 15)
	eq(r.x1, 1280 - 16, 'margin_right as before')
	eq(overlay(s).visible, true)
	-- suji's height already has its scale; the gap takes this script's.
	mock.set('fullscreen', true)
	eq(s.layout().y1, 720 - 62 - math.floor(15 * 1.3 + 0.5))
	mock.set('fullscreen', false)
	mock.set('display-hidpi-scale', 2)
	mock.set('user-data/suji/margins', {bottom = 124})
	eq(s.layout().y1, 720 - 124 - 30, 'hidpi')
	mock.set('user-data/suji/margins', {bottom = 62.4})
	eq(s.layout().y1, 720 - 62 - 30, 'rounded')
end)

test('with suji: no height, 0 or junk: margin_bottom, as before', function()
	local s = play(95)
	mock.set('user-data/suji/margins', {bottom = 62})
	eq(s.layout().y1, 720 - 77)
	for _, margins in ipairs({false, {bottom = 0}, {bottom = -5}, {bottom = 'abc'}, {}, 'x', {bottom = 0 / 0}}) do
		mock.set('user-data/suji/margins', margins or nil)
		eq(s.layout().y1, 720 - 96, 'margins ' .. tostring(margins))
	end
	mock.set('user-data/suji/margins', {bottom = 1e999})
	eq(s.layout().y1, 720 - 10000 - 15, 'bounded')
end)

-- suji's action button (suji 0.3.0 or newer) --------------------------------------

-- The show-action and hide-action messages sent to suji, in order.
local function actions()
	local out = {}
	for _, c in ipairs(mock.commands) do
		if c[1] == 'script-message-to' and c[2] == 'suji' and (c[3] == 'show-action' or c[3] == 'hide-action') then
			out[#out + 1] = c
		end
	end
	return out
end

-- suji as it starts: on, and its version sent to the scripts already running.
local function suji(version)
	mock.suji = true
	mock.set('user-data/suji/enabled', true)
	mock.messages['suji-version'](version)
end

-- A show-action, checked: id, label and a command back to this script.
local function shown(c, label)
	eq(c[3], 'show-action'); eq(c[4], 'hikari-skip', 'id')
	local data = mock.parse_json(c[5])
	eq(data.text, label, 'text')
	eq(#data.command, 3, 'command length')
	eq(data.command[1], 'script-message-to'); eq(data.command[2], SCRIPT_NAME); eq(data.command[3], 'skip-action')
	return data
end

test('suji 0.3.0: show-action with the label and a command back, nothing drawn here', function()
	local s = play(95)
	eq(overlay(s).visible, true, 'ours before suji')
	suji('0.3.0')
	local list = actions()
	eq(#list, 1)
	shown(list[1], 'Saltar opening ›')
	eq(overlay(s).visible, false, 'our overlay is gone')
	eq(s.layout(), nil)
	mock.set('mouse-pos', {x = 1200, y = 610, hover = true})
	eq(section(s).enabled, false, 'no click section')
	-- Nothing new while nothing changes.
	mock.set('time-pos', 100)
	mock.set('osd-dimensions', {w = 1920, h = 1080})
	eq(#actions(), 1, 'no resend')
	eq(overlay(s).updates, 1, 'drawn once, before suji')
end)

test('suji 0.3.0: in a range from the start, no overlay at all', function()
	local s = load()
	suji('0.3.0')
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('duration', 1420)
	mock.set('chapter-list', EPISODE)
	mock.set('time-pos', 95)
	eq(overlay(s).updates, 0, 'never drawn')
	eq(#actions(), 1); shown(actions()[1], 'Saltar opening ›')
end)

test('suji 0.3.0: hide-action when the range ends, and after the skip', function()
	local s = play(95)
	suji('0.3.0')
	mock.set('time-pos', 179.9)
	local list = actions()
	eq(#list, 2, 'range over')
	eq(list[2][3], 'hide-action'); eq(list[2][4], 'hikari-skip'); eq(list[2][5], nil)
	-- Into the ending: a new show-action with its label.
	mock.set('time-pos', 1310)
	shown(actions()[3], 'Saltar ending ›')
	mock.bindings.skip()
	list = actions()
	eq(#list, 4); eq(list[4][3], 'hide-action', 'after the skip')
	eq(overlay(s).updates, 1, 'never drawn here since suji')
end)

test('suji 0.3.0: the command skips like a click; nothing when no button of ours is up', function()
	local s = play(95)
	suji('0.3.0')
	mock.commands = {}
	mock.messages['skip-action']()
	eq(mock.commands[1][1], 'seek'); eq(mock.commands[1][2], '180.000'); eq(mock.commands[1][3], 'absolute+exact')
	eq(mock.commands[2][3], 'hide-action', 'then hidden')
	eq(s.guard_active(), false, 'no guard of ours: suji has its own')
	eq(section(s).enabled, false)
	-- A second, late message (or one by hand): no button, nothing.
	mock.commands = {}
	mock.messages['skip-action']()
	eq(#mock.commands, 0)
	mock.set('time-pos', 500)
	mock.messages['skip-action']()
	eq(#mock.commands, 0, 'outside a range')
end)

test('suji 0.3.0: the command skips while the console hides our own button; the key keeps its rule', function()
	local s = play(95)
	suji('0.3.0')
	mock.set('user-data/mpv/console/open', true)
	eq(#actions(), 1, 'still up: suji decides')
	mock.commands = {}
	mock.messages['skip-action']()
	eq(mock.commands[1][1], 'seek')
	mock.set('time-pos', 1310)
	mock.commands = {}
	mock.bindings.skip()
	eq(#mock.commands, 0, 'key: not while the console is open')
	eq(s.is_visible(), false)
end)

test('suji 0.3.0: a new label is a new show-action (language, next episode)', function()
	play(95)
	suji('0.3.0')
	mock.set_script_opt('hikari-language', 'en')
	eq(#actions(), 2); shown(actions()[2], 'Skip opening ›')
	mock.set_script_opt('hikari-language', 'en')
	eq(#actions(), 2, 'same label: nothing')
	-- A last-chapter ending, then the next episode queued.
	local s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	suji('0.3.0')
	shown(actions()[1], 'Saltar ending ›')
	mock.props['path'] = '/anime/ep01.mkv'
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 2
	mock.props['playlist/1/filename'] = '/anime/ep02.mkv'
	mock.set(s.NEXT_PROP, {path = '/anime/ep01.mkv', next = '/anime/ep02.mkv'})
	eq(#actions(), 2); shown(actions()[2], 'Siguiente episodio ›')
end)

test('suji 0.3.0: turned off, ours again; turned on, show-action again', function()
	local s = play(95)
	suji('0.3.0')
	mock.set('user-data/suji/enabled', false)
	eq(overlay(s).visible, true, 'ours while suji is off')
	local n = #actions()
	mock.set('user-data/suji/enabled', true)
	eq(overlay(s).visible, false, 'suji again')
	eq(#actions(), n + 1); shown(actions()[n + 1], 'Saltar opening ›')
	-- suji gone (the property is deleted when mpv quits).
	mock.set('user-data/suji/enabled', nil)
	eq(overlay(s).visible, true, 'ours when suji is gone')
	-- Turned on outside a range: nothing to show.
	mock.set('time-pos', 500)
	n = #actions()
	mock.set('user-data/suji/enabled', true)
	eq(#actions(), n, 'no button wanted')
end)

test('suji 0.3.0: a new file drops the button; the next one in a range gets it again', function()
	local s = play(95)
	suji('0.3.0')
	mock.events['end-file']()
	eq(actions()[2][3], 'hide-action')
	mock.set('duration', 1420)
	mock.set('chapter-list', EPISODE)
	mock.set('time-pos', 95)
	eq(#actions(), 3); shown(actions()[3], 'Saltar opening ›')
	eq(overlay(s).updates, 1)
end)

test('suji 0.2.x or an unknown version: our own button, as before', function()
	for _, version in ipairs({'0.2.1', '0.2.9', '0.1.0', 'abc', ''}) do
		local s = play(95)
		mock.set('user-data/suji/margins', {bottom = 62})
		suji(version)
		eq(#actions(), 0, version)
		eq(overlay(s).visible, true, version)
		eq(s.layout().y1, 720 - 62 - 15, 'above suji, as before')
	end
	-- suji loaded before this script: no suji-version arrives.
	local s = play(95)
	mock.suji = true
	mock.set('user-data/suji/enabled', true)
	eq(#actions(), 0, 'no version known')
	eq(overlay(s).visible, true)
	-- Newer versions count.
	for _, version in ipairs({'0.3.0', '0.3.1-dev', '0.10.0', '1.0.0'}) do
		play(95)
		suji(version)
		eq(#actions(), 1, version)
	end
end)

test('without suji: nothing is sent to it, our own button as before', function()
	local s = play(95)
	eq(#actions(), 0)
	eq(overlay(s).visible, true)
	mock.set('time-pos', 500)
	eq(#actions(), 0)
	eq(overlay(s).visible, false)
end)

-- Colours -----------------------------------------------------------------------

test('colours come from uosc-color in BGR, with defaults', function()
	local s = load()
	local c = s.parse_colors({['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12,background=112233,background_text=e6edf3'})
	eq(c.foreground, '5ad4e6'); eq(c.background, '112233')
	eq(s.to_bgr('112233'), '332211'); eq(s.to_bgr('5ad4e6'), 'E6D45A')
	local d = s.parse_colors({})
	eq(d.foreground, 'ffffff'); eq(d.background, '000000')
	local bad = s.parse_colors({['uosc-color'] = 'foreground=zzzzzz,background=#ABCDEF,evil=000000'})
	eq(bad.foreground, 'ffffff', 'malformed ignored'); eq(bad.background, 'abcdef'); eq(bad.evil, nil)
	eq(s.parse_colors(nil).foreground, 'ffffff')
	eq(s.to_alpha(1), '00'); eq(s.to_alpha(0), 'FF'); eq(s.to_alpha(0.85), '26')
end)

test('drawing uses the active palette and changes it on the fly', function()
	local s = play(95)
	mock.set('script-opts', {['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12,background=112233,background_text=e6edf3'})
	local data = overlay(s).data
	assert(data:find('\\1c&H332211&', 1, true), 'background fill in BGR')
	assert(data:find('\\3c&HE6D45A&', 1, true), 'foreground border in BGR')
	assert(data:find('\\1c&HF3EDE6&', 1, true), 'background_text label')
	assert(data:find('\\1a&H26&', 1, true), 'background opacity 0.85')
	mock.set('script-opts', {['uosc-color'] = 'background=000000'})
	assert(overlay(s).data:find('\\1c&H000000&', 1, true), 'repainted')
end)

test('without uosc (no uosc-color, no menu type): the button is drawn in the default colours', function()
	local s = play(95)
	mock.uosc = false
	mock.set('script-opts', {})
	local o = overlay(s)
	assert(o.visible, 'shown')
	assert(o.data:find('\\1c&H000000&', 1, true), 'default background')
	assert(o.data:find('\\3c&HFFFFFF&', 1, true), 'default foreground border')
	eq(#mock.logs.error, 0)
end)

test('hover fills with foreground and uses foreground_text', function()
	local s = play(95)
	mock.set('script-opts', {['uosc-color'] = 'foreground=5ad4e6,foreground_text=0b0d12'})
	mock.set('mouse-pos', center(s.layout()))
	local data = overlay(s).data
	assert(data:find('\\1c&HE6D45A&\\1a&H00&', 1, true), 'foreground fill, opaque')
	assert(data:find('\\1c&H120D0B&', 1, true), 'foreground_text label')
end)

test('ASS text is escaped', function()
	local s = load()
	eq(s.ass_escape('a{\\b1}b'), 'a\\{\\\239\187\191b1\\}b')
	eq(s.ass_escape('x\ny'), 'x y')
end)

-- Mouse and keyboard ------------------------------------------------------------

test('the click section is enabled only over the visible button', function()
	local s = play(95)
	local sec = section(s)
	eq(sec.flags, 'force')
	eq(sec.enabled, false, 'not hovering')
	local r = s.layout()
	mock.set('mouse-pos', {x = 10, y = 10, hover = true})
	eq(sec.enabled, false, 'elsewhere')
	mock.set('mouse-pos', center(r))
	eq(sec.enabled, true, 'over the button')
	eq(sec.enable_flags, '', 'no window dragging')
	mock.set('mouse-pos', {x = r.x0 - 1, y = r.y0, hover = true})
	eq(sec.enabled, false, 'left the button')
	mock.set('mouse-pos', center(r))
	mock.set('mouse-pos', {x = center(r).x, y = center(r).y, hover = false})
	eq(sec.enabled, false, 'pointer left the window')
end)

test('the section is released when the button hides or the file ends', function()
	local s = play(95)
	mock.set('mouse-pos', center(s.layout()))
	eq(section(s).enabled, true)
	mock.set('time-pos', 200)
	eq(section(s).enabled, false, 'hidden')
	eq(#mock.observers['mouse-pos'], 0, 'mouse-pos no longer observed')
	mock.set('time-pos', 95)
	mock.set('mouse-pos', center(s.layout()))
	eq(section(s).enabled, true)
	mock.events['end-file']()
	eq(section(s).enabled, false, 'end of file')
	eq(overlay(s).visible, false, 'overlay removed')
	mock.set('time-pos', 95)
	eq(s.is_visible(), false, 'no chapters after end-file')
end)

test('mouse bindings: release on the button skips, double click is swallowed', function()
	local s = play(95)
	local sec = section(s)
	eq(sec.bindings[1][1], 'mbtn_left')
	eq(sec.bindings[2][1], 'mbtn_left_dbl'); eq(sec.bindings[2][2], 'ignore')
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	mock.set('mouse-pos', center(s.layout()))
	on_down()
	eq(#mock.commands, 0, 'nothing on press')
	on_up()
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[1], 'seek'); eq(c[2], '180.000'); eq(c[3], 'absolute+exact')
	eq(s.is_visible(), false, 'hidden right after skipping')
	-- Second click of a double click, inside input-doubleclick-time (300 ms).
	mock.advance(0.15)
	mock.set('time-pos', 180.05)
	eq(sec.enabled, true, 'guard keeps the section')
	on_down()
	on_up()
	eq(#mock.commands, 1, 'second click swallowed, one skip only')
	eq(sec.enabled, true, 'still guarded: MBTN_LEFT_DBL lands in our section (ignore)')
	mock.advance(0.2)
	eq(s.guard_active(), false)
	eq(sec.enabled, false, 'section released when the guard runs out')
end)

test('the guard follows input-doubleclick-time and is not used by the key', function()
	local s = play(95)
	mock.props['input-doubleclick-time'] = 500
	local sec = section(s)
	mock.set('mouse-pos', center(s.layout()))
	sec.bindings[1][3](); sec.bindings[1][2]()
	mock.advance(0.4)
	eq(sec.enabled, true, 'still within 500 ms')
	mock.advance(0.2)
	eq(sec.enabled, false, 'after 500 ms')
	mock.set('time-pos', 1310)
	mock.set('mouse-pos', {x = 1, y = 1, hover = true})
	mock.bindings.skip()
	eq(sec.enabled, false, 'keyboard skip: no guard')
	eq(s.guard_active(), false)
end)

test('the guard outlives end-file after a playlist-next skip', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 2
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	mock.set('mouse-pos', center(s.layout()))
	on_down(); on_up()
	eq(mock.commands[1][1], 'playlist-next')
	mock.advance(0.03)
	mock.events['end-file']()
	eq(s.guard_active(), true, 'guard survives the end of the file')
	eq(sec.enabled, true, 'second click still ours')
	-- The file's own state is gone.
	eq(#s.state.ranges, 0, 'no ranges'); eq(s.state.dismissed, nil, 'no dismissal')
	eq(s.state.chapters, nil); eq(s.is_visible(), false)
	eq(#mock.observers['time-pos'], 0, 'time-pos not observed')
	eq(#mock.observers['mouse-pos'], 0, 'mouse-pos not observed')
	on_down(); on_up()
	eq(#mock.commands, 1, 'second click swallowed')
	mock.advance(0.3)
	eq(s.guard_active(), false); eq(sec.enabled, false, 'released by the timer, no file loaded')
end)

test('a click started in the guard never skips a range that appears under it', function()
	local list = chapters({{0, 'Part A'}, {90, 'OP'}, {180, 'Preview'}, {200, 'Part B'}})
	local s = play(95, list, {['hikari-skip-outros'] = 'yes'})
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	local rect = s.layout()
	mock.set('mouse-pos', center(rect))
	on_down(); on_up()
	eq(#mock.commands, 1)
	mock.advance(0.1)
	mock.set('time-pos', 180.02) -- the preview button shows up under the pointer
	eq(s.is_visible(), true)
	mock.set('mouse-pos', center(s.layout()))
	on_down(); on_up()
	eq(#mock.commands, 1, 'second click of the double click does not skip the preview')
	mock.advance(0.5)
	on_down(); on_up()
	eq(#mock.commands, 2, 'a later, separate click does')
end)

test('last ending with a non-finite duration: no skip', function()
	for _, d in ipairs({math.huge, 0 / 0}) do
		local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
		local s = play(1350, list)
		mock.props['playlist-pos'] = 0
		mock.props['playlist-count'] = 1
		mock.props.duration = d
		eq(s.skip(), false, tostring(d))
		eq(#mock.commands, 0); eq(s.is_visible(), true)
	end
end)

test('press on the button and release outside does not skip', function()
	local s = play(95)
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	local r = s.layout()
	mock.set('mouse-pos', center(r))
	on_down()
	mock.set('mouse-pos', {x = 5, y = 5, hover = true})
	eq(sec.enabled, true, 'kept until release')
	on_up()
	eq(#mock.commands, 0, 'no skip')
	eq(sec.enabled, false, 'released')
end)

test('section held while pressed even if the button hides, then released', function()
	local s = play(95)
	local sec = section(s)
	local on_up, on_down = sec.bindings[1][2], sec.bindings[1][3]
	mock.set('mouse-pos', center(s.layout()))
	on_down()
	mock.set('time-pos', 200)
	eq(sec.enabled, true, 'up event still ours')
	on_up()
	eq(#mock.commands, 0, 'no skip once hidden')
	eq(sec.enabled, false)
end)

test('keyboard binding skips only while visible', function()
	local s = play(10)
	assert(mock.bindings.skip, 'skip binding')
	mock.bindings.skip()
	eq(#mock.commands, 0, 'outside the range')
	mock.set('time-pos', 1300.5)
	mock.bindings.skip()
	eq(#mock.commands, 1)
	eq(mock.commands[1][2], '1390.000')
	mock.bindings.skip()
	eq(#mock.commands, 1, 'dismissed: second press ignored')
end)

test('dismissed range comes back after leaving and re-entering it', function()
	local s = play(95)
	mock.bindings.skip()
	mock.set('time-pos', 170) -- seek landed short of the next chapter
	eq(s.is_visible(), false, 'still dismissed')
	mock.set('time-pos', 181)
	mock.set('time-pos', 100) -- user seeks back into the opening
	eq(s.is_visible(), true, 'shown again')
end)

test('ending as last chapter: next playlist entry if there is one', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 3
	mock.bindings.skip()
	eq(#mock.commands, 1); eq(mock.commands[1][1], 'playlist-next')
	eq(s.is_visible(), false)
end)

test('ending as last chapter with nothing next: seek near the end', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 1
	mock.bindings.skip()
	eq(#mock.commands, 1)
	local c = mock.commands[1]
	eq(c[1], 'seek'); eq(c[2], '1419.000'); eq(c[3], 'absolute+exact')
	eq(s.is_visible(), false, 'button gone while the last second plays')
end)

test('a skipped last ending shows again after seeking back into it (keep-open)', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 1
	mock.bindings.skip()
	mock.props['time-pos'] = 1419.02
	mock.events['playback-restart']()
	eq(s.is_visible(), false, 'landed where the skip went')
	mock.set('time-pos', 1419.5)
	eq(s.is_visible(), false, 'still dismissed while the end plays')
	mock.props['time-pos'] = 1320
	mock.events['playback-restart']()
	eq(s.is_visible(), true, 'user went back into the ending')
end)

test('a dismissed range shows again when time goes before its start', function()
	local s = play(95)
	mock.bindings.skip()
	mock.set('time-pos', 170)
	eq(s.is_visible(), false)
	mock.set('time-pos', 89)
	mock.set('time-pos', 92)
	eq(s.is_visible(), true)
end)

test('a duration change keeps the dismissal of a range that still exists', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = play(1350, list)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 1
	mock.bindings.skip()
	mock.set('duration', 1500) -- a stream growing
	mock.set('time-pos', 1419.5)
	eq(s.is_visible(), false, 'still dismissed')
	mock.set('chapter-list', chapters({{0, 'Part A'}, {1200, 'ED'}}))
	mock.set('time-pos', 1250)
	eq(s.is_visible(), true, 'different range: shown')
end)

test('last ending with no next entry and unknown duration: no skip', function()
	local list = chapters({{0, 'Part A'}, {1300, 'ED'}})
	local s = load()
	mock.set('osd-dimensions', {w = 1280, h = 720})
	mock.set('chapter-list', list)
	mock.set('time-pos', 1350)
	mock.props['playlist-pos'] = 0
	mock.props['playlist-count'] = 1
	eq(s.is_visible(), true)
	eq(s.skip(), false, 'nothing to do')
	eq(#mock.commands, 0)
	eq(s.is_visible(), true, 'button stays')
end)

-- Next episode ------------------------------------------------------------------

local NEXT_PROP = 'user-data/hikari_resume/next'
local FILE = '/anime/Show - 05.mkv'
local NEXT = '/anime/Show - 06.mkv'

-- The file playing is FILE, first of a playlist whose second entry is
-- `entry`, and hikari-resume published `published` (default: NEXT for FILE).
local function queue(entry, published)
	mock.props.path = FILE
	mock.props['playlist/1/filename'] = entry or NEXT
	mock.set('playlist-pos', 0)
	mock.set('playlist-count', 2)
	mock.set(NEXT_PROP, published or {path = FILE, next = NEXT})
end

local function label(s) return s.layout() and s.layout().label end

test('next episode: a last-chapter ending with the next episode next reads Next episode', function()
	local s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	eq(label(s), 'Saltar ending ›')
	queue()
	eq(label(s), 'Siguiente episodio ›')
	mock.bindings.skip()
	eq(mock.commands[#mock.commands][1], 'playlist-next')
	eq(s.is_visible(), false)
end)

test('next episode: another entry next, another path or nothing published: Skip ending', function()
	local s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	queue('/anime/Other.mkv')
	eq(label(s), 'Saltar ending ›', 'another file next')
	s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	queue(nil, {path = '/anime/Show - 04.mkv', next = NEXT})
	eq(label(s), 'Saltar ending ›', 'published for another file')
	s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	queue(nil, {})
	eq(label(s), 'Saltar ending ›', 'nothing published')
	-- An ending followed by a preview chapter skips to the preview, as before.
	s = play(1320, EPISODE)
	queue()
	eq(label(s), 'Saltar ending ›')
end)

test('next episode: without an ending, a button for the last 5 %', function()
	local list = chapters({{0, 'Part A'}, {700, 'Part B'}})
	local s = play(1340, list)
	queue()
	eq(s.is_visible(), false, 'before 95 %')
	mock.set('time-pos', 1349)
	eq(label(s), 'Siguiente episodio ›')
	assert(s.overlay.visible, 'drawn')
	mock.set('time-pos', 1419.9)
	eq(s.is_visible(), false, 'gone at the very end')
	mock.set('time-pos', 1400)
	assert(s.skip(), 'skipped')
	eq(mock.commands[#mock.commands][1], 'playlist-next')
	-- Without the next episode next (the playlist changed), it goes.
	s = play(1400, list)
	queue()
	eq(label(s), 'Siguiente episodio ›')
	mock.set('playlist-count', 1)
	eq(s.is_visible(), false, 'the next entry is gone')
	-- A file with no chapters at all gets it too.
	s = play(1400, {})
	queue()
	eq(label(s), 'Siguiente episodio ›')
end)

test('next episode: compared with one kind of separator, without case on Windows', function()
	local s = load()
	mock.props.platform = 'linux'
	eq(s.same_path('/a//b/c.mkv', '/a/b/c.mkv'), true)
	eq(s.same_path('/a/B.mkv', '/a/b.mkv'), false, 'case counts outside Windows')
	mock.props.platform = 'windows'
	eq(s.same_path('\\\\NAS\\anime\\Show - 06.mkv', '//nas/Anime/show - 06.mkv'), true)
	eq(s.same_path('C:\\a\\b.mkv', 'C:\\a\\c.mkv'), false)
	eq(s.same_path(nil, 'x'), false)
end)

test('next episode: next_episode=no leaves the button as before', function()
	local s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}), {['hikari-skip-next_episode'] = 'no'})
	queue()
	eq(label(s), 'Saltar ending ›')
	s = play(1400, chapters({{0, 'Part A'}, {700, 'Part B'}}), {['hikari-skip-next_episode'] = 'no'})
	queue()
	eq(s.is_visible(), false, 'no button without an ending')
	eq(mock.observers[NEXT_PROP], nil, 'not even watched')
end)

test('next episode: streams are left as they were (hikari-resume publishes nothing for them)', function()
	local s = play(1400, chapters({{0, 'Part A'}, {700, 'Part B'}}))
	mock.props.path = 'https://host/stream?token=x&filename=Show%20-%2005.mkv'
	mock.props['playlist/1/filename'] = 'https://host/stream?token=x&filename=Show%20-%2006.mkv'
	mock.set('playlist-pos', 0)
	mock.set('playlist-count', 2)
	mock.set(NEXT_PROP, {})
	eq(s.is_visible(), false)
	s = play(1350, chapters({{0, 'Part A'}, {1300, 'ED'}}))
	mock.props.path = 'https://host/stream?token=x'
	mock.set('playlist-pos', 0)
	mock.set('playlist-count', 2)
	eq(label(s), 'Saltar ending ›')
end)

test('size options are clamped to finite ranges', function()
	local s = load({['hikari-skip-margin_bottom'] = '1e999', ['hikari-skip-margin_right'] = '-5',
		['hikari-skip-scale'] = '1e999', ['hikari-skip-scale_fullscreen'] = '0', ['hikari-skip-font_size'] = 'nan',
		['hikari-skip-opacity'] = '7'})
	eq(s.opts.margin_bottom, 10000); eq(s.opts.margin_right, 0)
	eq(s.opts.scale, 10); eq(s.opts.scale_fullscreen, 0.1)
	eq(s.opts.font_size, 18); eq(s.opts.opacity, 1)
	s = load({['hikari-skip-margin_bottom'] = 'abc', ['hikari-skip-scale'] = '0/0'})
	eq(s.opts.margin_bottom, 96); eq(s.opts.scale, 1)
end)

test('chapters with infinite times are ignored', function()
	local s = load()
	local list = {{time = 0, title = 'A'}, {time = 90, title = 'OP'}, {time = math.huge, title = 'B'},
		{time = -math.huge, title = 'OP'}}
	eq(#s.build_ranges(list, 1000), 0, 'OP followed only by an infinite chapter: dropped')
	list[#list + 1] = {time = 180, title = 'Part A'}
	local ranges = s.build_ranges(list, 1000)
	eq(#ranges, 1); eq(ranges[1].start, 90); eq(ranges[1].finish, 180)
end)

test('times are formatted with a dot whatever the locale', function()
	local s = load()
	eq(s.format_time(90), '90.000'); eq(s.format_time(1.2345), '1.235'); eq(s.format_time(-3), '0.000')
end)

test('a language switch redraws the button with the new label, wider in Chinese', function()
	local s = play(100)
	local o = overlay(s)
	assert(o.data:find('Saltar opening ›', 1, true), 'Spanish first')
	local width = s.layout().x1 - s.layout().x0
	local updates = o.updates
	mock.set_script_opt('hikari-language', 'en')
	assert(o.data:find('Skip opening ›', 1, true), 'English now')
	eq(o.updates, updates + 1, 'drawn again')
	mock.set_script_opt('hikari-language', 'zh-hans')
	assert(o.data:find('跳过片头 ›', 1, true), 'Chinese')
	assert(s.layout().x1 - s.layout().x0 >= width * 0.6, 'wide characters count double')
	eq(s.text_width('跳过片头 ›'), 10)
	eq(s.text_width('Skip opening ›'), 14)
end)

test('a language switch with no button on screen draws nothing', function()
	local s = play(500)
	local o = overlay(s)
	mock.set_script_opt('hikari-language', 'en')
	eq(o.updates, 0)
	eq(o.visible, false)
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
